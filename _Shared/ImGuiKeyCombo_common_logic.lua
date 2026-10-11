-- ImGuiKeyCombo_common_logic.lua
-- Combo con teclado para ReaImGui (BeginCombo + Selectable): flechas, Enter y
-- Esc los maneja ImGui; este modulo suma letras con ciclo (A, A#, Ab, A...),
-- dibuja el resaltado de la letra y confirma con Enter tras una letra.
-- Generico: sirve para cualquier lista. Ver musicstate_keys.md 9.3.
--
-- Uso (misma firma que ImGui_Combo, indice base 0):
--   local changed, idx = KeyCombo.combo(ctx, 'Tonica', idx, items)
-- items: tabla de strings o string con items separados por \0 (como Combo).
-- El estado de cada combo se guarda por label: usar labels unicos.

local M = {}

local states = {}  -- label -> { focused_idx, focus_req, letter_hl, mouse_mode }
local lists = {}   -- cache: string con \0 -> tabla

-- Recuadro de foco: Col_NavCursor en ReaImGui nuevo, Col_NavHighlight en viejo.
local COL_NAV = (reaper.ImGui_Col_NavCursor and reaper.ImGui_Col_NavCursor())
  or (reaper.ImGui_Col_NavHighlight and reaper.ImGui_Col_NavHighlight())

local function toList(items)
  if type(items) == 'table' then return items end
  local l = lists[items]
  if not l then
    l = {}
    for s in items:gmatch('([^\0]*)\0') do
      if s ~= '' then l[#l + 1] = s end
    end
    lists[items] = l
  end
  return l
end

-- Siguiente item (con vuelta) que empieza con la letra, despues de `from`
-- (base 0). Devuelve base 0, o nil.
local function nextWithLetter(list, letter, from)
  local n = #list
  for step = 1, n do
    local idx = (from + step) % n
    if list[idx + 1]:sub(1, 1):upper() == letter then return idx end
  end
end

-- Quien manda, teclado o mouse. UNICO punto a corregir (bugs conocidos):
-- (1) mouse_mode se activa con cualquier delta del mouse, aunque sea fuera
--     del popup o un temblor: apaga el recuadro de foco que acaba de
--     prender una flecha.
-- (2) mouse y despues flecha: el recuadro parpadea (la flecha lo prende y el
--     delta residual del frame siguiente lo apaga).
-- Los ensayos con ancla de posicion y filtro por IsWindowHovered no
-- anduvieron; ver musicstate_keys.md 9.3.
local function updateMouseGesture(ctx, st)
  local mdx, mdy = reaper.ImGui_GetMouseDelta(ctx)
  if mdx ~= 0 or mdy ~= 0 then st.mouse_mode = true end
  if math.abs(mdx) > 2 or math.abs(mdy) > 2 then st.letter_hl = nil end
end

-- Letras, flechas y Enter con el popup abierto. Devuelve true si Enter
-- confirmo el item resaltado por una letra (el nativo no activa en ese caso).
local function readKeys(ctx, st, list, cur)
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow())
    or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
    st.letter_hl = nil
    st.mouse_mode = false
  end
  local initials = {}
  for _, s in ipairs(list) do
    local c = s:sub(1, 1):upper()
    if c:match('%a') then initials[c] = true end
  end
  for L in pairs(initials) do
    local key_fn = reaper['ImGui_Key_' .. L]
    if key_fn and reaper.ImGui_IsKeyPressed(ctx, key_fn(), false) then
      st.focus_req = nextWithLetter(list, L, st.focused_idx or cur)
      st.letter_hl = st.focus_req
      st.mouse_mode = false
    end
  end
  -- Enter tras una letra: usa el foco del frame anterior (focused_idx), asi
  -- el Enter que abre el combo no confirma.
  return st.letter_hl ~= nil and st.focused_idx ~= nil
    and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
      or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false))
end

-- Devuelve changed, idx (como ImGui_Combo: changed es true al elegir un item).
function M.combo(ctx, label, cur, items)
  local list = toList(items)
  local st = states[label]
  if not st then st = { mouse_mode = false }; states[label] = st end
  local changed, result = false, cur

  if reaper.ImGui_BeginCombo(ctx, label, list[cur + 1] or '') then
    updateMouseGesture(ctx, st)
    if readKeys(ctx, st, list, cur) then
      changed, result = true, st.focused_idx
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    local focused = nil
    for i, text in ipairs(list) do
      local idx = i - 1
      if st.focus_req == idx then reaper.ImGui_SetKeyboardFocusHere(ctx) end
      -- Modo letra: hover y recuadro de foco nativos anulados (manda el
      -- teclado); modo mouse: solo el recuadro. Push y Pop balanceados.
      local n_push = 0
      if st.letter_hl ~= nil then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0)
        n_push = n_push + 1
      end
      if (st.letter_hl ~= nil or st.mouse_mode) and COL_NAV then
        reaper.ImGui_PushStyleColor(ctx, COL_NAV, 0)
        n_push = n_push + 1
      end
      local clicked = reaper.ImGui_Selectable(ctx, text, idx == cur)
      if n_push > 0 then reaper.ImGui_PopStyleColor(ctx, n_push) end
      if clicked then
        changed, result = true, idx
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if idx == cur then reaper.ImGui_SetItemDefaultFocus(ctx) end
      if reaper.ImGui_IsItemFocused(ctx) then focused = idx end
      if st.letter_hl == idx then
        local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
        local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx),
          x1, y1, x2, y2, reaper.ImGui_GetStyleColor(ctx, reaper.ImGui_Col_HeaderHovered()))
      end
      if st.focus_req == idx then
        reaper.ImGui_SetScrollHereY(ctx, 0.5)
        st.focus_req = nil
      end
    end
    st.focused_idx = focused
    reaper.ImGui_EndCombo(ctx)
  else
    st.focused_idx, st.focus_req, st.letter_hl, st.mouse_mode = nil, nil, nil, false
  end
  return changed, result
end

return M