-- Nik_Test_ComboLetterProbe.lua
-- Diagnostico Paso 5c: letras en un combo propio (BeginCombo + Selectable).
-- Mide: (1) IsItemFocused informa el item resaltado; (2) SetKeyboardFocusHere
-- antes de un Selectable mueve el resaltado de teclado.
local ctx = reaper.ImGui_CreateContext('Combo letter probe', 0)
local ITEMS = { 'A', 'A#', 'Ab', 'B', 'Bb', 'C', 'C#', 'Cb', 'D', 'D#', 'Db',
                'E', 'Eb', 'F', 'F#', 'G', 'G#', 'Gb' }
local LETTERS = { 'A', 'B', 'C', 'D', 'E', 'F', 'G' }
local sel, focused_idx, focus_req = 0, nil, nil  -- indices base 0
local letter_hl = nil  -- item resaltado por una letra (el nativo no lo dibuja)
local mouse_mode = false  -- ultimo gesto: mouse (se oculta el recuadro de foco)
local anchor_x, anchor_y = nil, nil  -- mouse en el ultimo gesto de teclado
local MOUSE_AWAY_PX = 4
-- Recuadro de foco: Col_NavCursor en ReaImGui nuevo, Col_NavHighlight en viejo.
local COL_NAV = (reaper.ImGui_Col_NavCursor and reaper.ImGui_Col_NavCursor())
  or (reaper.ImGui_Col_NavHighlight and reaper.ImGui_Col_NavHighlight())

-- Siguiente item (con vuelta) que empieza con la letra, despues de `from`.
local function nextWithLetter(letter, from)
  local n = #ITEMS
  for step = 1, n do
    local idx = (from + step) % n
    if ITEMS[idx + 1]:sub(1, 1):upper() == letter then return idx end
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 360, 220, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Combo letter probe', true,
    reaper.ImGui_WindowFlags_NoNav())
  if visible then
    reaper.ImGui_Text(ctx, string.format('sel=%s  resaltado=%s',
      ITEMS[sel + 1], focused_idx and ITEMS[focused_idx + 1] or 'nil'))
    if reaper.ImGui_BeginCombo(ctx, 'Tonica', ITEMS[sel + 1]) then
      -- Un movimiento real del mouse devuelve el control al mouse (vuelve el
      -- hover nativo). Va antes de las letras: una letra del mismo frame gana.
      -- El mouse manda solo si se aleja del ancla (ultimo gesto de teclado)
      -- y esta sobre el popup. Distancia acumulada, no delta por frame: un
      -- temblor no la cruza.
      local mx, my = reaper.ImGui_GetMousePos(ctx)
      if not anchor_x then anchor_x, anchor_y = mx, my end
      if reaper.ImGui_IsWindowHovered(ctx) then
        local dx, dy = mx - anchor_x, my - anchor_y
        if dx * dx + dy * dy > MOUSE_AWAY_PX * MOUSE_AWAY_PX then
          mouse_mode = true
          letter_hl = nil
        end
      end
      -- Una flecha devuelve el resaltado al nativo.
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow())
        or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
        letter_hl = nil
        mouse_mode = false
        anchor_x, anchor_y = mx, my
      end
      for _, L in ipairs(LETTERS) do
        if reaper.ImGui_IsKeyPressed(ctx, reaper['ImGui_Key_' .. L](), false) then
          focus_req = nextWithLetter(L, focused_idx or sel)
          letter_hl = focus_req
          mouse_mode = false
          anchor_x, anchor_y = mx, my
        end
      end
      -- Enter tras una letra: el nativo no activa. Usa el foco del frame
      -- anterior (focused_idx), asi el Enter de abrir no confirma.
      if letter_hl and focused_idx
        and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
          or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)) then
        sel = focused_idx
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      local f = nil
      for i, label in ipairs(ITEMS) do
        local idx = i - 1
        if focus_req == idx then reaper.ImGui_SetKeyboardFocusHere(ctx) end
        -- Modo letra: el hover y el recuadro de foco nativos se anulan (manda
        -- el teclado). Push y Pop se balancean en la misma iteracion.
        local kb = letter_hl ~= nil
        local n_push = 0
        if kb then
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0)
          n_push = n_push + 1
        end
        if (kb or mouse_mode) and COL_NAV then
          reaper.ImGui_PushStyleColor(ctx, COL_NAV, 0)
          n_push = n_push + 1
        end
        local clicked = reaper.ImGui_Selectable(ctx, label, idx == sel)
        if n_push > 0 then reaper.ImGui_PopStyleColor(ctx, n_push) end
        if clicked then
          sel = idx
          reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if idx == sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
        if reaper.ImGui_IsItemFocused(ctx) then f = idx end
        if letter_hl == idx then
          local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
          local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
          reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx),
            x1, y1, x2, y2, reaper.ImGui_GetStyleColor(ctx, reaper.ImGui_Col_HeaderHovered()))
        end
        if focus_req == idx then
          reaper.ImGui_SetScrollHereY(ctx, 0.5)
          focus_req = nil
        end
      end
      focused_idx = f
      reaper.ImGui_EndCombo(ctx)
    else
      focused_idx, focus_req, letter_hl, mouse_mode = nil, nil, nil, false
      anchor_x, anchor_y = nil, nil
    end
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)