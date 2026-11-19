-- MidiGenCcCurve_common_logic.lua
-- Curvas de CC y pitch bend sobre un take. Las formas son funciones puras que
-- devuelven puntos (t de 0 a 1, valor nativo de la lane); apply() los pasa al
-- take. Patron dofile + M={}.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Cc = dofile(script_dir .. "MidiGenCc_common_logic.lua")

local M = {}

local lane_info, encode, matches = Cc.lane_info, Cc.encode, Cc.matches
local floor_ppq, take_hash = Cc.floor_ppq, Cc.take_hash
local read_range, delete_range, insert_events = Cc.read_range, Cc.delete_range, Cc.insert_events

-- Campana con pico ajustable. Nativa: tres puntos con la forma de REAPER.
-- Densa: coseno elevado muestreado cada step_ms, con forma lineal.
-- El ultimo punto vale base con close, o lo si no.
function M.swell(p)
  local pk = math.max(0.01, math.min(0.99, p.peak))
  local last_v = p.close and p.base or p.lo

  if p.resolution ~= "dense" then
    return {
      { t = 0,  v = p.lo,   shape = p.shape, tension = p.tension },
      { t = pk, v = p.hi,   shape = p.shape, tension = p.tension },
      { t = 1,  v = last_v, shape = p.shape, tension = p.tension },
    }
  end

  local n = math.max(2, math.ceil(p.duration_ms / p.step_ms))
  local pts = {}
  for i = 0, n do
    local t = i / n
    local f
    if t <= pk then
      f = 0.5 - 0.5 * math.cos(math.pi * t / pk)
    else
      f = 0.5 + 0.5 * math.cos(math.pi * (t - pk) / (1 - pk))
    end
    local v = (i == n) and last_v or (p.lo + (p.hi - p.lo) * f)
    pts[#pts + 1] = { t = t, v = v, shape = 1, tension = 0 }
  end
  return pts
end

local TWO_PI = 2 * math.pi
local EPS = 1e-9

local function tri(u)
  local f = u - math.floor(u)
  if f < 0.25 then return 4 * f end
  if f < 0.75 then return 2 - 4 * f end
  return 4 * f - 4
end

-- f(u): onda de periodo 1 entre -1 y 1. corners: puntos del periodo donde la
-- forma nativa necesita un punto; ext marca extremos, jump saltos verticales.
local WAVES = {
  sine     = { f = function(u) return math.sin(TWO_PI * u) end, corners = { 0.25, 0.75 }, ext = true },
  triangle = { f = tri, corners = { 0.25, 0.75 }, ext = true },
  square   = { f = function(u) return (u - math.floor(u)) < 0.5 and 1 or -1 end, corners = { 0, 0.5 }, jump = true },
  saw_up   = { f = function(u) return 2 * (u - math.floor(u)) - 1 end, corners = { 0 }, jump = true },
  saw_down = { f = function(u) return 1 - 2 * (u - math.floor(u)) end, corners = { 0 }, jump = true },
}

-- Avance 0 a 1 de una forma de REAPER, para el modo denso.
local function shape_curve(shape, t)
  if shape == 0 then return t >= 1 and 1 or 0 end
  if shape == 2 then return 0.5 - 0.5 * math.cos(math.pi * t) end
  if shape == 3 then return math.sin(math.pi * t / 2) end
  if shape == 4 then return 1 - math.cos(math.pi * t / 2) end
  return t
end

local function closing_point(p)
  return { t = 1, v = p.base, shape = 0, tension = 0 }
end

-- Rampa de from a to con la forma de REAPER elegida. Con close, el ultimo
-- punto del rango devuelve la lane a base.
function M.ramp(p)
  local shape = p.shape or 1
  local pts = {}
  if p.resolution ~= "dense" then
    pts[1] = { t = 0, v = p.from, shape = shape, tension = p.tension }
    pts[2] = { t = 1, v = p.to, shape = shape, tension = p.tension }
  else
    local n = math.max(2, math.ceil(p.duration_ms / p.step_ms))
    for i = 0, n do
      local t = i / n
      pts[#pts + 1] = { t = t, v = p.from + (p.to - p.from) * shape_curve(shape, t), shape = 1, tension = 0 }
    end
  end
  if p.close then pts[#pts + 1] = closing_point(p) end
  return pts
end

-- Forma del segmento entre dos puntos nativos de un oscilador.
local function seg_shape(kind, a, b)
  if kind == "square" then return 0 end
  if kind ~= "sine" then return 1 end
  if a.ext and b.ext then return 2 end
  if b.ext then return 3 end
  if a.ext then return 4 end
  return 1
end

-- Oscilador alrededor de center con amplitud depth. La cantidad de ciclos sale
-- de hz (segun la duracion del rango) o de cycles. fade_in hace entrar la
-- amplitud de a poco durante esa fraccion del rango.
function M.osc(p)
  local kind = WAVES[p.wave] and p.wave or "sine"
  local def = WAVES[kind]
  local cycles = p.hz and p.hz * p.duration_ms / 1000 or p.cycles or 1
  if cycles <= 0 then cycles = 1 end
  local u0 = p.phase or 0
  local u1 = u0 + cycles
  local fade = p.fade_in or 0

  local function value(t, unit)
    local amp = (fade > 0) and math.min(1, t / fade) or 1
    return p.center + p.depth * amp * unit
  end

  local pts = {}
  if p.resolution == "dense" then
    local n = math.max(2, math.ceil(p.duration_ms / p.step_ms))
    local shape = (kind == "square") and 0 or 1
    for i = 0, n do
      local t = i / n
      pts[#pts + 1] = { t = t, v = value(t, def.f(u0 + cycles * t)), shape = shape, tension = 0 }
    end
  else
    local keys = { { u = u0, unit = def.f(u0 + EPS), ext = false } }
    for k = math.floor(u0) - 1, math.ceil(u1) do
      for _, c in ipairs(def.corners) do
        local u = k + c
        if u > u0 + EPS and u < u1 - EPS then
          if def.jump then
            keys[#keys + 1] = { u = u, unit = def.f(u - EPS), ext = false }
            keys[#keys + 1] = { u = u, unit = def.f(u + EPS), ext = false }
          else
            keys[#keys + 1] = { u = u, unit = def.f(u), ext = def.ext }
          end
        end
      end
    end
    keys[#keys + 1] = { u = u1, unit = def.f(u1 - EPS), ext = false }
    for i, key in ipairs(keys) do
      local t = (key.u - u0) / cycles
      pts[#pts + 1] = {
        t = t, v = value(t, key.unit),
        shape = seg_shape(kind, key, keys[i + 1] or key), tension = 0,
      }
    end
  end
  if p.close then pts[#pts + 1] = closing_point(p) end
  return pts
end

-- Sosten plano en center.
local function flat(p)
  return {
    { t = 0, v = p.center, shape = 0, tension = 0 },
    { t = 1, v = p.center, shape = 0, tension = 0 },
  }
end

local HOLDS = { flat = flat, swell = M.swell, ramp = M.ramp, osc = M.osc }

-- Valores por lane (ademas de base) que necesita cada sosten.
M.HOLD_KEYS = {
  flat = { "center" },
  osc = { "center", "depth" },
  swell = { "lo", "hi" },
  ramp = { "from", "to" },
}

-- Puntos de una transicion de v_a a v_b entre t_a y t_b, sin el punto final.
-- Nativa: un punto con la forma de REAPER. Densa: muestras cada step_ms.
local function transition(p, st, t_a, t_b, v_a, v_b)
  local shape, tension = st.shape or 2, st.tension or 0
  if p.resolution ~= "dense" then
    return { { t = t_a, v = v_a, shape = shape, tension = tension } }
  end
  local n = math.max(1, math.ceil((t_b - t_a) * p.duration_ms / p.step_ms))
  local pts = {}
  for i = 0, n - 1 do
    local u = i / n
    pts[#pts + 1] = {
      t = t_a + (t_b - t_a) * u,
      v = v_a + (v_b - v_a) * shape_curve(shape, u),
      shape = 1, tension = 0,
    }
  end
  return pts
end

-- Bend en tres etapas: subida de base (o del valor previo, p.start) al inicio
-- del sosten, sosten con la forma de p.hold y bajada a base al final del rango.
-- Cada etapa dura ms o un porcentaje del rango; si subida y bajada no entran,
-- se escalan y el sosten queda en cero.
function M.bend(p)
  local dur = math.max(p.duration_ms, 1)
  local function ms_of(st)
    local a = math.max(0, st.amount or 0)
    return (st.unit == "pct") and dur * a / 100 or a
  end
  local rise_ms, fall_ms = ms_of(p.rise), ms_of(p.fall)
  if rise_ms + fall_ms > dur then
    local k = dur / (rise_ms + fall_ms)
    rise_ms, fall_ms = rise_ms * k, fall_ms * k
  end
  local t_rise, t_fall = rise_ms / dur, 1 - fall_ms / dur

  local q = {}
  for k, v in pairs(p) do q[k] = v end
  for k, v in pairs(p.hold) do q[k] = v end
  q.close = false
  q.shape = q.shape or 2
  q.tension = q.tension or 0
  q.peak = q.peak or 0.5
  q.duration_ms = math.max(dur - rise_ms - fall_ms, 1)
  local hold = HOLDS[p.hold.engine](q)
  if t_fall - t_rise <= EPS then hold = { hold[1] } end

  -- el ultimo punto del sosten pasa a ser el inicio de la bajada
  local last = table.remove(hold)
  local rise_to = hold[1] and hold[1].v or last.v
  local pts = transition(p, p.rise, 0, t_rise, p.start or p.base, rise_to)
  for _, pt in ipairs(hold) do
    pts[#pts + 1] = {
      t = t_rise + pt.t * (t_fall - t_rise),
      v = pt.v, shape = pt.shape, tension = pt.tension,
    }
  end
  for _, pt in ipairs(transition(p, p.fall, t_fall, 1, last.v, p.base)) do
    pts[#pts + 1] = pt
  end
  pts[#pts + 1] = { t = 1, v = p.base, shape = 0, tension = 0 }
  return pts
end

local ENGINES = { swell = M.swell, ramp = M.ramp, osc = M.osc, bend = M.bend }

-- Rango en tiempo de proyecto: time selection; si no hay, de la primera nota
-- seleccionada al final de la ultima. El tercer valor dice el origen.
function M.resolve_range(take)
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if te > ts then return ts, te, "time selection" end

  local first, last
  local _, count = reaper.MIDI_CountEvts(take)
  for i = 0, count - 1 do
    local _, sel, _, s, e = reaper.MIDI_GetNote(take, i)
    if sel then
      if not first or s < first then first = s end
      if not last or e > last then last = e end
    end
  end
  if not first then return nil end
  return reaper.MIDI_GetProjTimeFromPPQPos(take, first),
         reaper.MIDI_GetProjTimeFromPPQPos(take, last),
         "notas seleccionadas"
end

-- Factor de los valores del preset a unidades nativas de la lane. En pitch
-- bend los valores estan en cents y 8192 equivale al bend range completo.
local function native_factor(kind, p)
  if kind ~= "pitchbend" then return 1 end
  return 8192 / ((p.bend_range_st or 2) * 100)
end

-- Puntos de la curva de p (t de 0 a 1, valor nativo de la lane) para una lane
-- de tipo kind ("cc" o "pitchbend"). Los valores del preset en pitch bend
-- estan en cents. start: valor nativo desde el que parte la subida del bend
-- (por defecto, base). nil y un mensaje si el preset no sirve.
function M.build_points(p, kind, duration_ms, start)
  local engine = ENGINES[p.engine]
  if not engine then return nil, "Motor inexistente en el preset: " .. tostring(p.engine) end
  local vals = p[kind]
  if not vals then return nil, "El preset no define valores para " .. kind .. "." end
  if p.engine == "bend" then
    local keys = p.hold and M.HOLD_KEYS[p.hold.engine]
    if not (p.rise and p.fall and keys) then
      return nil, "El bend necesita rise, fall y un hold valido."
    end
    if vals.base == nil then return nil, "El preset no define base para esta lane." end
    for _, k in ipairs(keys) do
      if vals[k] == nil then return nil, "El preset no define " .. k .. " para esta lane." end
    end
  end
  local q = {}
  for k, v in pairs(p) do q[k] = v end
  local f = native_factor(kind, p)
  for k, v in pairs(vals) do q[k] = v * f end
  q.duration_ms = duration_ms
  q.start = start
  return engine(q)
end

-- Valores de la curva en n + 1 posiciones entre 0 y 1, segun la forma de cada
-- segmento (el bezier se aproxima como lineal). Para la vista previa.
function M.sample(points, n)
  local out, j = {}, 1
  for i = 0, n do
    local t = i / n
    while points[j + 1] and points[j + 1].t <= t do j = j + 1 end
    local a, b = points[j], points[j + 1]
    local v = a.v
    if b then
      local span = b.t - a.t
      local u = span > 0 and math.max(0, (t - a.t) / span) or 1
      v = a.v + (b.v - a.v) * shape_curve(a.shape or 1, u)
    end
    out[#out + 1] = v
  end
  return out
end

-- Valor nativo de un evento de la lane (inverso de encode).
local function decode(info, msg2, msg3)
  if info.kind == "pitchbend" then return msg3 * 128 + msg2 - 8192 end
  return msg3
end

-- Valor del ultimo evento de la lane y el canal antes de ppq; nil si no hay.
local function value_before(take, info, chan, ppq)
  local best_p, best_v
  local _, _, cc_count = reaper.MIDI_CountEvts(take)
  for i = 0, cc_count - 1 do
    local _, _, _, p, chanmsg, ch, m2, m3 = reaper.MIDI_GetCC(take, i)
    if p < ppq and matches(info, chan, chanmsg, ch, m2) and (not best_p or p >= best_p) then
      best_p, best_v = p, decode(info, m2, m3)
    end
  end
  return best_v
end

-- Eventos listos para insertar en [ppq0, ppq1]. tg: { info, chan }. Sin tocar
-- el take. Dos puntos en el mismo tick: el anterior retrocede un tick.
local function curve_events(take, tg, ppq0, ppq1, p)
  local t0 = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq0)
  local t1 = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq1)
  local start
  if p.rise and p.rise.from_previous then
    start = value_before(take, tg.info, tg.chan, ppq0)
  end
  local points, err = M.build_points(p, tg.info.kind, (t1 - t0) * 1000, start)
  if not points then return nil, err end

  local events = {}
  for _, pt in ipairs(points) do
    local ppq = floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t0 + pt.t * (t1 - t0)))
    ppq = math.max(ppq0, math.min(ppq1, ppq))
    events[#events + 1] = { ppq = ppq, v = pt.v, shape = pt.shape, tension = pt.tension or 0 }
  end
  for i = #events - 1, 1, -1 do
    if events[i].ppq >= events[i + 1].ppq then events[i].ppq = events[i + 1].ppq - 1 end
  end
  while #events > 0 and events[1].ppq < ppq0 do table.remove(events, 1) end
  for _, ev in ipairs(events) do
    ev.msg2, ev.msg3 = encode(tg.info, ev.v)
    ev.chanmsg, ev.chan = tg.info.chanmsg, tg.chan
  end
  return events
end

-- Lane y canal sobre los que escribe p en el editor: { info, chan, chan_raw }.
function M.target(editor, p)
  local lane = p.lane
  if lane == "active" then
    lane = reaper.MIDIEditor_GetSetting_int(editor, "last_clicked_cc_lane")
  end
  local info = lane_info(lane)
  if not info then
    return nil, "La lane (" .. tostring(lane) .. ") no es un CC de 7 bits ni pitch bend."
  end
  local chan_raw = reaper.MIDIEditor_GetSetting_int(editor, "default_note_chan")
  local chan = (p.channel == "active") and chan_raw or (p.channel - 1)
  return { info = info, chan = chan, chan_raw = chan_raw }
end

-- Ultima curva aplicada: take, hash, lane, canal, rango en ticks y los eventos
-- originales de ese rango. Permite rehacerla desde el original.
local session

-- Aplica la curva de p al take del editor. Devuelve la cantidad de puntos y
-- los datos de lo escrito; sin curva posible, nil y el motivo.
function M.apply(editor, p)
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    return nil, "El MIDI Editor no tiene un take valido."
  end
  local tg, err = M.target(editor, p)
  if not tg then return nil, err end

  local t0, t1, source = M.resolve_range(take)
  if not t0 or t1 <= t0 then return nil, "Sin time selection ni notas seleccionadas." end
  local ppq0 = math.max(0, floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t0)))
  local ppq1 = floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t1))
  if ppq1 <= ppq0 then return nil, "Rango vacio." end

  local events, perr = curve_events(take, tg, ppq0, ppq1, p)
  if not events then return nil, perr end
  local originals = read_range(take, tg.info, tg.chan, ppq0, ppq1)

  if p.undo then reaper.Undo_BeginBlock() end
  if p.mode == "replace" then delete_range(take, tg.info, tg.chan, ppq0, ppq1) end
  insert_events(take, events)
  if p.undo then reaper.Undo_EndBlock("Draw CC curve (" .. (p.name or "") .. ")", -1) end

  session = {
    take = take, hash = take_hash(take), info = tg.info, chan = tg.chan,
    ppq0 = ppq0, ppq1 = ppq1, originals = originals,
  }
  return #events, {
    lane = tg.info.label, chan_raw = tg.chan_raw, chan = tg.chan,
    t0 = t0, t1 = t1, source = source,
  }
end

-- true si el take no cambio desde la ultima curva aplicada.
function M.can_rerun(take)
  return session ~= nil and session.take == take and take_hash(take) == session.hash
end

-- Rehace la ultima curva con otros params, en la misma lane, canal y rango, y
-- partiendo de los eventos originales. nil y el motivo si no hay sesion valida.
function M.rerun(take, p)
  if not M.can_rerun(take) then return nil, "sin sesion" end
  local s = session
  local events, err = curve_events(take, s, s.ppq0, s.ppq1, p)
  if not events then return nil, err end

  if p.undo then reaper.Undo_BeginBlock() end
  delete_range(take, s.info, s.chan, s.ppq0, s.ppq1)
  if p.mode ~= "replace" then insert_events(take, s.originals) end
  insert_events(take, events)
  if p.undo then reaper.Undo_EndBlock("Draw CC curve (" .. (p.name or "") .. ")", -1) end

  s.hash = take_hash(take)
  return #events
end

-- Inserta un evento de forma cuadrada en el cursor, en la lane y el canal de
-- p. mode: "base", "previous" (sin evento anterior, base) o "value" (en las
-- unidades del preset: valor de CC o cents). Reemplaza el evento de esa lane
-- y canal en el mismo tick. Devuelve el valor escrito (en esas unidades) y la
-- lane; sin punto posible, nil y el motivo.
function M.insert_point(editor, p, mode, value)
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    return nil, "El MIDI Editor no tiene un take valido."
  end
  local tg, err = M.target(editor, p)
  if not tg then return nil, err end

  local ppq = floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, reaper.GetCursorPosition()))
  if ppq < 0 then return nil, "El cursor esta antes del inicio del take." end

  local f = native_factor(tg.info.kind, p)
  local vals = p[tg.info.kind]
  local base = vals and vals.base
  local v
  if mode == "value" then
    v = value
  elseif mode == "previous" then
    local before = value_before(take, tg.info, tg.chan, ppq)
    v = before and before / f or base or 0
  else
    v = base
  end
  if v == nil then return nil, "El preset no define base para esta lane." end

  local m2, m3 = encode(tg.info, v * f)
  if p.undo then reaper.Undo_BeginBlock() end
  delete_range(take, tg.info, tg.chan, ppq, ppq)
  insert_events(take, { {
    ppq = ppq, chanmsg = tg.info.chanmsg, chan = tg.chan,
    msg2 = m2, msg3 = m3, shape = 0, tension = 0,
  } })
  if p.undo then reaper.Undo_EndBlock("Insert CC point", -1) end
  return decode(tg.info, m2, m3) / f, tg.info.label
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Arma los params de apply() a partir de un preset del config.
function M.resolve(config, preset_name)
  local cfg = config.cc_curve
  local preset = cfg.presets[preset_name]
  if not preset then return nil, "preset inexistente: " .. tostring(preset_name) end
  local p = copy(preset)
  p.cc = preset.cc and copy(preset.cc)
  p.pitchbend = preset.pitchbend and copy(preset.pitchbend)
  p.rise = preset.rise and copy(preset.rise)
  p.fall = preset.fall and copy(preset.fall)
  p.hold = preset.hold and copy(preset.hold)
  p.name = preset_name
  p.lane, p.channel, p.mode = cfg.lane, cfg.channel, cfg.mode
  p.resolution = preset.resolution or cfg.resolution
  p.step_ms = cfg.dense_step_ms
  p.bend_range_st = cfg.bend_range_st
  p.undo = config.undo.enabled
  return p
end

local function num(v) return string.format("%.4g", v) end

local function lua_value(v)
  if type(v) == "string" then return '"' .. v .. '"' end
  if type(v) == "number" then return num(v) end
  return tostring(v)
end

local function kind_text(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. " = " .. lua_value(t[k]) end
  return "{ " .. table.concat(out, ", ") .. " }"
end

-- Texto Lua del preset vigente, para pegar en MidiGen_config.lua.
function M.preset_text(p)
  local head = { 'engine = "' .. p.engine .. '"' }
  if p.wave then head[#head + 1] = 'wave = "' .. p.wave .. '"' end
  for _, k in ipairs({ "peak", "hz", "cycles", "phase", "fade_in" }) do
    if p[k] ~= nil then head[#head + 1] = k .. " = " .. num(p[k]) end
  end
  if p.engine ~= "bend" then
    head[#head + 1] = "close = " .. tostring(p.close and true or false)
    head[#head + 1] = "shape = " .. num(p.shape or 1)
    head[#head + 1] = "tension = " .. num(p.tension or 0)
  end
  head[#head + 1] = 'resolution = "' .. p.resolution .. '"'

  local lines = { "-- en cc_curve.presets:", '["Custom"] = {', "    " .. table.concat(head, ", ") .. "," }
  for _, name in ipairs({ "rise", "hold", "fall" }) do
    if p.engine == "bend" and p[name] then
      lines[#lines + 1] = "    " .. name .. " = " .. kind_text(p[name]) .. ","
    end
  end
  if p.cc then lines[#lines + 1] = "    cc = " .. kind_text(p.cc) .. "," end
  if p.pitchbend then lines[#lines + 1] = "    pitchbend = " .. kind_text(p.pitchbend) .. "," end
  lines[#lines + 1] = "},"
  return table.concat(lines, "\n")
end

local STATE_SEC, STATE_KEY = "Nik_MidiGen_CcCurve", "state_v2"
local SCALARS = { "peak", "shape", "tension", "phase", "fade_in", "bend_range_st" }
local RATES = { "hz", "cycles" }
-- Claves de valores por lane que puede necesitar el sosten de un bend, y claves
-- numericas de las etapas.
local HOLD_VALUE_KEYS = { center = true, depth = true, lo = true, hi = true, from = true, to = true }
local STAGE_NUMBERS = {
  amount = true, shape = true, tension = true, phase = true, fade_in = true,
  peak = true, hz = true, cycles = true,
}

-- Guarda los params vigentes (persistente entre sesiones).
function M.save(p)
  local parts = {
    "name=" .. (p.name or ""),
    "lane=" .. tostring(p.lane),
    "channel=" .. tostring(p.channel),
    "mode=" .. p.mode,
    "resolution=" .. p.resolution,
    "close=" .. tostring(p.close and true or false),
  }
  if p.wave then parts[#parts + 1] = "wave=" .. p.wave end
  for _, list in ipairs({ SCALARS, RATES }) do
    for _, k in ipairs(list) do
      if p[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(p[k]) end
    end
  end
  for _, kind in ipairs({ "cc", "pitchbend", "rise", "fall", "hold" }) do
    for k, v in pairs(p[kind] or {}) do
      parts[#parts + 1] = kind .. "." .. k .. "=" .. tostring(v)
    end
  end
  reaper.SetExtState(STATE_SEC, STATE_KEY, table.concat(parts, "|"), true)
end

-- Params guardados sobre la base del preset guardado; sin estado valido, el
-- preset por defecto del config. Solo se aplican valores que el preset tiene.
function M.load(config)
  local saved = {}
  for k, v in reaper.GetExtState(STATE_SEC, STATE_KEY):gmatch("([%w_%.]+)=([^|]*)") do
    saved[k] = v
  end
  local p, err = M.resolve(config, saved.name)
  if not p then p, err = M.resolve(config, config.cc_curve.preset) end
  if not p then return nil, err end

  if saved.lane == "active" or saved.lane == "pitchbend" then
    p.lane = saved.lane
  elseif lane_info(tonumber(saved.lane)) then
    p.lane = tonumber(saved.lane)
  end
  local ch = tonumber(saved.channel)
  if saved.channel == "active" then
    p.channel = "active"
  elseif ch and ch >= 1 and ch <= 16 then
    p.channel = math.floor(ch)
  end
  if saved.mode == "replace" or saved.mode == "merge" then p.mode = saved.mode end
  if saved.resolution == "native" or saved.resolution == "dense" then p.resolution = saved.resolution end
  if saved.close == "true" or saved.close == "false" then p.close = saved.close == "true" end
  if p.wave and WAVES[saved.wave] then p.wave = saved.wave end

  for _, k in ipairs(SCALARS) do
    local v = tonumber(saved[k])
    if v and p[k] ~= nil then p[k] = v end
  end
  if p.engine == "osc" then
    local hz, cycles = tonumber(saved.hz), tonumber(saved.cycles)
    if hz then
      p.hz, p.cycles = hz, nil
    elseif cycles then
      p.cycles, p.hz = cycles, nil
    end
  end
  for key, val in pairs(saved) do
    local kind, k = key:match("^(%w+)%.(.+)$")
    local v = tonumber(val)
    local t = kind and p[kind]
    if type(t) == "table" and v then
      if kind == "cc" or kind == "pitchbend" then
        if t[k] ~= nil or (p.engine == "bend" and HOLD_VALUE_KEYS[k]) then t[k] = v end
      elseif STAGE_NUMBERS[k] then
        t[k] = v
      end
    end
  end

  for _, name in ipairs({ "rise", "fall" }) do
    local unit = saved[name .. ".unit"]
    if p[name] and (unit == "ms" or unit == "pct") then p[name].unit = unit end
  end
  local from_prev = saved["rise.from_previous"]
  if p.rise and (from_prev == "true" or from_prev == "false") then
    p.rise.from_previous = from_prev == "true"
  end
  if p.hold then
    local e, w = saved["hold.engine"], saved["hold.wave"]
    if e and HOLDS[e] then p.hold.engine = e end
    if w and WAVES[w] then p.hold.wave = w end
    local hz, cy = tonumber(saved["hold.hz"]), tonumber(saved["hold.cycles"])
    if hz then
      p.hold.hz, p.hold.cycles = hz, nil
    elseif cy then
      p.hold.cycles, p.hold.hz = cy, nil
    end
  end
  return p
end

local function warn(msg)
  reaper.ShowMessageBox(msg, "Curva CC", 0)
end

-- Aplica el ultimo estado guardado (o el preset por defecto del config) al
-- editor activo.
function M.run(config)
  local editor = reaper.MIDIEditor_GetActive()
  if not editor then return end
  local cfg = config.cc_curve

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

  if cfg.verbose then
    reaper.ShowConsoleMsg(string.format(
      "CcCurve: preset=%s lane=%s canal_raw=%s canal_usado=%d resolucion=%s puntos=%d rango=%.3f-%.3f s (%s)\n",
      p.name, info.lane, tostring(info.chan_raw), info.chan, p.resolution, n, info.t0, info.t1, info.source))
  end
end

return M