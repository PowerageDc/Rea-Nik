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
      held_prev = false, msg = '',
      latency_ms = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_LATENCY)) or DEFAULT_LATENCY_MS,
    }
  end
  return S.sync
end

-- Vacia la cola pero conserva el texto pegado, para poder corregirlo.
function M.Clear(Sy)
  Sy.queue, Sy.pos, Sy.hist = {}, 1, {}
  Sy.msg = ''
end

local function readHeld(ctx, btn_active)
  local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
  local key_down = focused
    and not reaper.ImGui_IsAnyItemActive(ctx)
    and reaper.ImGui_IsKeyDown(ctx, KEY_TAP)
  return key_down or btn_active
end

local function onTapPress(Sy, Lyrics)
  if Sy.pos > #Sy.queue then return end
  if (reaper.GetPlayState() & 1) == 0 then return end
  local t = math.max(reaper.GetPlayPosition() + Sy.latency_ms / 1000, 0)
  local text = Sy.queue[Sy.pos]
  local track = Lyrics.FindLyricsTrack(0)
  local ok = Lyrics.ApplyLine(track, Lyrics.PlanLine(track, t, nil), text)
  if not ok then return end
  Sy.hist[#Sy.hist + 1] = { time = t, text = text }
  Sy.pos = Sy.pos + 1
  Sy.msg = 'Tap en ' .. reaper.format_timestr_pos(t, '', 2)
end

local function undoEntry(Sy, Lyrics)
  local e = table.remove(Sy.hist)
  if not e then return end
  Sy.pos = Sy.pos - 1
  if e.skip then return end
  local track = Lyrics.FindLyricsTrack(0)
  if not track then return end
  local victims = {}
  for _, ev in ipairs(Lyrics.EventsNear(Lyrics.CollectEvents(track), e.time)) do
    if ev.text ~= Lyrics.END_MARK then victims[#victims + 1] = ev end
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
  reaper.ImGui_BeginDisabled(ctx, done)
  if Sy.held_prev then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), COLOR_TAP_HELD)
  end
  reaper.ImGui_Button(ctx, string.format('TAP (mantener)  [%s]###tap', KEY_TAP_LABEL), avail_w, 56)
  local btn_active = reaper.ImGui_IsItemActive(ctx)
  if Sy.held_prev then reaper.ImGui_PopStyleColor(ctx) end
  reaper.ImGui_EndDisabled(ctx)

  local held = readHeld(ctx, btn_active)
  if held and not Sy.held_prev then onTapPress(Sy, Lyrics) end
  Sy.held_prev = held

  if not playing and not done then
    reaper.ImGui_TextDisabled(ctx, 'Inicia la reproduccion para tapear.')
  elseif reaper.ImGui_IsAnyItemActive(ctx) and not btn_active then
    reaper.ImGui_TextDisabled(ctx, 'Tecla de tap desactivada: hay un campo en edicion.')
  elseif Sy.msg ~= '' then
    reaper.ImGui_TextDisabled(ctx, Sy.msg)
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
end

function M.draw(ctx, S, H, helpers)
  local Sy = getSync(S, H)
  local label = 'Sincronizar (tap)'
  if #Sy.queue > 0 then
    label = string.format('%s - %d/%d', label, math.min(Sy.pos, #Sy.queue), #Sy.queue)
  end
  -- '###': el ID no depende del texto dinamico (08_REAIMGUI_PATTERNS.md §2).
  if not reaper.ImGui_CollapsingHeader(ctx, label .. '###lyrics_sync') then
    Sy.held_prev = false
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