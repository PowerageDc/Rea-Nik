-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Inputs & Focus
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Inputs & Focus')
local FLT_MIN, FLT_MAX = ImGui.NumericLimits_Float()
local DBL_MIN, DBL_MAX = ImGui.NumericLimits_Double()
local IMGUI_VERSION, IMGUI_VERSION_NUM, REAIMGUI_VERSION = ImGui.GetVersion()

local demo = {
  menu = { enabled = true, f = 0.5, n = 0, b = true },
  no_titlebar = false, no_scrollbar = false, no_menu = false, no_move = false,
  no_resize   = false, no_collapse  = false, no_close = false, no_nav  = false,
  no_background = false, unsaved_document = false, no_docking = false,
  topmost = false, set_dock_id = nil,
}
local config, widgets, layout, popups, tables, misc, app, cache = {}, {}, {}, {}, {}, {}, {}, {}

-------------------------------------------------------------------------------
-- Helpers compartidos (copiados del archivo original, necesarios por esta seccion)
-------------------------------------------------------------------------------
function demo.HelpMarker(desc)
  ImGui.TextDisabled(ctx, '(?)')
  if ImGui.BeginItemTooltip(ctx) then
    ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 35.0)
    ImGui.Text(ctx, desc)
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndTooltip(ctx)
  end
end

function demo.RgbaToArgb(rgba)
  return (rgba >> 8 & 0x00FFFFFF) | (rgba << 24 & 0xFF000000)
end

function demo.ArgbToRgba(argb)
  return (argb << 8 & 0xFFFFFF00) | (argb >> 24 & 0xFF)
end

function demo.round(n)
  return math.floor(n + .5)
end

function demo.clamp(v, mn, mx)
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

function demo.HSV(h, s, v, a)
  local r, g, b = ImGui.ColorConvertHSVtoRGB(h, s, v)
  return ImGui.ColorConvertDouble4ToU32(r, g, b, a or 1.0)
end

function demo.EachEnum(enum)
  local enum_cache = cache[enum]
  if not enum_cache then
    enum_cache = {}
    cache[enum] = enum_cache

    for func_name, value in pairs(ImGui) do
      local enum_name = func_name:match(('^%s_(.+)$'):format(enum))
      if enum_name then
        enum_cache[#enum_cache + 1] = {value, enum_name}
      end
    end
    table.sort(enum_cache, function(a, b) return a[1] < b[1] end)
  end

  local i = 0
  return function()
    i = i + 1
    if not enum_cache[i] then return end
    return table.unpack(enum_cache[i])
  end
end

function demo.DockName(dock_id)
  if dock_id == 0 then
    return 'Floating'
  elseif dock_id > 0 then
    return ('ImGui docker %d'):format(dock_id)
  end

  -- reaper.DockGetPosition was added in v6.02
  local positions = {
    [0]='Bottom', [1]='Left', [2]='Top', [3]='Right', [4]='Floating'
  }
  local position = reaper.DockGetPosition and
    positions[reaper.DockGetPosition(~dock_id)] or 'Unknown'
  return ('REAPER docker %d (%s)'):format(-dock_id, position)
end

function demo.ConfigVarCheckbox(name, label)
  name = 'ConfigVar_' .. name
  local var = assert(reaper[('ImGui_%s'):format(name)], 'unknown var')()
  local rv,val = ImGui.Checkbox(ctx, label or name, ImGui.GetConfigVar(ctx, var))
  if rv then ImGui.SetConfigVar(ctx, var, val and 1 or 0) end
end


-------------------------------------------------------------------------------
-- Contenido de la seccion: Inputs & Focus
-------------------------------------------------------------------------------

function demo.DemoWindowInputs()
  local rv

  if not ImGui.CollapsingHeader(ctx, 'Inputs & Focus') then return end

  -- Display inputs
  ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once)
  local inputs_opened = ImGui.TreeNode(ctx, 'Inputs')
  ImGui.SameLine(ctx)
  demo.HelpMarker(
    "This is a simplified view. See more detailed input state:\n\z
      - in 'Tools->Metrics/Debugger->Inputs'.\n\z
      - in 'Tools->Debug Log->IO'.")
  if inputs_opened then
    if ImGui.IsMousePosValid(ctx) then
      ImGui.Text(ctx, ('Mouse pos: (%g, %g)'):format(ImGui.GetMousePos(ctx)))
    else
      ImGui.Text(ctx, 'Mouse pos: <INVALID>')
    end
    ImGui.Text(ctx, ('Mouse delta: (%g, %g)'):format(ImGui.GetMouseDelta(ctx)))

    local buttons = 4
    ImGui.Text(ctx, 'Mouse down:')
    for button = 0, buttons do
      if ImGui.IsMouseDown(ctx, button) then
        local duration = ImGui.GetMouseDownDuration(ctx, button)
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, ('b%d (%.02f secs)'):format(button, duration))
      end
    end

    ImGui.Text(ctx, ('Mouse wheel: %.1f %.1f'):format(ImGui.GetMouseWheel(ctx)))

    ImGui.Text(ctx, 'Mouse clicked count:')
    for button = 0, buttons do
      if ImGui.IsMouseDown(ctx, button) then
        local count = ImGui.GetMouseClickedCount(ctx, button)
        if count > 0 then
          ImGui.SameLine(ctx)
          ImGui.Text(ctx, ('b%d: %d'):format(button, count))
        end
      end
    end

    ImGui.Text(ctx, 'Keys down:')
    for key, name in demo.EachEnum('Key') do
      if ImGui.IsKeyDown(ctx, key) then
        local duration = ImGui.GetKeyDownDuration(ctx, key)
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, ('"%s" %d (%.02f secs)'):format(name, key, duration))
      end
    end
    ImGui.Text(ctx, ('Keys mods: %s%s%s%s'):format(
      ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)  and 'Ctrl '   or '',
      ImGui.IsKeyDown(ctx, ImGui.Mod_Shift) and 'Shift '  or '',
      ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)   and 'Alt '    or '',
      ImGui.IsKeyDown(ctx, ImGui.Mod_Super) and 'Super '  or ''))

    ImGui.Text(ctx, 'Chars queue:')
    for next_id = 0, math.huge do
      local rv, c = ImGui.GetInputQueueCharacter(ctx, next_id)
      if not rv then break end
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, ("'%s' (0x%04X)"):format(utf8.char(c), c))
    end

    ImGui.TreePop(ctx)
  end

  -- Display ImGuiIO output flags
  -- ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once)
  -- local outputs_opened = ImGui.TreeNode(ctx, 'Outputs')
  -- demo.HelpMarker(
  --  'The value of io.WantCaptureMouse and io.WantCaptureKeyboard are normally set by Dear ImGui \z
  --   to instruct your application of how to route inputs. Typically, when a value is true, it means \z
  --   Dear ImGui wants the corresponding inputs and we expect the underlying application to ignore them.\n\n\z
  --   The most typical case is: when hovering a window, Dear ImGui set io.WantCaptureMouse to true, \z
  --   and underlying application should ignore mouse inputs (in practice there are many and more subtle \z
  --   rules leading to how those flags are set).');
  -- if outputs_opened then
  --   ImGui.Text('io.WantCaptureMouse: %d', io.WantCaptureMouse);
  --   ImGui.Text('io.WantCaptureMouseUnlessPopupClose: %d', io.WantCaptureMouseUnlessPopupClose);
  --   ImGui.Text('io.WantCaptureKeyboard: %d', io.WantCaptureKeyboard);
  --   ImGui.Text('io.WantTextInput: %d', io.WantTextInput);
  --   ImGui.Text('io.WantSetMousePos: %d', io.WantSetMousePos);
  --   ImGui.Text('io.NavActive: %d, io.NavVisible: %d', io.NavActive, io.NavVisible);

    if ImGui.TreeNode(ctx, 'WantCapture override') then
      if not misc.capture_override then
        misc.capture_override = {mouse = -1, keyboard = -1}
      end

      demo.HelpMarker(
        -- "Hovering the colored canvas will override io.WantCaptureXXX fields.\n\z
        --  Notice how normally (when set to none), the value of io.WantCaptureKeyboard would be false when hovering \n
        --  and true when clicking."
        "SetNextFrameWantCaptureXXX instructs ReaImGui how to route inputs.\n\n\z
        Capturing the keyboard allows receiving input from REAPER's global scope.\n\n\z
        Hovering the colored canvas will call SetNextFrameWantCaptureXXX.")

      local capture_override_desc = {'None', 'Set to false', 'Set to true'}
      -- ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 15)
      -- rv,misc.capture_override.mouse = ImGui.SliderInt(ctx, 'SetNextFrameWantCaptureMouse() on hover', misc.capture_override.mouse, -1, 1, capture_override_desc[misc.capture_override.mouse + 2], ImGui.SliderFlags_AlwaysClamp)
      ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 15)
      rv,misc.capture_override.keyboard = ImGui.SliderInt(ctx, 'SetNextFrameWantCaptureKeyboard() on hover', misc.capture_override.keyboard, -1, 1, capture_override_desc[misc.capture_override.keyboard + 2], ImGui.SliderFlags_AlwaysClamp)

      ImGui.ColorButton(ctx, '##panel', 0xb219b2ff, ImGui.ColorEditFlags_NoTooltip | ImGui.ColorEditFlags_NoDragDrop, 128, 96) -- Dummy item
      -- if ImGui.IsItemHovered(ctx) and misc.capture_override.mouse ~= -1 then
      --   ImGui.SetNextFrameWantCaptureMouse(ctx, misc.capture_override.mouse == 1)
      -- end
      if ImGui.IsItemHovered(ctx) and misc.capture_override.keyboard ~= -1 then
        ImGui.SetNextFrameWantCaptureKeyboard(ctx, misc.capture_override.keyboard == 1)
      end

      ImGui.TreePop(ctx)
    end

  --   ImGui.TreePop(ctx)
  -- end

  -- Demonstrate using Shortcut() and Routing Policies.
  -- The general flow is:
  -- - Code interested in a chord (e.g. "Ctrl+A") declares their intent.
  -- - Multiple locations may be interested in same chord! Routing helps find a winner.
  -- - Every frame, we resolve all claims and assign one owner if the modifiers are matching.
  -- - The lower-level function is 'bool SetShortcutRouting()', returns true when caller got the route.
  -- - Most of the times, SetShortcutRouting() is not called directly. User mostly calls Shortcut() with routing flags.
  -- - If you call Shortcut() WITHOUT any routing option, it uses InputFlags_RouteFocused.
  -- TL;DR: Most uses will simply be:
  -- - Shortcut(Mod_Ctrl | Key_A); // Use InputFlags_RouteFocused policy.
  if ImGui.TreeNode(ctx, 'Shortcuts') then
    if not misc.shortcuts then
      misc.shortcuts = {
        route_options = ImGui.InputFlags_Repeat,
        route_type    = ImGui.InputFlags_RouteFocused,
        factor = 0.5,
      }
    end

    rv, misc.shortcuts.route_options = ImGui.CheckboxFlags(ctx, 'InputFlags_Repeat', misc.shortcuts.route_options, ImGui.InputFlags_Repeat)
    rv, misc.shortcuts.route_type = ImGui.RadioButtonEx(ctx, 'InputFlags_RouteActive', misc.shortcuts.route_type, ImGui.InputFlags_RouteActive)
    rv, misc.shortcuts.route_type = ImGui.RadioButtonEx(ctx, 'InputFlags_RouteFocused (default)', misc.shortcuts.route_type, ImGui.InputFlags_RouteFocused)
    rv, misc.shortcuts.route_type = ImGui.RadioButtonEx(ctx, 'InputFlags_RouteGlobal', misc.shortcuts.route_type, ImGui.InputFlags_RouteGlobal)
    ImGui.Indent(ctx)
    ImGui.BeginDisabled(ctx, misc.shortcuts.route_type ~= ImGui.InputFlags_RouteGlobal)
    rv, misc.shortcuts.route_options = ImGui.CheckboxFlags(ctx, 'InputFlags_RouteOverFocused',     misc.shortcuts.route_options, ImGui.InputFlags_RouteOverFocused)
    rv, misc.shortcuts.route_options = ImGui.CheckboxFlags(ctx, 'InputFlags_RouteOverActive',      misc.shortcuts.route_options, ImGui.InputFlags_RouteOverActive)
    rv, misc.shortcuts.route_options = ImGui.CheckboxFlags(ctx, 'InputFlags_RouteUnlessBgFocused', misc.shortcuts.route_options, ImGui.InputFlags_RouteUnlessBgFocused)
    ImGui.EndDisabled(ctx)
    ImGui.Unindent(ctx)
    rv, misc.shortcuts.route_type = ImGui.RadioButtonEx(ctx, 'InputFlags_RouteAlways', misc.shortcuts.route_type, ImGui.InputFlags_RouteAlways)
    local flags = misc.shortcuts.route_type | misc.shortcuts.route_options -- Merged flags
    if misc.shortcuts.route_type ~= ImGui.InputFlags_RouteGlobal then
      flags = flags & ~(ImGui.InputFlags_RouteOverFocused | ImGui.InputFlags_RouteOverActive | ImGui.InputFlags_RouteUnlessBgFocused)
    end

    ImGui.SeparatorText(ctx, 'Using SetNextItemShortcut()')
    ImGui.Text(ctx, 'Ctrl+S')
    ImGui.SetNextItemShortcut(ctx, ImGui.Mod_Ctrl | ImGui.Key_S, flags | ImGui.InputFlags_Tooltip)
    ImGui.Button(ctx, 'Save')
    ImGui.Text(ctx, 'Alt+F')
    ImGui.SetNextItemShortcut(ctx, ImGui.Mod_Alt | ImGui.Key_F, flags | ImGui.InputFlags_Tooltip)
    rv, misc.shortcuts.factor = ImGui.SliderDouble(ctx, 'Factor', misc.shortcuts.factor, 0.0, 1.0)

    ImGui.SeparatorText(ctx, 'Using Shortcut()')
    local line_height = ImGui.GetTextLineHeightWithSpacing(ctx)
    local key_chord = ImGui.Mod_Ctrl | ImGui.Key_A

    ImGui.Text(ctx, 'Ctrl+A')
    ImGui.Text(ctx, ('IsWindowFocused: %s, Shortcut: %s'):format(ImGui.IsWindowFocused(ctx), ImGui.Shortcut(ctx, key_chord, flags) and 'PRESSED' or '...'))

    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0xff00ff20)

    if ImGui.BeginChild(ctx, 'WindowA', -FLT_MIN, line_height * 14, ImGui.ChildFlags_Borders) then
      ImGui.Text(ctx, 'Press Ctrl+A and see who receives it!')
      ImGui.Separator(ctx)

      -- 1: Window polling for Ctrl+A
      ImGui.Text(ctx, '(in WindowA)')
      ImGui.Text(ctx, ('IsWindowFocused: %s, Shortcut: %s'):format(ImGui.IsWindowFocused(ctx), ImGui.Shortcut(ctx, key_chord, flags) and 'PRESSED' or '...'))

      -- 2: InputText also polling for Ctrl+A: it always uses _RouteFocused internally (gets priority when active)
      -- (Commented because the owner-aware version of Shortcut() is still in imgui_internal.h)
      --local str = 'Press Ctrl+A'
      --ImGui.Spacing(ctx)
      --ImGui.InputText(ctx, 'InputTextB', str, ImGui.InputTextFlags_ReadOnly)
      --local item_id = ImGui.GetItemID(ctx)
      --ImGui.SameLine(ctx); demo.HelpMarker('Internal widgets always use _RouteFocused')
      --ImGui.Text(ctx, ('IsWindowFocused: %s, Shortcut: %s'):format(ImGui.IsWindowFocused(ctx), ImGui.Shortcut(ctx, key_chord, flags, item_id) and 'PRESSED' or '...'))

      -- 3: Dummy child is not claiming the route: focusing them shouldn't steal route away from WindowA
      if ImGui.BeginChild(ctx, 'ChildD', -FLT_MIN, line_height * 4, ImGui.ChildFlags_Borders) then
        ImGui.Text(ctx, '(in ChildD: not using same Shortcut)')
        ImGui.Text(ctx, ('IsWindowFocused: %s'):format(ImGui.IsWindowFocused(ctx)))
        ImGui.EndChild(ctx)
      end

      -- 4: Child window polling for Ctrl+A. It is deeper than WindowA and gets priority when focused.
      if ImGui.BeginChild(ctx, 'ChildE', -FLT_MIN, line_height * 4, ImGui.ChildFlags_Borders) then
        ImGui.Text(ctx, '(in ChildE: using same Shortcut)')
        ImGui.Text(ctx, ('IsWindowFocused: %s, Shortcut: %s'):format(ImGui.IsWindowFocused(ctx), ImGui.Shortcut(ctx, key_chord, flags) and 'PRESSED' or '...'))
        ImGui.EndChild(ctx)
      end

      -- 5: In a popup
      if ImGui.Button(ctx, 'Open Popup') then
        ImGui.OpenPopup(ctx, 'PopupF')
      end
      if ImGui.BeginPopup(ctx, 'PopupF') then
        ImGui.Text(ctx, '(in PopupF)')
        ImGui.Text(ctx, ('IsWindowFocused: %s, Shortcut: %s'):format(ImGui.IsWindowFocused(ctx), ImGui.Shortcut(ctx, key_chord, flags) and 'PRESSED' or '...'))
        -- (Commented because the owner-aware version of Shortcut() is still in imgui_internal.h)
        --ImGui.InputText(ctx, 'InputTextG', str, ImGui.InputTextFlags_ReadOnly)
        --ImGui.Text(ctx, ('IsWindowFocused: %s, Shortcut: %s'):format(ImGui.IsWindowFocused(ctx), ImGui.Shortcut(ctx, key_chord, flags, ImGui.GetItemID(ctx)) and 'PRESSED' or '...'))
        ImGui.EndPopup(ctx)
      end

      ImGui.EndChild(ctx)
    end

    ImGui.PopStyleColor(ctx)
    ImGui.TreePop(ctx)
  end

  -- Display mouse cursors
  if ImGui.TreeNode(ctx, 'Mouse Cursors') then
    local current = ImGui.GetMouseCursor(ctx)
    local current_name = 'N/A'
    for cursor, name in demo.EachEnum('MouseCursor') do
      if cursor == current then
        current_name = name
        break
      end
    end
    ImGui.Text(ctx, ('Current mouse cursor = %d: %s'):format(current, current_name))
    ImGui.Text(ctx, 'Hover to see mouse cursors:')
    -- ImGui.SameLine(ctx); demo.HelpMarker(
    --   'Your application can render a different mouse cursor based on what ImGui.GetMouseCursor() returns. \z
    --    If software cursor rendering (io.MouseDrawCursor) is set ImGui will draw the right cursor for you, \z
    --    otherwise your backend needs to handle it.')
    for i, name in demo.EachEnum('MouseCursor') do
      local label = ('Mouse cursor %d: %s'):format(i, name)
      ImGui.Bullet(ctx); ImGui.Selectable(ctx, label, false)
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetMouseCursor(ctx, i)
      end
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Tabbing') then
    if not misc.tabbing then
      misc.tabbing = {
        buf = 'hello',
      }
    end

    ImGui.Text(ctx, 'Use TAB/Shift+TAB to cycle through keyboard editable fields.')
    rv,misc.tabbing.buf = ImGui.InputText(ctx, '1', misc.tabbing.buf)
    rv,misc.tabbing.buf = ImGui.InputText(ctx, '2', misc.tabbing.buf)
    rv,misc.tabbing.buf = ImGui.InputText(ctx, '3', misc.tabbing.buf)
    ImGui.PushItemFlag(ctx, ImGui.ItemFlags_NoTabStop, true)
    rv,misc.tabbing.buf = ImGui.InputText(ctx, '4 (tab skip)', misc.tabbing.buf)
    ImGui.SameLine(ctx); demo.HelpMarker("Item won't be cycled through when using TAB or Shift+Tab.")
    ImGui.PopItemFlag(ctx)
    rv,misc.tabbing.buf = ImGui.InputText(ctx, '5', misc.tabbing.buf)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Focus from code') then
    if not misc.focus then
      misc.focus = {
        buf = 'click on a button to set focus',
        d3  = {0.0, 0.0, 0.0}
      }
    end

    local focus_1 = ImGui.Button(ctx, 'Focus on 1'); ImGui.SameLine(ctx)
    local focus_2 = ImGui.Button(ctx, 'Focus on 2'); ImGui.SameLine(ctx)
    local focus_3 = ImGui.Button(ctx, 'Focus on 3')
    local has_focus = 0

    if focus_1 then ImGui.SetKeyboardFocusHere(ctx) end
    rv,misc.focus.buf = ImGui.InputText(ctx, '1', misc.focus.buf)
    if ImGui.IsItemActive(ctx) then has_focus = 1 end

    if focus_2 then ImGui.SetKeyboardFocusHere(ctx) end
    rv,misc.focus.buf = ImGui.InputText(ctx, '2', misc.focus.buf)
    if ImGui.IsItemActive(ctx) then has_focus = 2 end

    ImGui.PushItemFlag(ctx, ImGui.ItemFlags_NoTabStop, true)
    if focus_3 then ImGui.SetKeyboardFocusHere(ctx) end
    rv,misc.focus.buf = ImGui.InputText(ctx, '3 (tab skip)', misc.focus.buf)
    if ImGui.IsItemActive(ctx) then has_focus = 3 end
    ImGui.SameLine(ctx); demo.HelpMarker("Item won't be cycled through when using TAB or Shift+Tab.")
    ImGui.PopItemFlag(ctx)

    if has_focus > 0 then
      ImGui.Text(ctx, ('Item with focus: %d'):format(has_focus))
    else
      ImGui.Text(ctx, 'Item with focus: <none>')
    end

    -- Use >= 0 parameter to SetKeyboardFocusHere() to focus an upcoming item
    local focus_ahead = -1
    if ImGui.Button(ctx, 'Focus on X') then focus_ahead = 0 end ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Focus on Y') then focus_ahead = 1 end ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Focus on Z') then focus_ahead = 2 end
    if focus_ahead ~= -1 then ImGui.SetKeyboardFocusHere(ctx, focus_ahead) end
    rv,misc.focus.d3[1],misc.focus.d3[2],misc.focus.d3[3] =
      ImGui.SliderDouble3(ctx, 'Double3', misc.focus.d3[1], misc.focus.d3[2], misc.focus.d3[3], 0.0, 1.0)

    ImGui.TextWrapped(ctx, 'NB: Cursor & selection are preserved when refocusing last used item in code.')
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Dragging') then
    ImGui.TextWrapped(ctx, 'You can use GetMouseDragDelta(0) to query for the dragged amount on any widget.')
    for button = 0, 2 do
      ImGui.Text(ctx, ('IsMouseDragging(%d):'):format(button))
      ImGui.Text(ctx, ('  w/ default threshold: %s,'):format(ImGui.IsMouseDragging(ctx, button)))
      ImGui.Text(ctx, ('  w/ zero threshold: %s,'):format(ImGui.IsMouseDragging(ctx, button, 0.0)))
      ImGui.Text(ctx, ('  w/ large threshold: %s,'):format(ImGui.IsMouseDragging(ctx, button, 20.0)))
    end

    ImGui.Button(ctx, 'Drag Me')
    if ImGui.IsItemActive(ctx) then
      -- Draw a line between the button and the mouse cursor
      local draw_list = ImGui.GetForegroundDrawList(ctx)
      local mouse_pos_x, mouse_pos_y = ImGui.GetMousePos(ctx)
      local click_pos_x, click_pos_y = ImGui.GetMouseClickedPos(ctx, 0)
      local color = ImGui.GetColor(ctx, ImGui.Col_Button)
      ImGui.DrawList_AddLine(draw_list, click_pos_x, click_pos_y, mouse_pos_x, mouse_pos_y, color, 4.0)
    end

    -- Drag operations gets "unlocked" when the mouse has moved past a certain threshold
    -- (the default threshold is stored in io.MouseDragThreshold). You can request a lower or higher
    -- threshold using the second parameter of IsMouseDragging() and GetMouseDragDelta().
    local value_raw_x, value_raw_y = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left, 0.0)
    local value_with_lock_threshold_x, value_with_lock_threshold_y = ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left)
    local mouse_delta_x, mouse_delta_y = ImGui.GetMouseDelta(ctx)
    ImGui.Text(ctx, 'GetMouseDragDelta(0):')
    ImGui.Text(ctx, ('  w/ default threshold: (%.1f, %.1f)'):format(value_with_lock_threshold_x, value_with_lock_threshold_y))
    ImGui.Text(ctx, ('  w/ zero threshold: (%.1f, %.1f)'):format(value_raw_x, value_raw_y))
    ImGui.Text(ctx, ('GetMouseDelta() (%.1f, %.1f)'):format(mouse_delta_x, mouse_delta_y))
    ImGui.TreePop(ctx)
  end
end

-------------------------------------------------------------------------------
-- [SECTION] Style Editor / ShowStyleEditor()
-------------------------------------------------------------------------------
-- - ShowStyleSelector()
-- - ShowStyleEditor()
-------------------------------------------------------------------------------

-- Demo helper function to select among default colors. See ShowStyleEditor() for more advanced options.
-- Here we use the simplified Combo() api that packs items into a single literal string.
-- Useful for quick combo boxes where the choices are known locally.
-- bool ImGui::ShowStyleSelector(const char* label)
-- {
--     static int style_idx = -1;
--     if (ImGui.Combo(label, &style_idx, "Dark\0Light\0Classic\0"))
--     {
--         switch (style_idx)
--         {
--         case 0: ImGui.StyleColorsDark(); break;
--         case 1: ImGui.StyleColorsLight(); break;
--         case 2: ImGui.StyleColorsClassic(); break;
--         }
--         return true;
--     }
--     return false;
-- }

-- static const char* GetTreeLinesFlagsName(ImGuiTreeNodeFlags flags)
-- {
--   if (flags == ImGuiTreeNodeFlags_DrawLinesNone) return "DrawLinesNone";
--   if (flags == ImGuiTreeNodeFlags_DrawLinesFull) return "DrawLinesFull";
--   if (flags == ImGuiTreeNodeFlags_DrawLinesToNodes) return "DrawLinesToNodes";
--   return "";
-- }


-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Inputs & Focus', true)
  if visible then
    demo.DemoWindowInputs()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
