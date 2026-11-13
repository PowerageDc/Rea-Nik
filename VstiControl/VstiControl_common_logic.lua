local M = {}

local SHAPES = {
  square = 0,
  linear = 1,
  slow = 2,
  fast_start = 3,
  fast_end = 4,
  bezier = 5,
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local NOTE_BASE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

function M.note(name, middle_c)
  local letter, accidental, octave = name:match("^([A-G])([#b]?)(-?%d+)$")
  if not letter then return nil, "Nombre de nota inválido: " .. tostring(name) end
  local semis = NOTE_BASE[letter]
  if accidental == "#" then semis = semis + 1 elseif accidental == "b" then semis = semis - 1 end
  return 60 + (tonumber(octave) - (middle_c or 4)) * 12 + semis
end

local function cc_msg(cc, value)
  if cc == "pw" then
    local raw = math.floor(clamp(value, -8192, 8191) + 0.5) + 8192
    return 0xE0, raw % 128, raw // 128
  end
  return 0xB0, clamp(cc, 0, 127), math.floor(clamp(value, 0, 127) + 0.5)
end

local function ppq_from_time(take, t)
  return math.floor(reaper.MIDI_GetPPQPosFromProjTime(take, t) + 0.5)
end

function M.get_context()
  local editor = reaper.MIDIEditor_GetActive()
  if not editor then return nil, "No hay un MIDI Editor activo" end

  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
    return nil, "El editor no tiene un take MIDI"
  end

  local item = reaper.GetMediaItemTake_Item(take)
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local ctx = {
    take = take,
    item_start_ppq = ppq_from_time(take, item_pos),
    item_end_ppq = ppq_from_time(take, item_pos + item_len),
    cursor_ppq = ppq_from_time(take, reaper.GetCursorPositionEx(0)),
  }

  local ts_s, ts_e = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if ts_e > ts_s then
    ctx.ts_start_ppq = ppq_from_time(take, ts_s)
    ctx.ts_end_ppq = ppq_from_time(take, ts_e)
  end

  return ctx
end

local function channel_of(spec, cfg)
  return clamp((spec.channel or cfg.channel or 1) - 1, 0, 15)
end

local function plan_keyswitch(ctx, spec, cfg, anchor, end_ppq)
  local d = cfg.defaults or {}
  local steps = spec.steps or { spec }
  local base = spec.offset or d.ks_offset or 0
  local stagger = spec.stagger or 0
  local events = {}

  for i, st in ipairs(steps) do
    local pitch = st.pitch
    if not pitch then return nil, "Falta pitch en el step " .. i end
    if type(pitch) == "string" then
      local n, nerr = M.note(pitch, cfg.middle_c)
      if not n then return nil, nerr end
      pitch = n
    end
    local offset = st.offset or (base + (i - 1) * stagger)
    local ppq = (anchor or ctx.cursor_ppq) + offset
    local len = st.length or spec.length or d.ks_length or 60
    if end_ppq then
      len = math.min(end_ppq, ctx.item_end_ppq) - ppq
      if len <= 0 then return nil, "El rango del keyswitch queda vacío" end
    end
    events[#events + 1] = {
      kind = "note",
      ppq = ppq,
      len = len,
      pitch = clamp(pitch, 0, 127),
      vel = clamp(st.velocity or spec.velocity or d.ks_velocity or 100, 1, 127),
      chan = channel_of(spec, cfg),
    }
  end

  return events
end

local function plan_cc_point(ctx, spec, cfg)
  if not spec.cc or not spec.value then return nil, "Falta cc o value" end
  local chanmsg, msg2, msg3 = cc_msg(spec.cc, spec.value)
  return {
    {
      kind = "cc",
      ppq = ctx.cursor_ppq + (spec.offset or 0),
      chanmsg = chanmsg,
      msg2 = msg2,
      msg3 = msg3,
      chan = channel_of(spec, cfg),
    },
  }
end

local function plan_cc_ramp(ctx, spec, cfg)
  if not spec.cc or not spec.from or not spec.to then
    return nil, "Falta cc, from o to"
  end
  if not ctx.ts_start_ppq then
    return nil, "La rampa necesita una selección de tiempo"
  end

  local d = cfg.defaults or {}
  local shape_name = spec.shape or d.ramp_shape or "linear"
  local shape = SHAPES[shape_name]
  if not shape then return nil, "Shape desconocida: " .. tostring(shape_name) end

  local offset = spec.offset or 0
  local chan = channel_of(spec, cfg)
  local cm1, a2, a3 = cc_msg(spec.cc, spec.from)
  local cm2, b2, b3 = cc_msg(spec.cc, spec.to)

  return {
    { kind = "cc", ppq = ctx.ts_start_ppq + offset, chanmsg = cm1,
      msg2 = a2, msg3 = a3, chan = chan, shape = shape,
      tension = spec.tension or d.ramp_tension },
    { kind = "cc", ppq = ctx.ts_end_ppq + offset, chanmsg = cm2,
      msg2 = b2, msg3 = b3, chan = chan },
  }
end

local function read_source(ctx)
  local take = ctx.take
  local _, note_count = reaper.MIDI_CountEvts(take)
  local selected, inside = {}, {}

  for i = 0, note_count - 1 do
    local _, sel, _, s, e = reaper.MIDI_GetNote(take, i)
    s = math.floor(s + 0.5)
    e = math.floor(e + 0.5)
    if sel then selected[#selected + 1] = { s = s, e = e } end
    if ctx.ts_start_ppq and s >= ctx.ts_start_ppq and s < ctx.ts_end_ppq then
      inside[#inside + 1] = { s = s, e = e }
    end
  end

  if #selected > 0 then
    local first, last_end = selected[1].s, selected[1].e
    for _, n in ipairs(selected) do
      if n.s < first then first = n.s end
      if n.e > last_end then last_end = n.e end
    end
    return { notes = selected, from = first, to = last_end,
             label = #selected .. " nota(s) seleccionada(s)" }
  end

  if ctx.ts_start_ppq then
    return { notes = inside, from = ctx.ts_start_ppq, to = ctx.ts_end_ppq,
             label = "selección de tiempo" }
  end

  return nil, "Hace falta seleccionar notas o una selección de tiempo"
end

local function unique_starts(notes)
  local seen, starts = {}, {}
  for _, n in ipairs(notes) do
    if not seen[n.s] then
      seen[n.s] = true
      starts[#starts + 1] = n.s
    end
  end
  table.sort(starts)
  return starts
end

local function plan_keyswitch_mode(ctx, spec, cfg)
  local mode = spec.mode or "cursor"
  if mode == "cursor" then return plan_keyswitch(ctx, spec, cfg) end
  if mode ~= "range" and mode ~= "per_note" then
    return nil, "Modo de keyswitch desconocido: " .. tostring(mode)
  end

  local src, err = read_source(ctx)
  if not src then return nil, err end

  if mode == "range" then
    local events, rerr = plan_keyswitch(ctx, spec, cfg, src.from, src.to)
    if events then events.source = src.label end
    return events, rerr
  end

  local starts = unique_starts(src.notes)
  if #starts == 0 then
    return nil, "No hay notas en la fuente (" .. src.label .. ")"
  end

  local events = { source = src.label }
  for _, s in ipairs(starts) do
    local evs, perr = plan_keyswitch(ctx, spec, cfg, s)
    if not evs then return nil, perr end
    for _, ev in ipairs(evs) do events[#events + 1] = ev end
  end
  return events
end

local PLANNERS = {
  keyswitch = plan_keyswitch_mode,
  cc_point = plan_cc_point,
  cc_ramp = plan_cc_ramp,
}

function M.describe_source()
  local ctx, err = M.get_context()
  if not ctx then return nil, err end
  local src, serr = read_source(ctx)
  if not src then return nil, serr end
  return src.label
end

function M.value_at_cursor(cfg, cc)
  local ctx, err = M.get_context()
  if not ctx then return nil, err end

  local is_pw = cc == "pw"
  local chanmsg = is_pw and 0xE0 or 0xB0
  local chan = clamp((cfg.channel or 1) - 1, 0, 15)
  local _, _, ccount = reaper.MIDI_CountEvts(ctx.take)
  local best_ppq, best_value

  for i = 0, ccount - 1 do
    local _, _, _, p, cm, c, m2, m3 = reaper.MIDI_GetCC(ctx.take, i)
    if cm == chanmsg and c == chan and p <= ctx.cursor_ppq
        and (is_pw or m2 == cc) and (not best_ppq or p >= best_ppq) then
      best_ppq = p
      best_value = is_pw and (m3 * 128 + m2 - 8192) or m3
    end
  end

  if not best_value then
    return nil, "No hay eventos de ese control antes del cursor"
  end
  return best_value
end

local function find_cc(take, ev)
  local _, _, ccount = reaper.MIDI_CountEvts(take)
  for i = 0, ccount - 1 do
    local _, _, _, p, chanmsg, c, m2, m3 = reaper.MIDI_GetCC(take, i)
    if chanmsg == ev.chanmsg and c == ev.chan and m2 == ev.msg2
        and m3 == ev.msg3 and math.abs(p - ev.ppq) < 0.5 then
      return i
    end
  end
  return nil
end

local function apply(ctx, events, label)
  local take = ctx.take
  reaper.Undo_BeginBlock2(0)

  for _, ev in ipairs(events) do
    if ev.kind == "note" then
      reaper.MIDI_InsertNote(take, false, false, ev.ppq, ev.ppq + ev.len,
        ev.chan, ev.pitch, ev.vel, true)
    else
      reaper.MIDI_InsertCC(take, false, false, ev.ppq, ev.chanmsg, ev.chan, ev.msg2, ev.msg3)
    end
  end
  reaper.MIDI_Sort(take)

  local shaped = false
  for _, ev in ipairs(events) do
    if ev.kind == "cc" and ev.shape then
      local idx = find_cc(take, ev)
      if idx then
        reaper.MIDI_SetCCShape(take, idx, ev.shape, ev.tension or 0, true)
        shaped = true
      end
    end
  end
  if shaped then reaper.MIDI_Sort(take) end

  reaper.UpdateArrange()
  reaper.Undo_EndBlock2(0, "VstiControl: " .. label, -1)
end

function M.exec(cfg, spec)
  local planner = PLANNERS[spec.type]
  if not planner then
    return false, "Tipo de botón desconocido: " .. tostring(spec.type)
  end

  local ctx, err = M.get_context()
  if not ctx then return false, err end

  local events, perr = planner(ctx, spec, cfg)
  if not events then return false, perr end

  for _, ev in ipairs(events) do
    if ev.ppq < ctx.item_start_ppq or ev.ppq >= ctx.item_end_ppq then
      return false, "Un evento queda fuera del item MIDI"
    end
  end

  apply(ctx, events, spec.label or spec.type)
  local msg = string.format("%d evento(s) insertado(s)", #events)
  if events.source then msg = msg .. " (fuente: " .. events.source .. ")" end
  return true, msg
end

return M