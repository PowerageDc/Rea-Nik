-- Nik_Test_KeysFocusProbe.lua
-- Probe del Paso 1 (atajos globales del Helper). No toca el Helper.
-- Mide, con las mismas condiciones del Helper (contexto config_flags=0 y
-- ventana raiz con WindowFlags_NoNav):
--  1. Si IsKeyPressed lee Tab y Esc con y sin un input activo.
--  2. Si SetKeyboardFocusHere hace scroll dentro de un BeginChild (prototipo
--     del anillo de foco: Tab / Shift+Tab mueven el foco entre los inputs).
--  3. Que pasa con un Combo nativo abierto (Esc, flechas, IsPopupOpen).
--  4. ImGui -> REAPER: F4 (SWS) y F5 (js_ReaScriptAPI) devuelven el foco.
--  5. REAPER -> ImGui: el script Nik_Test_KeysFocusRequest.lua levanta una
--     bandera de ExtState y esta ventana toma el foco con el metodo elegido.
-- Los textos van sin acentos a proposito (el log es solo de diagnostico).

local TITLE = 'Keys Probe'
local EXT_SEC, EXT_KEY = 'NikKeysProbe', 'focus_request'
local N = 40

local ctx = reaper.ImGui_CreateContext(TITLE, 0)

local bufs = {}
for i = 1, N do bufs[i] = 'item ' .. i end

local S = {
  focus_req = nil, active_idx = nil, check_vis = nil,
  tab = { n = 0, in_item = 0 }, esc = { n = 0, in_item = 0, in_popup = 0 },
  down = { n = 0, in_popup = 0 },
  combo_idx = 0, method = 'A', want_focus = false,
}
local log = {}

local function L(msg)
  table.insert(log, 1, os.date('%H:%M:%S ') .. msg)
  if #log > 14 then table.remove(log) end
end

local function has(name) return reaper[name] ~= nil end

-- ImGui -> REAPER ---------------------------------------------------------
local function focusReaperSWS()
  if not (has('BR_Win32_SetFocus') and has('BR_Win32_GetMainHwnd')) then
    L('F4: SWS BR_Win32_SetFocus NO disponible'); return
  end
  local ok, err = pcall(function() reaper.BR_Win32_SetFocus(reaper.BR_Win32_GetMainHwnd()) end)
  L('F4 SWS -> main: ' .. (ok and 'ok (probar Space en REAPER)' or tostring(err)))
end

local function focusReaperJS()
  if not has('JS_Window_SetFocus') then
    L('F5: js_ReaScriptAPI NO instalada'); return
  end
  local ok, err = pcall(function() reaper.JS_Window_SetFocus(reaper.GetMainHwnd()) end)
  L('F5 JS -> main: ' .. (ok and 'ok (probar Space en REAPER)' or tostring(err)))
end

-- REAPER -> ImGui ---------------------------------------------------------
local function focusSelfSWS()
  if not (has('BR_Win32_FindWindowEx') and has('BR_Win32_SetFocus')) then
    L('B: SWS FindWindowEx/SetFocus NO disponible'); return
  end
  local ok, h = pcall(reaper.BR_Win32_FindWindowEx, '0', '0', '', TITLE, false, true)
  if not ok or not h then L('B: ventana no encontrada (' .. tostring(h) .. ')'); return end
  local ok2, err = pcall(reaper.BR_Win32_SetFocus, h)
  L('B SWS por titulo: ' .. (ok2 and 'ok' or tostring(err)))
end

local function focusSelfJS()
  if not (has('JS_Window_Find') and has('JS_Window_SetFocus')) then
    L('C: js_ReaScriptAPI NO instalada'); return
  end
  local ok, h = pcall(reaper.JS_Window_Find, TITLE, true)
  if not ok or not h then L('C: ventana no encontrada (' .. tostring(h) .. ')'); return end
  local ok2, err = pcall(reaper.JS_Window_SetFocus, h)
  L('C JS por titulo: ' .. (ok2 and 'ok' or tostring(err)))
end

local function pollFocusRequest()
  if reaper.GetExtState(EXT_SEC, EXT_KEY) == '' then return end
  reaper.DeleteExtState(EXT_SEC, EXT_KEY, false)
  L('pedido de foco recibido, metodo ' .. S.method)
  if S.method == 'A' then S.want_focus = true
  elseif S.method == 'B' then focusSelfSWS()
  else focusSelfJS() end
end

-- Teclas (se leen al inicio del frame, como el despacho actual del Helper) --
local function readKeys(prev_active)
  local any_active = reaper.ImGui_IsAnyItemActive(ctx)
  local popup = reaper.ImGui_IsPopupOpen(ctx, '', reaper.ImGui_PopupFlags_AnyPopupId())
  local function pressed(k) return reaper.ImGui_IsKeyPressed(ctx, k, false) end

  if pressed(reaper.ImGui_Key_Tab()) then
    S.tab.n = S.tab.n + 1
    if any_active then S.tab.in_item = S.tab.in_item + 1 end
    if prev_active then
      local shift = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0
      local d = shift and -1 or 1
      S.focus_req = ((prev_active - 1 + d) % N) + 1
      L(string.format('Tab desde #%d -> pide foco #%d', prev_active, S.focus_req))
    end
  end
  if pressed(reaper.ImGui_Key_Escape()) then
    S.esc.n = S.esc.n + 1
    if any_active then S.esc.in_item = S.esc.in_item + 1 end
    if popup then S.esc.in_popup = S.esc.in_popup + 1 end
    L(string.format('Esc: item_activo=%s popup=%s', tostring(any_active), tostring(popup)))
  end
  if pressed(reaper.ImGui_Key_DownArrow()) then
    S.down.n = S.down.n + 1
    if popup then S.down.in_popup = S.down.in_popup + 1 end
  end
  if pressed(reaper.ImGui_Key_F2()) then S.focus_req = 35; L('F2 -> pide foco #35') end
  if pressed(reaper.ImGui_Key_F4()) then focusReaperSWS() end
  if pressed(reaper.ImGui_Key_F5()) then focusReaperJS() end
end

local function drawList()
  S.active_idx = nil
  if reaper.ImGui_BeginChild(ctx, 'list', 0, 160, 0, reaper.ImGui_WindowFlags_NoNav()) then
    for i = 1, N do
      reaper.ImGui_PushID(ctx, i)
      if S.focus_req == i then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        S.check_vis = { idx = i, frames = 0 }
        S.focus_req = nil
      end
      local ch, s = reaper.ImGui_InputText(ctx, '##in', bufs[i])
      if ch then bufs[i] = s end
      if reaper.ImGui_IsItemActive(ctx) then S.active_idx = i end
      if S.check_vis and S.check_vis.idx == i then
        S.check_vis.frames = S.check_vis.frames + 1
        if S.check_vis.frames == 3 then
          L(string.format('#%d: activo=%s visible=%s', i,
            tostring(reaper.ImGui_IsItemActive(ctx)), tostring(reaper.ImGui_IsItemVisible(ctx))))
          S.check_vis = nil
        end
      end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndChild(ctx)
  end
end

local function loop()
  pollFocusRequest()
  if S.want_focus then reaper.ImGui_SetNextWindowFocus(ctx); S.want_focus = false end

  reaper.ImGui_SetNextWindowSize(ctx, 560, 640, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, reaper.ImGui_WindowFlags_NoNav())
  if visible then
    local prev_active = S.active_idx
    readKeys(prev_active)

    local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
    reaper.ImGui_Text(ctx, 'Ventana enfocada: ' .. (focused and 'SI' or 'NO'))
    reaper.ImGui_Text(ctx, string.format('Tab: %d (con item activo: %d)   Esc: %d (item: %d, popup: %d)   Abajo: %d (popup: %d)',
      S.tab.n, S.tab.in_item, S.esc.n, S.esc.in_item, S.esc.in_popup, S.down.n, S.down.in_popup))
    reaper.ImGui_Text(ctx, string.format('IsAnyItemActive: %s   popup abierto: %s',
      tostring(reaper.ImGui_IsAnyItemActive(ctx)),
      tostring(reaper.ImGui_IsPopupOpen(ctx, '', reaper.ImGui_PopupFlags_AnyPopupId()))))
    reaper.ImGui_Separator(ctx)

    reaper.ImGui_Text(ctx, '1) Inputs en child con scroll: clic en uno, Tab / Shift+Tab; F2 = foco a #35')
    drawList()
    reaper.ImGui_Separator(ctx)

    reaper.ImGui_Text(ctx, '2) Combo nativo: abrirlo con el mouse y probar Esc / flechas / Enter')
    local _, idx = reaper.ImGui_Combo(ctx, 'Tonica', S.combo_idx, 'A\0A#\0Bb\0B\0C\0C#\0Db\0D\0')
    S.combo_idx = idx
    reaper.ImGui_Separator(ctx)

    reaper.ImGui_Text(ctx, '3) Foco: F4 (SWS) / F5 (JS) -> REAPER.  Metodo REAPER -> ImGui: ' .. S.method)
    if reaper.ImGui_Button(ctx, 'A: SetNextWindowFocus') then S.method = 'A' end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'B: SWS por titulo') then S.method = 'B' end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'C: JS por titulo') then S.method = 'C' end
    reaper.ImGui_Text(ctx, string.format('APIs: SWS=%s  JS=%s',
      tostring(has('BR_Win32_SetFocus')), tostring(has('JS_Window_SetFocus'))))
    reaper.ImGui_Separator(ctx)

    for _, line in ipairs(log) do reaper.ImGui_TextDisabled(ctx, line) end
    reaper.ImGui_End(ctx)
  end

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
