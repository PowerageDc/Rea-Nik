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
  local pcs = cfg.sets[preset.set]
  if not pcs then return nil, "conjunto inexistente: " .. tostring(preset.set) end
  return {
    name = preset_name,
    set = pitch_set(pcs),
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
local function plan_source(take, p, notes)
  local function ppq_of(t) return floor_ppq(reaper.MIDI_GetPPQPosFromProjTime(take, t)) end
  local function proj_of(ppq) return reaper.MIDI_GetProjTimeFromPPQPos(take, ppq) end

  local dest = notes[#notes]
  local away = (p.single.direction == "down") and 1 or -1
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

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

-- Borra las notas no seleccionadas del canal que arrancan en [lo, hi).
local function delete_notes(take, chan, lo, hi)
  local _, count = reaper.MIDI_CountEvts(take)
  for i = count - 1, 0, -1 do
    local _, sel, _, s, _, ch = reaper.MIDI_GetNote(take, i)
    if not sel and ch == chan and s >= lo and s < hi then reaper.MIDI_DeleteNote(take, i) end
  end
end

-- Escribe el glissando en el take del editor. Devuelve la cantidad de notas
-- y los datos de lo escrito; sin glissando posible, nil y el motivo.
function M.apply(editor, p)
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    return nil, "El MIDI Editor no tiene un take valido."
  end
  local notes = selected_notes(take)
  local src, serr = plan_source(take, p, notes)
  if not src then return nil, serr end
  local events, berr = build(take, p, src)
  if not events then return nil, berr end

  local chan_raw = reaper.MIDIEditor_GetSetting_int(editor, "default_note_chan")
  local chan = (p.channel == "active") and chan_raw or (p.channel - 1)

  if p.undo then reaper.Undo_BeginBlock() end
  if p.mode == "replace" then delete_notes(take, chan, events[1].s, src.ppq_end) end
  for _, ev in ipairs(events) do
    reaper.MIDI_InsertNote(take, false, false, ev.s, ev.e, chan, ev.pitch, ev.vel, true)
  end
  reaper.MIDI_Sort(take)
  if p.undo then reaper.Undo_EndBlock("Generate glissando (" .. p.name .. ")", -1) end

  return #events, { label = src.label, chan = chan, chan_raw = chan_raw }
end

local function warn(msg)
  reaper.ShowMessageBox(msg, "Glissando", 0)
end

-- Aplica el preset por defecto del config al editor activo.
function M.run(config)
  local editor = reaper.MIDIEditor_GetActive()
  if not editor then return end

  local p, err = M.resolve(config, config.gliss.preset)
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
