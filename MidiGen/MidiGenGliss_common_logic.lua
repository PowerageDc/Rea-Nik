-- MidiGenGliss_common_logic.lua
-- Glissando de teclado sobre un take: genera notas de un conjunto de teclas
-- (blancas o negras) entre un origen y un destino. Sin UI: quien lo consume
-- arma los params con resolve() y llama a apply(editor, params).
-- Patron dofile + M={}.

local M = {}

-- Pseudoaleatorio determinista en [-1, 1]: misma posicion, mismo resultado.
local function rand(a, b)
  local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
  return (x - math.floor(x)) * 2 - 1
end

local function floor_ppq(x) return math.floor(x + 0.5) end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function reverse(t)
  for i = 1, #t // 2 do t[i], t[#t + 1 - i] = t[#t + 1 - i], t[i] end
end

local function pitch_set(pcs)
  local set = {}
  for _, pc in ipairs(pcs) do set[pc % 12] = true end
  return set
end

-- Notas seleccionadas del take, por inicio y luego por pitch.
local function selected_notes(take)
  local notes = {}
  local _, count = reaper.MIDI_CountEvts(take)
  for i = 0, count - 1 do
    local _, sel, _, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if sel then notes[#notes + 1] = { s = s, e = e, chan = chan, pitch = pitch, vel = vel } end
  end
  table.sort(notes, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    return a.pitch < b.pitch
  end)
  return notes
end

-- Pitches del conjunto estrictamente entre lo y hi, de menor a mayor.
local function between(set, lo, hi)
  local out = {}
  for p = lo + 1, hi - 1 do
    if set[p % 12] then out[#out + 1] = p end
  end
  return out
end

-- Hasta count pitches del conjunto a partir de from en la direccion dir (1 o
-- -1), del mas cercano al mas lejano. from entra solo con include_from.
local function walk(set, from, dir, count, include_from)
  local out, p = {}, include_from and from - dir or from
  while #out < count do
    p = p + dir
    if p < 0 or p > 127 then break end
    if set[p % 12] then out[#out + 1] = p end
  end
  return out
end

-- Arma los params de apply() a partir de un preset del config.
function M.resolve(config, preset_name)
  local cfg = config.gliss
  local preset = cfg.presets[preset_name]
  if not preset then return nil, "preset inexistente: " .. tostring(preset_name) end
  if not cfg.sets[preset.set] then return nil, "conjunto inexistente: " .. tostring(preset.set) end
  return {
    name = preset_name,
    set_name = preset.set,
    sets = cfg.sets,
    contact = math.max(1, math.floor(preset.contact or 1)),
    timing = copy(preset.timing),
    velocity = copy(preset.velocity),
    channel = cfg.channel,
    single = copy(cfg.single),
    range = copy(cfg.range),
    mode = cfg.mode,
    undo = config.undo.enabled,
  }
end

-- Origen del glissando segun la time selection y las notas seleccionadas.
-- Con time selection, ella fija el tiempo (de su inicio a su final) y las
-- notas los pitches (primera y ultima por inicio; una sola nota es el
-- destino; sin notas, range del config). Sin time selection: dos o mas
-- notas rellenan el hueco entre la primera y la ultima; una nota es el
-- destino y el glissando llega a ella (desde single.from_pitch, o desde
-- single.count notas del conjunto). gap indica que las generadas quedan
-- entre dos notas existentes.
local function plan_source(take, p, notes, ts, te)
  local function ppq_of(t) return floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t)) end
  local function proj_of(ppq) return reaper.MIDI_GetProjTimeFromPPQPos(take, ppq) end

  local dest = notes[#notes]
  local away = (p.single.direction == "down") and 1 or -1

  if te > ts then
    local src = { t0 = ts, t1 = te, ppq_end = ppq_of(te), label = "time selection" }
    if #notes >= 2 or not dest then
      local from = (#notes >= 2) and notes[1].pitch or p.range.from_pitch
      local to = (#notes >= 2) and dest.pitch or p.range.to_pitch
      src.pitches = between(p.set, math.min(from, to) - 1, math.max(from, to) + 1)
      if from > to then reverse(src.pitches) end
    else
      src.pitches = walk(p.set, dest.pitch, away, p.single.count, true)
      reverse(src.pitches)
    end
    src.dest = dest or { s = ppq_of(ts), vel = p.range.velocity }
    return src
  end

  if not dest then
    return nil, "Selecciona el destino (una nota), origen y destino (dos o mas), o arma una time selection."
  end
  local src = { dest = dest, ppq_end = dest.s, t1 = proj_of(dest.s) }

  if #notes >= 2 then
    local origin = notes[1]
    src.gap = true
    src.ppq_start = origin.s
    src.t0 = proj_of(origin.s)
    src.pitches = between(p.set, math.min(origin.pitch, dest.pitch), math.max(origin.pitch, dest.pitch))
    if origin.pitch > dest.pitch then reverse(src.pitches) end
    src.label = "hueco entre origen y destino"
    return src
  end

  local from = p.single.from_pitch
  if from and from < dest.pitch then
    src.pitches = between(p.set, from - 1, dest.pitch)
  elseif from then
    src.pitches = between(p.set, dest.pitch, from + 1)
    reverse(src.pitches)
  else
    src.pitches = walk(p.set, dest.pitch, away, p.single.count)
    reverse(src.pitches)
  end
  local n = #src.pitches
  local ms = (p.timing.mode == "per_note") and n * p.timing.note_ms or p.timing.total_ms
  src.t0 = src.t1 - ms / 1000
  src.label = "llegada al destino"
  return src
end

-- Notas a escribir: inicios repartidos entre t0 y t1 con la curva del timing,
-- largo segun el contacto y velocity como factor sobre la del destino.
local function build(take, p, src)
  local pitches = src.pitches
  local n = #pitches
  if n == 0 then return nil, "No hay notas del conjunto para el glissando." end
  local span = src.t1 - src.t0
  if span <= 0 then return nil, "El destino no esta despues del origen." end

  local T = p.timing
  local starts = {}
  for k = 1, n do
    local f = src.gap and k / (n + 1) or (k - 1) / n
    local t = src.t0 + span * f ^ (T.curve or 1)
    if k > 1 and (T.jitter_ms or 0) > 0 then
      t = t + T.jitter_ms / 1000 * rand(src.dest.s, k)
    end
    starts[k] = floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t))
  end

  if not src.gap and starts[1] < 0 then
    return nil, "El glissando empieza antes del inicio del take."
  end
  starts[1] = math.max(starts[1], src.ppq_start and src.ppq_start + 1 or 0)
  for k = 2, n do
    if starts[k] <= starts[k - 1] then starts[k] = starts[k - 1] + 1 end
  end
  if starts[n] >= src.ppq_end then
    return nil, "Intervalo demasiado corto para tantas notas."
  end

  local V, dest = p.velocity, src.dest
  local events = {}
  for k = 1, n do
    local e = (k + p.contact <= n) and starts[k + p.contact] or src.ppq_end
    local fv = (n > 1) and (k - 1) / (n - 1) or 0
    local fac = V.from + (V.to - V.from) * fv ^ (V.curve or 1)
    local vel = floor_ppq(dest.vel * fac + (V.jitter or 0) * rand(dest.s + 1, k))
    events[k] = { s = starts[k], e = e, pitch = pitches[k], vel = math.max(1, math.min(127, vel)) }
  end
  return events, src
end

-- Borra las notas no seleccionadas del canal que arrancan en [lo, hi), salvo
-- las de keep (origen y destino del glissando). Devuelve las borradas.
local function delete_notes(take, chan, lo, hi, keep)
  local protected = {}
  for _, n in ipairs(keep) do
    protected[string.format("%d:%d:%d", n.pitch, n.chan, floor_ppq(n.s))] = true
  end
  local removed = {}
  local _, count = reaper.MIDI_CountEvts(take)
  for i = count - 1, 0, -1 do
    local _, sel, muted, s, e, ch, pitch, vel = reaper.MIDI_GetNote(take, i)
    local key = string.format("%d:%d:%d", pitch, ch, floor_ppq(s))
    if not sel and not protected[key] and ch == chan and s >= lo and s < hi then
      removed[#removed + 1] = { muted = muted, s = s, e = e, chan = ch, pitch = pitch, vel = vel }
      reaper.MIDI_DeleteNote(take, i)
    end
  end
  return removed
end

-- Escribe las notas del glissando (con replace, borra antes las del rango).
-- Devuelve las notas borradas.
local function write(take, p, events, src, chan, input)
  local removed = {}
  if p.mode == "replace" then
    removed = delete_notes(take, chan, events[1].s, src.ppq_end, input.notes)
  end
  for _, ev in ipairs(events) do
    reaper.MIDI_InsertNote(take, false, false, ev.s, ev.e, chan, ev.pitch, ev.vel, true)
  end
  reaper.MIDI_Sort(take)
  return removed
end

local function restore_notes(take, notes)
  for _, n in ipairs(notes) do
    reaper.MIDI_InsertNote(take, false, n.muted, n.s, n.e, n.chan, n.pitch, n.vel, true)
  end
end

local function note_key(pitch, chan, s, e, vel)
  return string.format("%d:%d:%d:%d:%d", pitch, chan, floor_ppq(s), floor_ppq(e), vel)
end

-- Borra del take las notas que escribio la ultima aplicacion.
local function remove_written(take, s)
  local wanted = {}
  for _, w in ipairs(s.written) do
    local key = note_key(w.pitch, s.chan, w.s, w.e, w.vel)
    wanted[key] = (wanted[key] or 0) + 1
  end
  local _, count = reaper.MIDI_CountEvts(take)
  for i = count - 1, 0, -1 do
    local _, _, _, st, en, ch, pitch, vel = reaper.MIDI_GetNote(take, i)
    local key = note_key(pitch, ch, st, en, vel)
    if (wanted[key] or 0) > 0 then
      wanted[key] = wanted[key] - 1
      reaper.MIDI_DeleteNote(take, i)
    end
  end
end

local function take_hash(take)
  local _, h = reaper.MIDI_GetHash(take, false, "")
  return h
end

-- Ultimo glissando aplicado: take, hash del take completo, entrada (notas de
-- origen y destino, time selection), canal, notas escritas y notas borradas.
-- Permite rehacerlo desde el original.
local session

-- Escribe el glissando en el take del editor. Devuelve la cantidad de notas
-- y los datos de lo escrito; sin glissando posible, nil y el motivo.
function M.apply(editor, p)
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    return nil, "El MIDI Editor no tiene un take valido."
  end
  local input = M.read_input(take)
  local events, src = M.plan(take, p, input)
  if not events or type(src) ~= "table" then return nil, tostring(src) end

  local chan_raw = reaper.MIDIEditor_GetSetting_int(editor, "default_note_chan")
  local chan = (p.channel == "active") and chan_raw or (p.channel - 1)

  if p.undo then reaper.Undo_BeginBlock() end
  local removed = write(take, p, events, src, chan, input)
  if p.undo then reaper.Undo_EndBlock("Generate glissando (" .. p.name .. ")", -1) end

  session = {
    take = take, hash = take_hash(take), input = input, chan = chan,
    written = events, removed = removed,
  }
  return #events, { label = src.label, chan = chan, chan_raw = chan_raw }
end

-- Notas seleccionadas y time selection vigentes: lo que define el glissando.
function M.read_input(take)
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return { notes = selected_notes(take), ts = ts, te = te }
end

-- Notas que escribiria el glissando para esa entrada, sin tocar el take.
-- Devuelve las notas y los datos del origen; sin glissando posible, nil y el
-- motivo. El conjunto de teclas se deriva del nombre vigente.
function M.plan(take, p, input)
  local view = setmetatable({ set = pitch_set(p.sets[p.set_name]) }, { __index = p })
  local src, err = plan_source(take, view, input.notes, input.ts, input.te)
  if not src then return nil, err end
  return build(take, view, src)
end

-- true si el take no cambio desde el ultimo glissando aplicado.
function M.can_rerun(take)
  return session ~= nil and session.take == take and take_hash(take) == session.hash
end

-- Rehace el ultimo glissando con otros params, sobre el mismo origen y canal,
-- partiendo del take original (borra lo escrito y restaura lo borrado).
-- Devuelve la cantidad de notas; nil y el motivo si no hay sesion valida.
function M.rerun(take, p)
  if not M.can_rerun(take) then return nil, "sin sesion" end
  local s = session
  local events, src = M.plan(take, p, s.input)
  if not events then return nil, src end

  if p.undo then reaper.Undo_BeginBlock() end
  remove_written(take, s)
  restore_notes(take, s.removed)
  reaper.MIDI_Sort(take)
  local removed = write(take, p, events, src, s.chan, s.input)
  if p.undo then reaper.Undo_EndBlock("Generate glissando (" .. p.name .. ")", -1) end

  s.written, s.removed, s.hash = events, removed, take_hash(take)
  return #events
end

local function num(v) return string.format("%.4g", v) end

local function fields(t, keys)
  local out = {}
  for _, k in ipairs(keys) do
    if t[k] ~= nil then out[#out + 1] = k .. " = " .. num(t[k]) end
  end
  return table.concat(out, ", ")
end

-- Texto Lua del preset vigente, para pegar en MidiGen_config.lua.
function M.preset_text(p)
  return table.concat({
    "-- en gliss.presets:",
    '["Custom"] = {',
    string.format('    set = "%s", contact = %d,', p.set_name, p.contact),
    string.format('    timing = { mode = "%s", %s },', p.timing.mode,
      fields(p.timing, { "total_ms", "note_ms", "curve", "jitter_ms" })),
    "    velocity = { " .. fields(p.velocity, { "from", "to", "curve", "jitter" }) .. " },",
    "},",
  }, "\n")
end

local STATE_SEC, STATE_KEY = "Nik_MidiGen_Gliss", "state"
local NUMERIC = {
  ["t.total_ms"] = { "timing", "total_ms" },
  ["t.note_ms"] = { "timing", "note_ms" },
  ["t.curve"] = { "timing", "curve" },
  ["t.jitter_ms"] = { "timing", "jitter_ms" },
  ["v.from"] = { "velocity", "from" },
  ["v.to"] = { "velocity", "to" },
  ["v.curve"] = { "velocity", "curve" },
  ["v.jitter"] = { "velocity", "jitter" },
  ["s.count"] = { "single", "count" },
  ["r.from_pitch"] = { "range", "from_pitch" },
  ["r.to_pitch"] = { "range", "to_pitch" },
  ["r.velocity"] = { "range", "velocity" },
}

-- Guarda los params vigentes (persistente entre sesiones).
function M.save(p)
  local parts = {
    "name=" .. p.name,
    "set=" .. p.set_name,
    "contact=" .. p.contact,
    "tmode=" .. p.timing.mode,
    "sdir=" .. p.single.direction,
    "mode=" .. p.mode,
    "channel=" .. tostring(p.channel),
    "s.from_pitch=" .. (p.single.from_pitch and tostring(p.single.from_pitch) or ""),
    "rdir=" .. (p.range.direction or "up"),
  }
  for key, ref in pairs(NUMERIC) do
    local v = p[ref[1]][ref[2]]
    if v ~= nil then parts[#parts + 1] = key .. "=" .. tostring(v) end
  end
  reaper.SetExtState(STATE_SEC, STATE_KEY, table.concat(parts, "|"), true)
end

-- Params guardados sobre la base del preset guardado; sin estado valido, el
-- preset por defecto del config.
function M.load(config)
  local cfg = config.gliss
  local saved = {}
  for k, v in reaper.GetExtState(STATE_SEC, STATE_KEY):gmatch("([%w_%.]+)=([^|]*)") do
    saved[k] = v
  end
  local p, err = M.resolve(config, saved.name)
  if not p then p, err = M.resolve(config, cfg.preset) end
  if not p then return nil, err end

  if cfg.sets[saved.set] then p.set_name = saved.set end
  local contact = tonumber(saved.contact)
  if contact and contact >= 1 then p.contact = math.floor(contact) end
  if saved.tmode == "total" or saved.tmode == "per_note" then p.timing.mode = saved.tmode end
  if saved.sdir == "up" or saved.sdir == "down" then p.single.direction = saved.sdir end
  if saved.mode == "merge" or saved.mode == "replace" then p.mode = saved.mode end
  local ch = tonumber(saved.channel)
  if saved.channel == "active" then
    p.channel = "active"
  elseif ch and ch >= 1 and ch <= 16 then
    p.channel = math.floor(ch)
  end
  if saved["s.from_pitch"] ~= nil then p.single.from_pitch = tonumber(saved["s.from_pitch"]) end
  for key, ref in pairs(NUMERIC) do
    local v = tonumber(saved[key])
    if v then p[ref[1]][ref[2]] = v end
  end
  if saved.rdir == "up" or saved.rdir == "down" then
    p.range.direction = saved.rdir
  elseif not p.range.direction then
    p.range.direction = (p.range.from_pitch > p.range.to_pitch) and "down" or "up"
  end
  return p
end

local function warn(msg)
  reaper.ShowMessageBox(msg, "Glissando", 0)
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

  if config.gliss.verbose then
    reaper.ShowConsoleMsg(string.format(
      "Gliss: preset=%s caso=%s canal_raw=%s canal_usado=%d notas=%d\n",
      p.name, info.label, tostring(info.chan_raw), info.chan, n))
  end
end

return M
