-- MusicStateLyricsSync_common_logic.lua
-- Cola de tap-to-sync de la tab Lyrics (paso 3b). Consumido solo por la tab
-- (via helpers.LyricsSync). Etapa 1: parseo, cola y UI; todavia sin taps.
-- El estado vive en S.sync (S = H._lyrics) y se descarta al cambiar de proyecto.

local M = {}

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
    S.sync = { proj = H.last_proj, buf = '', queue = {}, pos = 1, hist = {} }
  end
  return S.sync
end

-- Vacia la cola pero conserva el texto pegado, para poder corregirlo.
function M.Clear(Sy)
  Sy.queue, Sy.pos, Sy.hist = {}, 1, {}
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

local function drawQueue(ctx, Sy)
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

  reaper.ImGui_BeginDisabled(ctx, done)
  if reaper.ImGui_Button(ctx, 'Saltar linea', 110, 0) then
    Sy.hist[#Sy.hist + 1] = { skip = true }
    Sy.pos = Sy.pos + 1
  end
  reaper.ImGui_EndDisabled(ctx)

  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_BeginDisabled(ctx, #Sy.hist == 0)
  if reaper.ImGui_Button(ctx, 'Deshacer', 90, 0) then
    table.remove(Sy.hist)  -- etapa 3: las entradas de tap borraran sus eventos
    Sy.pos = Sy.pos - 1
  end
  reaper.ImGui_EndDisabled(ctx)

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Vaciar cola', 110, 0) then
    M.Clear(Sy)
  end
end

function M.draw(ctx, S, H, helpers)
  local Sy = getSync(S, H)
  local label = 'Sincronizar (tap)'
  if #Sy.queue > 0 then
    label = string.format('%s - %d/%d', label, math.min(Sy.pos, #Sy.queue), #Sy.queue)
  end
  -- '###': el ID no depende del texto dinamico (08_REAIMGUI_PATTERNS.md §2).
  if not reaper.ImGui_CollapsingHeader(ctx, label .. '###lyrics_sync') then return end

  if #Sy.queue == 0 then
    drawPrep(ctx, Sy, helpers.Lyrics)
  else
    drawQueue(ctx, Sy)
  end
  reaper.ImGui_Spacing(ctx)
end

return M