-- MidiEditStrum_common_logic.lua
-- Rasguido sobre los acordes de un take: reparte en el tiempo los inicios de
-- las notas de cada acorde y ajusta sus velocities. Sin UI: quien lo consume
-- arma los params con resolve() y llama a run(take, params).
-- Patron dofile + M={}.

local M = {}

-- Milisegundos a ticks en la posicion ppq, con el tempo del mapa en ese punto.
local function ms_to_ticks(take, ppq, ms)
  local t = reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)
  return reaper.MIDI_GetPPQPosFromProjTime(take, t + ms / 1000) - ppq
end

-- Pseudoaleatorio determinista en [-1, 1]: misma posicion, mismo resultado.
local function rand(a, b)
  local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
  return (x - math.floor(x)) * 2 - 1
end

local function read_notes(take)
  local notes = {}
  local _, count = reaper.MIDI_CountEvts(take)
  for i = 0, count - 1 do
    local _, sel, muted, s, e, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    notes[#notes + 1] = { idx = i, sel = sel, muted = muted, s = s, e = e, chan = chan, pitch = pitch, vel = vel }
  end
  return notes
end

-- Notas seleccionadas; sin seleccion, las no muteadas que arrancan junto al cursor.
local function pick_notes(take, notes, window_ms)
  local picked = {}
  for _, n in ipairs(notes) do
    if n.sel then picked[#picked + 1] = n end
  end
  if #picked > 0 then return picked end

  local cur = reaper.MIDI_GetPPQPosFromProjTime(take, reaper.GetCursorPosition())
  local w = ms_to_ticks(take, cur, window_ms)
  for _, n in ipairs(notes) do
    if not n.muted and math.abs(n.s - cur) <= w then picked[#picked + 1] = n end
  end
  return picked
end

-- Agrupa por cercania de inicio respecto de la primera nota del acorde.
local function group_chords(take, picked, window_ms)
  table.sort(picked, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    return a.pitch < b.pitch
  end)
  local chords, cur = {}, nil
  for _, n in ipairs(picked) do
    if cur and n.s - cur.ref <= cur.win then
      cur[#cur + 1] = n
    else
      cur = { n, ref = n.s, win = ms_to_ticks(take, n.s, window_ms) }
      chords[#chords + 1] = cur
    end
  end
  return chords
end

-- Cambios de un acorde segun direccion y params. nil si algun inicio
-- quedaria antes del origen del take.
local function plan_chord(take, chord, dir, p)
  local n = #chord
  local order = {}
  for i = 1, n do order[i] = chord[i] end
  table.sort(order, function(a, b) return a.pitch < b.pitch end)
  if dir == "up" then
    for i = 1, n // 2 do order[i], order[n + 1 - i] = order[n + 1 - i], order[i] end
  end

  local T, D, ref = p.timing, p.dynamics, chord.ref
  local plan = {}
  for k, note in ipairs(order) do
    local f = (n > 1) and (k - 1) / (n - 1) or 0

    local ms = T.total_ms * f ^ T.curve
    if k > 1 and (T.jitter_ms or 0) > 0 then
      ms = math.max(0, ms + T.jitter_ms * rand(ref, k))
    end
    if p.anchor == "last" then
      ms = ms - T.total_ms
    elseif p.anchor == "center" then
      ms = ms - T.total_ms / 2
    end

    local ns = math.floor(ref + ms_to_ticks(take, ref, ms) + 0.5)
    if ns < 0 then return nil end
    local ne = (p.ends == "duration") and (ns + (note.e - note.s)) or note.e

    local fac = D.from + (D.to - D.from) * f ^ (D.curve or 1)
    if dir == "up" then fac = fac * (D.up_scale or 1) end
    local nv = math.floor(note.vel * fac + (D.jitter or 0) * rand(ref + 1, k) + 0.5)
    nv = math.max(1, math.min(127, nv))

    if ns < ne then
      plan[#plan + 1] = { note = note, s = ns, e = ne, vel = nv }
    else
      plan[#plan + 1] = { note = note, s = note.s, e = note.e, vel = note.vel }
    end
  end
  return plan
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Arma los params de run() a partir de un estilo del config.
function M.resolve(config, style_name)
  local cfg = config.strum
  local style = cfg.styles[style_name]
  if not style then return nil, "estilo inexistente: " .. tostring(style_name) end
  local timing = cfg.timings[style.timing]
  if not timing then return nil, "timing inexistente: " .. tostring(style.timing) end
  local dynamics = cfg.dynamics[style.dynamics]
  if not dynamics then return nil, "dynamics inexistente: " .. tostring(style.dynamics) end
  return {
    name = style_name,
    timing_name = style.timing,
    dynamics_name = style.dynamics,
    timing = copy(timing),
    dynamics = copy(dynamics),
    direction = style.direction,
    anchor = cfg.anchor,
    ends = cfg.ends,
    chord_window_ms = cfg.chord_window_ms,
    undo = config.undo.enabled,
  }
end

-- Ultimo strum aplicado: take, hash de sus notas y, por nota, valores
-- originales (o*) y finales (n*). Permite rehacerlo desde el original.
local session

local function take_hash(take)
  local _, h = reaper.MIDI_GetHash(take, true, "")
  return h
end

-- Strum de las notas dadas: una entrada por nota de cada acorde de 2 o mas.
local function plan_notes(take, picked, p)
  local chords = group_chords(take, picked, p.chord_window_ms)
  local members, strummed = {}, 0
  for _, chord in ipairs(chords) do
    if #chord >= 2 then
      strummed = strummed + 1
      local dir = p.direction
      if dir == "alternate" then dir = (strummed % 2 == 1) and "down" or "up" end
      local plan = plan_chord(take, chord, dir, p)
      if plan then
        for _, m in ipairs(plan) do members[#members + 1] = m end
      end
    end
  end
  return members
end

-- Escribe las notas cuyo valor final difiere del actual y guarda la sesion.
-- Devuelve la cantidad escrita; sin diferencias no escribe ni crea undo.
local function commit(take, members, p)
  local function differs(m)
    local c = m.note.cur or m.note
    return m.s ~= c.s or m.e ~= c.e or m.vel ~= c.vel
  end

  local count = 0
  for _, m in ipairs(members) do
    if differs(m) then count = count + 1 end
  end
  if count == 0 then return 0 end

  if p.undo then reaper.Undo_BeginBlock() end
  for _, m in ipairs(members) do
    if differs(m) then
      reaper.MIDI_SetNote(take, m.note.idx, nil, nil, m.s, m.e, nil, nil, m.vel, true)
    end
  end
  reaper.MIDI_Sort(take)
  if p.undo then reaper.Undo_EndBlock("Strum chords (" .. (p.name or "") .. ")", -1) end

  session = { take = take, hash = take_hash(take), items = {} }
  for _, m in ipairs(members) do
    local n = m.note
    session.items[#session.items + 1] = {
      pitch = n.pitch, chan = n.chan, os = n.s, oe = n.e, ovel = n.vel,
      ns = m.s, ne = m.e, nvel = m.vel,
    }
  end
  return count
end

-- Aplica el rasguido al take. Devuelve la cantidad de notas modificadas.
function M.run(take, p)
  local notes = read_notes(take)
  local picked = pick_notes(take, notes, p.chord_window_ms)
  return commit(take, plan_notes(take, picked, p), p)
end

-- true si el take no cambio desde el ultimo strum aplicado.
function M.can_rerun(take)
  return session ~= nil and session.take == take and take_hash(take) == session.hash
end

-- Rehace el ultimo strum con otros params, partiendo de las notas originales.
-- nil si no hay sesion valida (el take cambio, o no se aplico nada antes).
function M.rerun(take, p)
  if not M.can_rerun(take) then return nil end
  local notes = read_notes(take)
  local used, originals = {}, {}
  for _, it in ipairs(session.items) do
    local found
    for _, c in ipairs(notes) do
      if not used[c.idx] and c.pitch == it.pitch and c.chan == it.chan
         and c.s == it.ns and c.e == it.ne and c.vel == it.nvel then
        found = c
        break
      end
    end
    if not found then session = nil; return nil end
    used[found.idx] = true
    originals[#originals + 1] = {
      idx = found.idx, sel = found.sel, muted = found.muted,
      pitch = found.pitch, chan = found.chan,
      s = it.os, e = it.oe, vel = it.ovel,
      cur = { s = found.s, e = found.e, vel = found.vel },
    }
  end
  return commit(take, plan_notes(take, originals, p), p)
end

local function fmt_fields(t, keys)
  local out = {}
  for _, k in ipairs(keys) do
    if t[k] ~= nil then out[#out + 1] = string.format("%s = %.4g", k, t[k]) end
  end
  return table.concat(out, ", ")
end

-- Texto Lua del preset vigente, para pegar en MidiEdit_config.lua.
function M.preset_text(p)
  return table.concat({
    "-- en strum.timings:",
    "custom = { " .. fmt_fields(p.timing, { "total_ms", "curve", "jitter_ms" }) .. " },",
    "-- en strum.dynamics:",
    "custom = { " .. fmt_fields(p.dynamics, { "from", "to", "curve", "jitter", "up_scale" }) .. " },",
    "-- en strum.styles:",
    string.format('["Custom"] = { timing = "custom", dynamics = "custom", direction = "%s" },', p.direction),
  }, "\n")
end

local STATE_SEC, STATE_KEY = "Nik_MidiEdit_Strum", "state"
local DIRECTIONS = { down = true, up = true, alternate = true }
local ANCHORS = { first = true, last = true, center = true }
local ENDS = { keep = true, duration = true }
local NUMERIC = {
  t_total_ms = { "timing", "total_ms" },
  t_curve = { "timing", "curve" },
  t_jitter_ms = { "timing", "jitter_ms" },
  d_from = { "dynamics", "from" },
  d_to = { "dynamics", "to" },
  d_curve = { "dynamics", "curve" },
  d_jitter = { "dynamics", "jitter" },
  d_up_scale = { "dynamics", "up_scale" },
}

-- Guarda los params vigentes (persistente entre sesiones).
function M.save(p)
  local parts = {
    "name=" .. (p.name or ""),
    "timing_name=" .. (p.timing_name or ""),
    "dynamics_name=" .. (p.dynamics_name or ""),
    "direction=" .. p.direction,
    "anchor=" .. p.anchor,
    "ends=" .. p.ends,
  }
  for key, ref in pairs(NUMERIC) do
    local v = p[ref[1]][ref[2]]
    if v ~= nil then parts[#parts + 1] = key .. "=" .. tostring(v) end
  end
  reaper.SetExtState(STATE_SEC, STATE_KEY, table.concat(parts, "|"), true)
end

-- Params guardados sobre la base del estilo; sin estado valido, el estilo
-- por defecto del config.
function M.load(config)
  local saved = {}
  for k, v in reaper.GetExtState(STATE_SEC, STATE_KEY):gmatch("([%w_]+)=([^|]*)") do
    saved[k] = v
  end
  local p, err = M.resolve(config, saved.name)
  if not p then p, err = M.resolve(config, config.strum.default_style) end
  if not p then return nil, err end
  if config.strum.timings[saved.timing_name] then p.timing_name = saved.timing_name end
  if config.strum.dynamics[saved.dynamics_name] then p.dynamics_name = saved.dynamics_name end
  if DIRECTIONS[saved.direction] then p.direction = saved.direction end
  if ANCHORS[saved.anchor] then p.anchor = saved.anchor end
  if ENDS[saved.ends] then p.ends = saved.ends end
  for key, ref in pairs(NUMERIC) do
    local v = tonumber(saved[key])
    if v then p[ref[1]][ref[2]] = v end
  end
  return p
end

return M