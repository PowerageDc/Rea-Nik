-- MusicStateLyricsSync_common_logic.lua
-- Cola de tap-to-sync de la tab Lyrics (paso 3b). Consumido solo por la tab
-- (via helpers.LyricsSync). Etapa 1: parseo, cola y UI; todavia sin taps.
-- El estado vive en S.sync (S = H._lyrics) y se descarta al cambiar de proyecto.

local M = {}

local KEY_TAP = reaper.ImGui_Key_B()
local KEY_TAP_LABEL = 'B'
local EXT_SECTION = 'NikMusicStateHelper'
local EXT_KEY_LATENCY = 'lyrics_tap_latency_ms'
local DEFAULT_LATENCY_MS = -150
local COLOR_TAP_HELD = 0x2E8B57FF
local EXT_KEY_CLOSE = 'lyrics_tap_close'
local EXT_KEY_GAP = 'lyrics_tap_gap_ms'
local DEFAULT_GAP_MS = 400
local MIN_HOLD_S = 0.25

-- Una linea con contenido = un item. Las lineas en blanco y los "·" sueltos
-- se ignoran (el fin de linea sale del gesto de tap, no del texto).
function M.ParseQueue(Lyrics, text)
  local items = {}
  for line in text:gmatch('[^\r\n]+') do
    local clean = Lyrics.CleanText(line)
    if clean ~= '' and clean ~= Lyrics.END_MARK then
      items[#items + 1] = clean
    end
  end
  return items
end

-- Invariante: pos == #hist + 1 (cada entrada de hist consumio un item).
local function getSync(S, H)
  if not S.sync or S.sync.proj ~= H.last_proj then
    S.sync = {
      proj = H.last_proj, buf = '', queue = {}, pos = 1, hist = {},
      held_prev = false, msg = '', pending = nil, cur_entry = nil,
      close_marks = reaper.GetExtState(EXT_SECTION, EXT_KEY_CLOSE) ~= '0',
      gap_ms = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_GAP)) or DEFAULT_GAP_MS,
      latency_ms = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_LATENCY)) or DEFAULT_LATENCY_MS,
    }
  end
  return S.sync
end

-- Vacia la cola pero conserva el texto pegado, para poder corregirlo.
function M.Clear(Sy)
  Sy.queue, Sy.pos, Sy.hist = {}, 1, {}
  Sy.msg = ''
  Sy.pending, Sy.cur_entry = nil, nil
end

local function readHeld(ctx, btn_active)
  local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
  local key_down = focused
    and not reaper.ImGui_IsAnyItemActive(ctx)
    and reaper.ImGui_IsKeyDown(ctx, KEY_TAP)
  return key_down or btn_active
end

-- Descarta las referencias a una entrada de hist que ya no existe.
local function forget(Sy, entry)
  if Sy.pending and Sy.pending.entry == entry then Sy.pending = nil end
  if Sy.cur_entry == entry then Sy.cur_entry = nil end
end

-- Inserta el fin pendiente (si lo hay) y lo anota en su entrada de hist.
local function insertEnd(Sy, Lyrics)
  local p = Sy.pending
  Sy.pending = nil
  if not p then return end
  local track = Lyrics.FindLyricsTrack(0)
  if not track then return end
  local ok = Lyrics.ApplyLine(track, Lyrics.PlanLine(track, p.time, nil), '')
  if ok then
    p.entry.end_time = p.time
    Sy.msg = 'Fin en ' .. reaper.format_timestr_pos(p.time, '', 2)
  end
end

-- Un press nuevo decide el destino del pendiente: dentro del gap se
-- descarta (carry-over), pasado el gap se inserta.
local function settleOnPress(Sy, Lyrics, t)
  if not Sy.pending then return end
  if t - Sy.pending.time < Sy.gap_ms / 1000 then
    Sy.pending = nil
  else
    insertEnd(Sy, Lyrics)
  end
end

-- Corre cada frame, tambien con el header colapsado.
local function tickPending(Sy, Lyrics)
  local p = Sy.pending
  if not p then return end
  local playing = (reaper.GetPlayState() & 1) ~= 0
  local now = reaper.GetPlayPosition() + Sy.latency_ms / 1000
  if not playing or now < p.time or now - p.time >= Sy.gap_ms / 1000 then
    insertEnd(Sy, Lyrics)
  end
end

local function onTapRelease(Sy, Lyrics)
  local entry = Sy.cur_entry
  Sy.cur_entry = nil
  if not entry or not Sy.close_marks then return end
  if (reaper.GetPlayState() & 1) == 0 then return end
  local rt = math.max(reaper.GetPlayPosition() + Sy.latency_ms / 1000, 0)
  if rt - entry.time < MIN_HOLD_S then return end
  Sy.pending = { time = rt, entry = entry }
end

local function onTapPress(Sy, Lyrics)
  if Sy.pos > #Sy.queue then return end
  if (reaper.GetPlayState() & 1) == 0 then return end
  local t = math.max(reaper.GetPlayPosition() + Sy.latency_ms / 1000, 0)
  settleOnPress(Sy, Lyrics, t)
  local text = Sy.queue[Sy.pos]
  local track = Lyrics.FindLyricsTrack(0)
  local ok = Lyrics.ApplyLine(track, Lyrics.PlanLine(track, t, nil), text)
  if not ok then return end
  local entry = { time = t, text = text }
  Sy.hist[#Sy.hist + 1] = entry
  Sy.cur_entry = entry
  Sy.pos = Sy.pos + 1
  Sy.msg = 'Tap en ' .. reaper.format_timestr_pos(t, '', 2)
end

local function undoEntry(Sy, Lyrics)
  local e = table.remove(Sy.hist)
  if not e then return end
  Sy.pos = Sy.pos - 1
  forget(Sy, e)
  if e.skip then return end
  local track = Lyrics.FindLyricsTrack(0)
  if not track then return end
  local victims = {}
  local events = Lyrics.CollectEvents(track)
  for _, ev in ipairs(Lyrics.EventsNear(events, e.time)) do
    if ev.text ~= Lyrics.END_MARK then victims[#victims + 1] = ev end
  end
  if e.end_time then
    for _, ev in ipairs(Lyrics.EventsNear(events, e.end_time)) do
      if ev.text == Lyrics.END_MARK then victims[#victims + 1] = ev end
    end
  end
  if #victims == 0 then return end
  reaper.Undo_BeginBlock()
  Lyrics.DeleteEvents(victims)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock('Lyrics: deshacer tap', -1)
end

local function drawPrep(ctx, Sy, Lyrics)
  reaper.ImGui_TextDisabled(ctx, 'Pega la letra: una linea por renglon (las lineas en blanco se ignoran).')
  local changed, text = reaper.ImGui_InputTextMultiline(ctx, '##lyrics_paste', Sy.buf, -1, 120)
  if changed then Sy.buf = text end

  local items = M.ParseQueue(Lyrics, Sy.buf)
  reaper.ImGui_TextDisabled(ctx, string.format('%d lineas detectadas', #items))
  if #items > 0 then
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Cargar cola', 120, 0) then
      Sy.queue, Sy.pos, Sy.hist = items, 1, {}
    end
  end
end

local function drawQueue(ctx, Sy, Lyrics)
  local n = #Sy.queue
  local done = Sy.pos > n
  if done then
    reaper.ImGui_Text(ctx, string.format('Cola completa (%d lineas).', n))
  else
    reaper.ImGui_Text(ctx, string.format('%d/%d  Siguiente:', Sy.pos, n))
    reaper.ImGui_TextWrapped(ctx, Sy.queue[Sy.pos])
    for k = Sy.pos + 1, math.min(Sy.pos + 2, n) do
      reaper.ImGui_TextDisabled(ctx, Sy.queue[k])
    end
  end

  local playing = (reaper.GetPlayState() & 1) ~= 0
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  if Sy.held_prev then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLOR_TAP_HELD)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), COLOR_TAP_HELD)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), COLOR_TAP_HELD)
  end
  local tap_label = done and 'Cola completa' or string.format('TAP (mantener)  [%s]', KEY_TAP_LABEL)
  reaper.ImGui_Button(ctx, tap_label .. '###tap', avail_w, 56)
  local btn_active = reaper.ImGui_IsItemActive(ctx)
  if Sy.held_prev then reaper.ImGui_PopStyleColor(ctx, 3) end

  local held = readHeld(ctx, btn_active)
  if held and not Sy.held_prev then
    onTapPress(Sy, Lyrics)
  elseif Sy.held_prev and not held then
    onTapRelease(Sy, Lyrics)
  end
  Sy.held_prev = held

  if reaper.ImGui_IsAnyItemActive(ctx) and not btn_active then
    reaper.ImGui_TextDisabled(ctx, 'Tecla de tap desactivada: hay un campo en edicion.')
  elseif not playing and not done then
    reaper.ImGui_TextDisabled(ctx, 'Inicia la reproduccion para tapear.')
  else
    reaper.ImGui_TextDisabled(ctx, Sy.msg ~= '' and Sy.msg or ' ')
  end

  reaper.ImGui_BeginDisabled(ctx, done)
  if reaper.ImGui_Button(ctx, 'Saltar linea', 110, 0) then
    Sy.hist[#Sy.hist + 1] = { skip = true }
    Sy.pos = Sy.pos + 1
  end
  reaper.ImGui_EndDisabled(ctx)

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_BeginDisabled(ctx, #Sy.hist == 0)
  if reaper.ImGui_Button(ctx, 'Deshacer', 90, 0) then
    undoEntry(Sy, Lyrics)
  end
  reaper.ImGui_EndDisabled(ctx)

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Vaciar cola', 110, 0) then
    insertEnd(Sy, Lyrics)
    M.Clear(Sy)
  end

  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local changed, v = reaper.ImGui_DragInt(ctx, 'Comp. (ms)', Sy.latency_ms, 1, -500, 200)
  if changed then Sy.latency_ms = v end
  if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    reaper.SetExtState(EXT_SECTION, EXT_KEY_LATENCY, tostring(Sy.latency_ms), true)
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, 'negativo = inserta antes')

  local c_changed, c_val = reaper.ImGui_Checkbox(ctx, 'Cerrar lineas con fin', Sy.close_marks)
  if c_changed then
    Sy.close_marks = c_val
    reaper.SetExtState(EXT_SECTION, EXT_KEY_CLOSE, c_val and '1' or '0', true)
  end
  reaper.ImGui_BeginDisabled(ctx, not Sy.close_marks)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local g_changed, g_val = reaper.ImGui_DragInt(ctx, 'Gap min. (ms)', Sy.gap_ms, 5, 0, 2000)
  if g_changed then Sy.gap_ms = g_val end
  if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    reaper.SetExtState(EXT_SECTION, EXT_KEY_GAP, tostring(Sy.gap_ms), true)
  end
  reaper.ImGui_EndDisabled(ctx)
end

local function tapExists(S, Lyrics, e)
  for _, ev in ipairs(Lyrics.EventsNear(S.events, e.time)) do
    if ev.text ~= Lyrics.END_MARK then return true end
  end
  return false
end

-- Ctrl+Z de REAPER o un borrado a mano pueden sacar lineas que la cola ya
-- dio por tapeadas. Solo se revisa cuando la cantidad de lineas baja (un
-- nudge no la cambia) y solo desde el final de hist hacia atras.
local function reconcile(Sy, S, Lyrics)
  local prev = Sy.seen_lines
  Sy.seen_lines = S.line_count
  if not prev or S.line_count >= prev then return end
  while #Sy.hist > 0 do
    local i = #Sy.hist
    while i > 0 and Sy.hist[i].skip do i = i - 1 end
    if i == 0 or tapExists(S, Lyrics, Sy.hist[i]) then return end
    for j = #Sy.hist, i, -1 do
      forget(Sy, Sy.hist[j])
      table.remove(Sy.hist, j)
      Sy.pos = Sy.pos - 1
    end
  end
end

function M.draw(ctx, S, H, helpers)
  local Sy = getSync(S, H)
  reconcile(Sy, S, helpers.Lyrics)
  tickPending(Sy, helpers.Lyrics)
  local label = 'Sincronizar (tap)'
  if #Sy.queue > 0 then
    label = string.format('%s - %d/%d', label, math.min(Sy.pos, #Sy.queue), #Sy.queue)
  end
  -- '###': el ID no depende del texto dinamico (08_REAIMGUI_PATTERNS.md §2).
  if not reaper.ImGui_CollapsingHeader(ctx, label .. '###lyrics_sync') then
    Sy.held_prev = false
    Sy.cur_entry = nil
    return
  end

  if #Sy.queue == 0 then
    drawPrep(ctx, Sy, helpers.Lyrics)
  else
    drawQueue(ctx, Sy, helpers.Lyrics)
  end
  reaper.ImGui_Spacing(ctx)
end

return M