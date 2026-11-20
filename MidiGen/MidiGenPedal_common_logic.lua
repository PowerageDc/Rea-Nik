-- MidiGenPedal_common_logic.lua
-- Pedal de sustain (CC64) de un teclado sobre una seleccion: levanta y vuelve
-- a bajar el pedal con los acordes o los compases, o lo sostiene sobre todo el
-- rango. Sin UI: quien lo consume arma los params con resolve(). Patron
-- dofile + M={}.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Cc = dofile(script_dir .. "MidiGenCc_common_logic.lua")
local CcCurve = dofile(script_dir .. "MidiGenCcCurve_common_logic.lua")

local M = {}

local STYLES = { legato = true, sustained = true }
local CHANGES = { chord = true, bar = true }
local STARTS = { range = true, first_attack = true }
local MODES = { replace = true, merge = true }
local NUMBERS = {
  "chord_window_ms", "min_gap_ms", "offset_ms", "dip_ms",
  "down_value", "up_value", "shape", "transition_ms",
}

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- true si v es "active", o un numero de canal de 1 a 16; con all, tambien "all".
local function valid_channel(v, all)
  if v == "active" or (all and v == "all") then return true end
  return type(v) == "number" and v >= 1 and v <= 16 and v == math.floor(v)
end

-- Arma los params del pedal a partir de un preset del config. nil y el motivo
-- si el preset no existe o sus valores no son validos.
function M.resolve(config, preset_name)
  local cfg = config.pedal
  local preset = cfg.presets[preset_name]
  if not preset then return nil, "preset inexistente: " .. tostring(preset_name) end
  if not STYLES[preset.style] then return nil, "style invalido: " .. tostring(preset.style) end
  if not CHANGES[preset.change] then return nil, "change invalido: " .. tostring(preset.change) end
  if not STARTS[preset.start] then return nil, "start invalido: " .. tostring(preset.start) end
  for _, k in ipairs(NUMBERS) do
    if type(preset[k]) ~= "number" then return nil, "falta el numero " .. k end
  end
  if preset.down_value <= preset.up_value then
    return nil, "down_value tiene que ser mayor que up_value"
  end
  if not valid_channel(cfg.channel, false) then
    return nil, "channel invalido: " .. tostring(cfg.channel)
  end
  if not valid_channel(cfg.source_channel, true) then
    return nil, "source_channel invalido: " .. tostring(cfg.source_channel)
  end
  if not MODES[cfg.mode] then return nil, "mode invalido: " .. tostring(cfg.mode) end

  local p = copy(preset)
  p.name = preset_name
  p.channel = cfg.channel
  p.source_channel = cfg.source_channel
  p.mode = cfg.mode
  p.close = preset.close == true
  p.lift_first = preset.lift_first == true
  p.undo = config.undo.enabled
  return p
end

local PEDAL_CC = 64
local floor_ppq = Cc.floor_ppq

-- Milisegundos a ticks en la posicion ppq, con el tempo del mapa en ese punto.
local function ms_to_ticks(take, ppq, ms)
  local t = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
  return reaper.MIDI_GetPPQPosFromProjTime(take, t + ms / 1000) - ppq
end

-- Rango (time selection; si no hay, notas seleccionadas) y notas no muteadas
-- del take. El canal activo sale del editor.
function M.read_input(take, editor)
  local t0, t1, source = CcCurve.resolve_range(take)
  local notes = {}
  local _, count = reaper.MIDI_CountEvts(take)
  for i = 0, count - 1 do
    local _, _, muted, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if not muted then
      notes[#notes + 1] = { s = s, e = e, chan = chan, pitch = pitch, vel = vel }
    end
  end
  local active = editor and reaper.MIDIEditor_GetSetting_int(editor, "default_note_chan") or 0
  return { t0 = t0, t1 = t1, source = source, notes = notes, active_chan = active }
end

local function from_source(p, input, chan)
  local sc = p.source_channel
  if sc == "all" then return true end
  if sc == "active" then return chan == input.active_chan end
  return chan == sc - 1
end

M.from_source = from_source

-- Un punto por acorde (inicio del primero; los siguientes a menos de
-- window_ms se suman a el). Dos puntos a menos de gap_ms: queda el primero.
local function chord_points(take, attacks, window_ms, gap_ms)
  local pts, ref, win = {}, nil, 0
  for _, s in ipairs(attacks) do
    if not ref or s - ref > win then
      ref = s
      win = ms_to_ticks(take, ref, window_ms)
      local last = pts[#pts]
      if not last or ref - last >= ms_to_ticks(take, last, gap_ms) then
        pts[#pts + 1] = ref
      end
    end
  end
  return pts
end

-- Inicio de cada compas dentro de [ppq0, ppq1). Arranca un compas antes del
-- que contiene el inicio, por si el indice de compas viene corrido.
local function bar_points(take, ppq0, ppq1)
  local _, measure = reaper.TimeMap2_timeToBeats(0, reaper.MIDI_GetProjTimeFromPPQPos(take, ppq0))
  local pts = {}
  for i = 0, 100000 do
    local t = reaper.TimeMap_GetMeasureInfo(0, math.max(0, measure - 1) + i)
    local ppq = floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t))
    if ppq >= ppq1 then break end
    if ppq >= ppq0 and ppq ~= pts[#pts] then pts[#pts + 1] = ppq end
  end
  return pts
end

-- Eventos CC64 del pedal sobre el rango de input, sin tocar el take. Devuelve
-- los eventos y los datos del plan; sin pedal posible, nil y el motivo.
function M.plan(take, p, input)
  if not input.t0 or input.t1 <= input.t0 then
    return nil, "Sin time selection ni notas seleccionadas."
  end
  local ppq0 = math.max(0, floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, input.t0)))
  local ppq1 = floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, input.t1))
  if ppq1 <= ppq0 then return nil, "Rango vacio." end

  local info = Cc.lane_info(PEDAL_CC)
  local chan = (p.channel == "active") and input.active_chan or (p.channel - 1)

  local attacks = {}
  for _, n in ipairs(input.notes) do
    if n.s >= ppq0 and n.s < ppq1 and from_source(p, input, n.chan) then
      attacks[#attacks + 1] = n.s
    end
  end
  table.sort(attacks)

  local pts = {}
  if p.style == "legato" then
    if p.change == "bar" then
      pts = bar_points(take, ppq0, ppq1)
    else
      pts = chord_points(take, attacks, p.chord_window_ms, p.min_gap_ms)
    end
    if #pts == 0 then
      if p.change == "chord" and #attacks == 0 and p.source_channel ~= "all" then
        return nil, "Ninguna nota del rango es del canal de origen elegido."
      end
      return nil, "Sin puntos de cambio en el rango."
    end
  end

  local first = attacks[1]
  if p.start == "first_attack" and not first then return nil, "Sin ataques en el rango." end
  local start_ppq = (p.start == "first_attack") and first or ppq0

  local events = {}
  local function add(ppq, v, shape)
    local m2, m3 = Cc.encode(info, v)
    events[#events + 1] = {
      ppq = ppq, chanmsg = info.chanmsg, chan = chan, msg2 = m2, msg3 = m3,
      shape = shape or 0, tension = 0,
    }
  end

  add(start_ppq, p.down_value)
  local last, dips = start_ppq, 0

  if p.style == "legato" then
    -- en acordes, el primer punto levanta solo con lift_first (sin ella se
    -- asume que no hay acorde anterior que cortar); en compases, levanta todo
    -- punto posterior al inicio. Con lift_first, un levantado anterior al
    -- inicio se recorta al inicio.
    local lifts = {}
    for i = (p.change == "bar" or p.lift_first) and 1 or 2, #pts do
      if pts[i] > start_ppq or (p.lift_first and pts[i] == start_ppq) then
        local lift = floor_ppq(pts[i] + ms_to_ticks(take, pts[i], p.offset_ms))
        if p.lift_first and lift < start_ppq then lift = start_ppq end
        local prev = lifts[#lifts] or (p.lift_first and start_ppq - 1 or start_ppq)
        if lift > prev and lift < ppq1 then
          lifts[#lifts + 1] = lift
        end
      end
    end
    for k, lift in ipairs(lifts) do
      local limit = (lifts[k + 1] or ppq1) - 1
      local dip = math.min(floor_ppq(ms_to_ticks(take, lift, p.dip_ms)), limit - lift)
      if dip >= 1 then
        local tr = 0
        if p.shape ~= 0 then
          tr = math.min(floor_ppq(ms_to_ticks(take, lift, p.transition_ms)), (dip - 1) // 2)
        end
        if tr >= 1 then
          add(lift, p.down_value, p.shape)
          add(lift + tr, p.up_value)
          add(lift + dip - tr, p.up_value, p.shape)
          add(lift + dip, p.down_value)
        else
          add(lift, p.up_value)
          add(lift + dip, p.down_value)
        end
        last = lift + dip
        dips = dips + 1
      end
    end
    -- un levantado en el inicio reemplaza al presionado inicial
    if events[2] and events[2].ppq == events[1].ppq then table.remove(events, 1) end
  end

  if p.close and ppq1 > last then add(ppq1, 0) end

  return events, {
    t0 = input.t0, t1 = input.t1, source = input.source,
    ppq0 = ppq0, ppq1 = ppq1, start = start_ppq, chan = chan, lane = info.label,
    points = pts, attacks = attacks, changes = dips,
  }
end

-- Ultimo pedal aplicado: take, hash del take completo, entrada, canal, rango
-- en ticks y CC64 originales del rango. Permite rehacerlo desde el original.
local session

-- Escribe el pedal en el take del editor. Devuelve la cantidad de eventos y
-- los datos del plan; sin pedal posible, nil y el motivo.
function M.apply(editor, p)
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    return nil, "El MIDI Editor no tiene un take valido."
  end
  local input = M.read_input(take, editor)
  local events, data = M.plan(take, p, input)
  if not events or type(data) ~= "table" then return nil, tostring(data) end

  local info = Cc.lane_info(PEDAL_CC)
  local originals = Cc.read_range(take, info, data.chan, data.ppq0, data.ppq1)

  if p.undo then reaper.Undo_BeginBlock() end
  if p.mode == "replace" then Cc.delete_range(take, info, data.chan, data.ppq0, data.ppq1) end
  Cc.insert_events(take, events)
  if p.undo then reaper.Undo_EndBlock("Generate sustain pedal (" .. p.name .. ")", -1) end

  session = {
    take = take, hash = Cc.take_hash(take), input = input, info = info,
    chan = data.chan, ppq0 = data.ppq0, ppq1 = data.ppq1, originals = originals,
  }
  return #events, data
end

-- true si el take no cambio desde el ultimo pedal aplicado.
function M.can_rerun(take)
  return session ~= nil and session.take == take and Cc.take_hash(take) == session.hash
end

-- Rehace el ultimo pedal con otros params, sobre la misma entrada, canal y
-- rango, partiendo de los CC64 originales. Devuelve la cantidad de eventos y
-- los datos del plan; nil y el motivo si no hay sesion valida.
function M.rerun(take, p)
  if not M.can_rerun(take) then return nil, "sin sesion" end
  local s = session
  local view = setmetatable({ channel = s.chan + 1 }, { __index = p })
  local events, data = M.plan(take, view, s.input)
  if not events or type(data) ~= "table" then return nil, tostring(data) end

  if p.undo then reaper.Undo_BeginBlock() end
  Cc.delete_range(take, s.info, s.chan, s.ppq0, s.ppq1)
  if p.mode ~= "replace" then Cc.insert_events(take, s.originals) end
  Cc.insert_events(take, events)
  if p.undo then reaper.Undo_EndBlock("Generate sustain pedal (" .. p.name .. ")", -1) end

  s.hash = Cc.take_hash(take)
  return #events, data
end

-- Rango valido de cada numero: lo usa load para descartar lo guardado fuera
-- de rango y el panel para sus sliders.
M.LIMITS = {
  chord_window_ms = { 0, 500 },
  min_gap_ms = { 0, 2000 },
  offset_ms = { -500, 500 },
  dip_ms = { 0, 2000 },
  down_value = { 1, 127 },
  up_value = { 0, 126 },
  shape = { 0, 5 },
  transition_ms = { 0, 500 },
}

local function num(v) return string.format("%.4g", v) end

-- Texto Lua del preset vigente, para pegar en MidiGen_config.lua.
function M.preset_text(p)
  return table.concat({
    "-- en pedal.presets:",
    '["Custom"] = {',
    string.format('    style = "%s", change = "%s", chord_window_ms = %s, min_gap_ms = %s,',
      p.style, p.change, num(p.chord_window_ms), num(p.min_gap_ms)),
    string.format("    offset_ms = %s, dip_ms = %s, down_value = %s, up_value = %s,",
      num(p.offset_ms), num(p.dip_ms), num(p.down_value), num(p.up_value)),
    string.format('    shape = %s, transition_ms = %s, start = "%s", close = %s, lift_first = %s,',
      num(p.shape), num(p.transition_ms), p.start, tostring(p.close), tostring(p.lift_first)),
    "},",
  }, "\n")
end

local STATE_SEC, STATE_KEY = "Nik_MidiGen_Pedal", "state"

-- Guarda los params vigentes (persistente entre sesiones).
function M.save(p)
  local parts = {
    "name=" .. p.name,
    "style=" .. p.style,
    "change=" .. p.change,
    "start=" .. p.start,
    "close=" .. (p.close and "1" or "0"),
    "lift_first=" .. (p.lift_first and "1" or "0"),
    "mode=" .. p.mode,
    "channel=" .. tostring(p.channel),
    "source_channel=" .. tostring(p.source_channel),
  }
  for _, k in ipairs(NUMBERS) do
    parts[#parts + 1] = k .. "=" .. tostring(p[k])
  end
  reaper.SetExtState(STATE_SEC, STATE_KEY, table.concat(parts, "|"), true)
end

-- Params guardados sobre la base del preset guardado; sin estado valido, el
-- preset por defecto del config.
function M.load(config)
  local cfg = config.pedal
  local saved = {}
  for k, v in reaper.GetExtState(STATE_SEC, STATE_KEY):gmatch("([%w_]+)=([^|]*)") do
    saved[k] = v
  end
  local p, err = M.resolve(config, saved.name)
  if not p then p, err = M.resolve(config, cfg.preset) end
  if not p then return nil, err end

  local base_down, base_up = p.down_value, p.up_value
  if STYLES[saved.style] then p.style = saved.style end
  if CHANGES[saved.change] then p.change = saved.change end
  if STARTS[saved.start] then p.start = saved.start end
  if saved.close == "1" or saved.close == "0" then p.close = (saved.close == "1") end
  if saved.lift_first == "1" or saved.lift_first == "0" then p.lift_first = (saved.lift_first == "1") end
  if MODES[saved.mode] then p.mode = saved.mode end
  local ch, sch = tonumber(saved.channel), tonumber(saved.source_channel)
  if saved.channel == "active" then
    p.channel = "active"
  elseif ch and valid_channel(ch, false) then
    p.channel = ch
  end
  if saved.source_channel == "active" or saved.source_channel == "all" then
    p.source_channel = saved.source_channel
  elseif sch and valid_channel(sch, true) then
    p.source_channel = sch
  end
  for _, k in ipairs(NUMBERS) do
    local v, lim = tonumber(saved[k]), M.LIMITS[k]
    if v and v >= lim[1] and v <= lim[2] then p[k] = v end
  end
  p.shape = math.floor(p.shape)
  if p.down_value <= p.up_value then p.down_value, p.up_value = base_down, base_up end
  return p
end

local function warn(msg)
  reaper.ShowMessageBox(msg, "Pedal", 0)
end

-- Aplica el ultimo estado guardado (o el preset por defecto del config) al
-- editor activo.
function M.run(config)
  local editor = reaper.MIDIEditor_GetActive()
  if not editor then return end

  local p, err = M.load(config)
  if not p then
    warn(err)
    return
  end
  local n, info = M.apply(editor, p)
  if not n or type(info) ~= "table" then
    warn(tostring(info))
    return
  end

  if config.pedal.verbose then
    reaper.ShowConsoleMsg(string.format(
      "Pedal: preset=%s canal=%d origen=%s cambios=%d eventos=%d rango=%.3f-%.3f s\n",
      p.name, info.chan + 1, info.source, info.changes, n, info.t0, info.t1))
  end
end

return M