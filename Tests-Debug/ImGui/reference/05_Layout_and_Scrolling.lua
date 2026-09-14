-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Layout & Scrolling
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Layout & Scrolling')
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
-- Contenido de la seccion: Layout & Scrolling
-------------------------------------------------------------------------------

function demo.ShowExampleMenuFile()
  local rv

  ImGui.MenuItem(ctx, '(demo menu)', nil, false, false)
  if ImGui.MenuItem(ctx, 'New') then end
  if ImGui.MenuItem(ctx, 'Open', 'Ctrl+O') then end
  if ImGui.BeginMenu(ctx, 'Open Recent') then
    ImGui.MenuItem(ctx, 'fish_hat.c')
    ImGui.MenuItem(ctx, 'fish_hat.inl')
    ImGui.MenuItem(ctx, 'fish_hat.h')
    if ImGui.BeginMenu(ctx,'More..') then
      ImGui.MenuItem(ctx, 'Hello')
      ImGui.MenuItem(ctx, 'Sailor')
      if ImGui.BeginMenu(ctx, 'Recurse..') then
        demo.ShowExampleMenuFile()
        ImGui.EndMenu(ctx)
      end
      ImGui.EndMenu(ctx)
      end
    ImGui.EndMenu(ctx)
  end
  if ImGui.MenuItem(ctx, 'Save', 'Ctrl+S') then end
  if ImGui.MenuItem(ctx, 'Save As...') then end

  ImGui.Separator(ctx)
  if ImGui.BeginMenu(ctx, 'Options') then
    rv,demo.menu.enabled = ImGui.MenuItem(ctx, 'Enabled', '', demo.menu.enabled)
    if ImGui.BeginChild(ctx, 'child', 0, 60, ImGui.ChildFlags_Borders) then
      for i = 0, 9 do
        ImGui.Text(ctx, ('Scrolling Text %d'):format(i))
      end
      ImGui.EndChild(ctx)
    end
    rv,demo.menu.f = ImGui.SliderDouble(ctx, 'Value', demo.menu.f, 0.0, 1.0)
    rv,demo.menu.f = ImGui.InputDouble(ctx, 'Input', demo.menu.f, 0.1)
    rv,demo.menu.n = ImGui.Combo(ctx, 'Combo', demo.menu.n, 'Yes\0No\0Maybe\0')
    ImGui.EndMenu(ctx)
  end

  if ImGui.BeginMenu(ctx, 'Colors') then
    local sz = ImGui.GetTextLineHeight(ctx)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    for i, name in demo.EachEnum('Col') do
      local x, y = ImGui.GetCursorScreenPos(ctx)
      ImGui.DrawList_AddRectFilled(draw_list, x, y, x + sz, y + sz, ImGui.GetColor(ctx, i))
      ImGui.Dummy(ctx, sz, sz)
      ImGui.SameLine(ctx)
      ImGui.MenuItem(ctx, name)
    end
    ImGui.EndMenu(ctx)
  end

  -- Here we demonstrate appending again to the "Options" menu (which we already created above)
  -- Of course in this demo it is a little bit silly that this function calls BeginMenu("Options") twice.
  -- In a real code-base using it would make senses to use this feature from very different code locations.
  if ImGui.BeginMenu(ctx, 'Options') then -- <-- Append!
    rv,demo.menu.b = ImGui.Checkbox(ctx, 'SomeOption', demo.menu.b)
    ImGui.EndMenu(ctx)
  end

  if ImGui.BeginMenu(ctx, 'Disabled', false) then -- Disabled
    error('never called')
  end
  if ImGui.MenuItem(ctx, 'Checked', nil, true) then end
  ImGui.Separator(ctx)
  if ImGui.MenuItem(ctx, 'Quit', 'Alt+F4') then end
end

function demo.DemoWindowLayout()
  if not ImGui.CollapsingHeader(ctx, 'Layout & Scrolling') then return end

  local rv

  if ImGui.TreeNode(ctx, 'Child windows') then
    if not layout.child then
      layout.child = {
        disable_mouse_wheel = false,
        disable_menu        = false,
        draw_lines          = 3,
        max_height_in_lines = 10,
        offset_x            = 0,
        override_bg_color   = true,
        flags               = ImGui.ChildFlags_Borders | ImGui.ChildFlags_ResizeX | ImGui.ChildFlags_ResizeY,
      }
    end

    ImGui.SeparatorText(ctx, 'Child windows')
    demo.HelpMarker('Use child windows to begin into a self-contained independent scrolling/clipping regions within a host window.')
    rv,layout.child.disable_mouse_wheel = ImGui.Checkbox(ctx, 'Disable Mouse Wheel', layout.child.disable_mouse_wheel)
    rv,layout.child.disable_menu = ImGui.Checkbox(ctx, 'Disable Menu', layout.child.disable_menu)

    -- Child 1: no border, enable horizontal scrollbar
    do
      local window_flags = ImGui.WindowFlags_HorizontalScrollbar
      if layout.child.disable_mouse_wheel then
        window_flags = window_flags | ImGui.WindowFlags_NoScrollWithMouse
      end
      if ImGui.BeginChild(ctx, 'ChildL', ImGui.GetContentRegionAvail(ctx) * 0.5, 260, ImGui.ChildFlags_None, window_flags) then
        for i = 0, 99 do
          ImGui.Text(ctx, ('%04d: scrollable region'):format(i))
        end
        ImGui.EndChild(ctx)
      end
    end

    ImGui.SameLine(ctx)

    -- Child 2: rounded border
    do
      local window_flags = ImGui.WindowFlags_None
      if layout.child.disable_mouse_wheel then
        window_flags = window_flags | ImGui.WindowFlags_NoScrollWithMouse
      end
      if not layout.child.disable_menu then
        window_flags = window_flags | ImGui.WindowFlags_MenuBar
      end
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 5.0)
      local visible = ImGui.BeginChild(ctx, 'ChildR', 0, 260, ImGui.ChildFlags_Borders, window_flags)
      if visible then
        if not layout.child.disable_menu and ImGui.BeginMenuBar(ctx) then
          if ImGui.BeginMenu(ctx, 'Menu') then
            demo.ShowExampleMenuFile()
            ImGui.EndMenu(ctx)
          end
          ImGui.EndMenuBar(ctx)
        end
        if ImGui.BeginTable(ctx, 'split', 2, ImGui.TableFlags_Resizable | ImGui.TableFlags_NoSavedSettings) then
          for i = 0, 99 do
            ImGui.TableNextColumn(ctx)
            ImGui.Button(ctx, ('%03d'):format(i), -FLT_MIN, 0.0)
          end
          ImGui.EndTable(ctx)
        end
        ImGui.EndChild(ctx)
      end
      ImGui.PopStyleVar(ctx)
    end

    -- Child 3: manual-resize
    ImGui.SeparatorText(ctx, 'Manual-resize')
    do
      demo.HelpMarker('Drag bottom border to resize. Double-click bottom border to auto-fit to vertical contents.')
      -- if ImGui.Button(ctx, 'Set Height to 200') then
      --   ImGui.SetNextWindowSize(ctx, -FLT_MIN, 200)
      -- end

      ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, ImGui.GetStyleColor(ctx, ImGui.Col_FrameBg))
      if ImGui.BeginChild(ctx, 'ResizableChild', -FLT_MIN, ImGui.GetTextLineHeightWithSpacing(ctx) * 8, ImGui.ChildFlags_Borders | ImGui.ChildFlags_ResizeY) then
        for n = 0, 9 do
          ImGui.Text(ctx, ('Line %04d'):format(n))
        end
        ImGui.EndChild(ctx)
      end
      ImGui.PopStyleColor(ctx)
    end

    -- Child 4: auto-resizing height with a limit
    ImGui.SeparatorText(ctx, 'Auto-resize with constraints')
    do
      ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
      rv,layout.child.draw_lines = ImGui.DragInt(ctx, 'Lines Count', layout.child.draw_lines, 0.2)
      ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
      rv,layout.child.max_height_in_lines = ImGui.DragInt(ctx, 'Max Height (in Lines)', layout.child.max_height_in_lines, 0.2)

      ImGui.SetNextWindowSizeConstraints(ctx, 0.0, ImGui.GetTextLineHeightWithSpacing(ctx) * 1, FLT_MAX, ImGui.GetTextLineHeightWithSpacing(ctx) * layout.child.max_height_in_lines)
      if ImGui.BeginChild(ctx, 'ConstrainedChild', -FLT_MIN, 0.0, ImGui.ChildFlags_Borders | ImGui.ChildFlags_AutoResizeY) then
        for n = 0, layout.child.draw_lines - 1 do
          ImGui.Text(ctx, ('Line %04d'):format(n))
        end
        ImGui.EndChild(ctx)
      end
    end

    ImGui.SeparatorText(ctx, 'Misc/Advanced')

    -- Demonstrate a few extra things
    -- - Changing Col_ChildBg (which is transparent black in default styles)
    -- - Using SetCursorPos() to position child window (the child window is an item from the POV of parent window)
    --   You can also call SetNextWindowPos() to position the child window. The parent window will effectively
    --   layout from this position.
    -- - Using ImGui.GetItemRectMin/Max() to query the "item" state (because the child window is an item from
    --   the POV of the parent window). See 'Demo->Querying Status (Edited/Active/Hovered etc.)' for details.
    do
      ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
      rv,layout.child.offset_x = ImGui.DragInt(ctx, 'Offset X', layout.child.offset_x, 1.0, -1000, 1000)
      rv,layout.child.override_bg_color = ImGui.Checkbox(ctx, 'Override ChildBg color', layout.child.override_bg_color)
      rv,layout.child.flags = ImGui.CheckboxFlags(ctx, 'ChildFlags_Borders', layout.child.flags, ImGui.ChildFlags_Borders)
      rv,layout.child.flags = ImGui.CheckboxFlags(ctx, 'ChildFlags_AlwaysUseWindowPadding', layout.child.flags, ImGui.ChildFlags_AlwaysUseWindowPadding)
      rv,layout.child.flags = ImGui.CheckboxFlags(ctx, 'ChildFlags_ResizeX', layout.child.flags, ImGui.ChildFlags_ResizeX)
      rv,layout.child.flags = ImGui.CheckboxFlags(ctx, 'ChildFlags_ResizeY', layout.child.flags, ImGui.ChildFlags_ResizeY)
      rv,layout.child.flags = ImGui.CheckboxFlags(ctx, 'ChildFlags_FrameStyle', layout.child.flags, ImGui.ChildFlags_FrameStyle)
      ImGui.SameLine(ctx); demo.HelpMarker('Style the child window like a framed item: use FrameBg, FrameRounding, FrameBorderSize, FramePadding instead of ChildBg, ChildRounding, ChildBorderSize, WindowPadding.')
      if (layout.child.flags & ImGui.ChildFlags_FrameStyle) ~= 0 then
        layout.child.override_bg_color = false
      end

      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + layout.child.offset_x)
      if layout.child.override_bg_color then
        ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0xFF000064)
      end
      local visible = ImGui.BeginChild(ctx, 'Red', 200, 100, layout.child.flags, ImGui.WindowFlags_None)
      if layout.child.override_bg_color then
        ImGui.PopStyleColor(ctx)
      end
      if visible then
        for n = 0, 49 do
          ImGui.Text(ctx, ('Some test %d'):format(n))
        end
        ImGui.EndChild(ctx)
      end
      local child_is_hovered = ImGui.IsItemHovered(ctx)
      local child_rect_min_x,child_rect_min_y = ImGui.GetItemRectMin(ctx)
      local child_rect_max_x,child_rect_max_y = ImGui.GetItemRectMax(ctx)
      ImGui.Text(ctx, ('Hovered: %s'):format(child_is_hovered))
      ImGui.Text(ctx, ('Rect of child window is: (%.0f,%.0f) (%.0f,%.0f)')
        :format(child_rect_min_x, child_rect_min_y, child_rect_max_x, child_rect_max_y))
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Widgets Width') then
    if not layout.width then
      layout.width = {
        d = 0.0,
        show_indented_items = true,
      }
    end

    -- Use SetNextItemWidth() to set the width of a single upcoming item.
    -- Use PushItemWidth()/PopItemWidth() to set the width of a group of items.
    -- In real code use you'll probably want to choose width values that are proportional to your font size
    -- e.g. Using '20.0 * GetFontSize()' as width instead of '200.0', etc.

    rv,layout.width.show_indented_items = ImGui.Checkbox(ctx, 'Show indented items', layout.width.show_indented_items)

    ImGui.Text(ctx, 'SetNextItemWidth/PushItemWidth(100)')
    ImGui.SameLine(ctx); demo.HelpMarker('Fixed width.')
    ImGui.PushItemWidth(ctx, 100)
    rv,layout.width.d = ImGui.DragDouble(ctx, 'double##1b', layout.width.d)
    if layout.width.show_indented_items then
      ImGui.Indent(ctx)
      rv,layout.width.d = ImGui.DragDouble(ctx, 'double (indented)##1b', layout.width.d)
      ImGui.Unindent(ctx)
    end
    ImGui.PopItemWidth(ctx)

    ImGui.Text(ctx, 'SetNextItemWidth/PushItemWidth(-100)')
    ImGui.SameLine(ctx); demo.HelpMarker('Align to right edge minus 100')
    ImGui.PushItemWidth(ctx, -100)
    rv,layout.width.d = ImGui.DragDouble(ctx, 'double##2a', layout.width.d)
    if layout.width.show_indented_items then
      ImGui.Indent(ctx)
      rv,layout.width.d = ImGui.DragDouble(ctx, 'double (indented)##2b', layout.width.d)
      ImGui.Unindent(ctx)
    end
    ImGui.PopItemWidth(ctx)

    ImGui.Text(ctx, 'SetNextItemWidth/PushItemWidth(GetContentRegionAvail().x * 0.5)')
    ImGui.SameLine(ctx); demo.HelpMarker('Half of available width.\n(~ right-cursor_pos)\n(works within a column set)')
    ImGui.PushItemWidth(ctx, ImGui.GetContentRegionAvail(ctx) * 0.5)
    rv,layout.width.d = ImGui.DragDouble(ctx, 'double##3a', layout.width.d)
    if layout.width.show_indented_items then
      ImGui.Indent(ctx)
      rv,layout.width.d = ImGui.DragDouble(ctx, 'double (indented)##3b', layout.width.d)
      ImGui.Unindent(ctx)
    end
    ImGui.PopItemWidth(ctx)

    ImGui.Text(ctx, 'SetNextItemWidth/PushItemWidth(-GetContentRegionAvail().x * 0.5)')
    ImGui.SameLine(ctx); demo.HelpMarker('Align to right edge minus half')
    ImGui.PushItemWidth(ctx, -ImGui.GetContentRegionAvail(ctx) * 0.5)
    rv,layout.width.d = ImGui.DragDouble(ctx, 'double##4a', layout.width.d)
    if layout.width.show_indented_items then
      ImGui.Indent(ctx)
      rv,layout.width.d = ImGui.DragDouble(ctx, 'double (indented)##4b', layout.width.d)
      ImGui.Unindent(ctx)
    end
    ImGui.PopItemWidth(ctx)

    ImGui.Text(ctx, 'SetNextItemWidth/PushItemWidth(-Min(GetContentRegionAvail().x * .40, GetFontSize() * 12))');
    ImGui.PushItemWidth(ctx, -math.min(ImGui.GetFontSize(ctx) * 12, ImGui.GetContentRegionAvail(ctx) * .40))
    rv,layout.width.d = ImGui.DragDouble(ctx, 'double##5a', layout.width.d)
    if layout.width.show_indented_items then
      ImGui.Indent(ctx)
      rv,layout.width.d = ImGui.DragDouble(ctx, 'double (indented)##5b', layout.width.d);
      ImGui.Unindent(ctx)
    end
    ImGui.PopItemWidth(ctx)

    -- Demonstrate using PushItemWidth to surround three items.
    -- Calling SetNextItemWidth() before each of them would have the same effect.
    ImGui.Text(ctx, 'SetNextItemWidth/PushItemWidth(-FLT_MIN)')
    ImGui.SameLine(ctx); demo.HelpMarker('Align to right edge')
    ImGui.PushItemWidth(ctx, -FLT_MIN)
    rv,layout.width.d = ImGui.DragDouble(ctx, '##double6a', layout.width.d)
    if layout.width.show_indented_items then
      ImGui.Indent(ctx)
      rv,layout.width.d = ImGui.DragDouble(ctx, 'double (indented)##6b', layout.width.d)
      ImGui.Unindent(ctx)
    end
    ImGui.PopItemWidth(ctx)

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Basic Horizontal Layout') then
    if not layout.horizontal then
      layout.horizontal = {
        c1 = false, c2 = false, c3 = false, c4 = false,
        d0 = 1.0, d1 = 2.0, d2 = 3.0,
        item = -1,
        selection = {0, 1, 2, 3},
      }
    end

    ImGui.TextWrapped(ctx, '(Use ImGui.SameLine() to keep adding items to the right of the preceding item)')

    -- Text
    ImGui.Text(ctx, 'Two items: Hello'); ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xFFFF00FF, 'Sailor')

    -- Adjust spacing
    ImGui.Text(ctx, 'More spacing: Hello'); ImGui.SameLine(ctx, 0, 20)
    ImGui.TextColored(ctx, 0xFFFF00FF, 'Sailor')

    -- Button
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, 'Normal buttons'); ImGui.SameLine(ctx)
    ImGui.Button(ctx, 'Banana'); ImGui.SameLine(ctx)
    ImGui.Button(ctx, 'Apple'); ImGui.SameLine(ctx)
    ImGui.Button(ctx, 'Corniflower')

    -- Button
    ImGui.Text(ctx, 'Small buttons'); ImGui.SameLine(ctx)
    ImGui.SmallButton(ctx, 'Like this one'); ImGui.SameLine(ctx)
    ImGui.Text(ctx, 'can fit within a text block.')

    -- Aligned to arbitrary position. Easy/cheap column.
    ImGui.Text(ctx, 'Aligned')
    ImGui.SameLine(ctx, 150); ImGui.Text(ctx, 'x=150')
    ImGui.SameLine(ctx, 300); ImGui.Text(ctx, 'x=300')
    ImGui.Text(ctx, 'Aligned')
    ImGui.SameLine(ctx, 150); ImGui.SmallButton(ctx, 'x=150')
    ImGui.SameLine(ctx, 300); ImGui.SmallButton(ctx, 'x=300')

    -- Checkbox
    rv,layout.horizontal.c1 = ImGui.Checkbox(ctx, 'My',     layout.horizontal.c1); ImGui.SameLine(ctx)
    rv,layout.horizontal.c2 = ImGui.Checkbox(ctx, 'Tailor', layout.horizontal.c2); ImGui.SameLine(ctx)
    rv,layout.horizontal.c3 = ImGui.Checkbox(ctx, 'Is',     layout.horizontal.c3); ImGui.SameLine(ctx)
    rv,layout.horizontal.c4 = ImGui.Checkbox(ctx, 'Rich',   layout.horizontal.c4)

    -- Various
    ImGui.PushItemWidth(ctx, 80)
    local items = 'AAAA\0BBBB\0CCCC\0DDDD\0'
    rv,layout.horizontal.item = ImGui.Combo(ctx, 'Combo', layout.horizontal.item, items);   ImGui.SameLine(ctx)
    rv,layout.horizontal.d0 = ImGui.SliderDouble(ctx, 'X', layout.horizontal.d0, 0.0, 5.0); ImGui.SameLine(ctx)
    rv,layout.horizontal.d1 = ImGui.SliderDouble(ctx, 'Y', layout.horizontal.d1, 0.0, 5.0); ImGui.SameLine(ctx)
    rv,layout.horizontal.d2 = ImGui.SliderDouble(ctx, 'Z', layout.horizontal.d2, 0.0, 5.0)
    ImGui.PopItemWidth(ctx)

    ImGui.PushItemWidth(ctx, 80)
    ImGui.Text(ctx, 'Lists:')
    for i,sel in ipairs(layout.horizontal.selection) do
      if i > 1 then ImGui.SameLine(ctx) end
      ImGui.PushID(ctx, i)
      rv,layout.horizontal.selection[i] = ImGui.ListBox(ctx, '', sel, items)
      ImGui.PopID(ctx)
      -- ImGui.SetItemTooltip(ctx, ('ListBox %d hovered'):format(i))
    end
    ImGui.PopItemWidth(ctx)

    -- Dummy
    local button_sz_w, button_sz_h = 40, 40
    ImGui.Button(ctx, 'A', button_sz_w, button_sz_h); ImGui.SameLine(ctx)
    ImGui.Dummy(ctx, button_sz_w, button_sz_h); ImGui.SameLine(ctx)
    ImGui.Button(ctx,'B', button_sz_w, button_sz_h)

    -- Manually wrapping
    -- (we should eventually provide this as an automatic layout feature, but for now you can do it manually)
    ImGui.Text(ctx, 'Manual wrapping:')
    local item_spacing_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local buttons_count = 20
    local window_visible_x2 = ImGui.GetCursorScreenPos(ctx) + ImGui.GetContentRegionAvail(ctx)
    for n = 0, buttons_count - 1 do
      ImGui.PushID(ctx, n)
      ImGui.Button(ctx, 'Box', button_sz_w, button_sz_h)
      local last_button_x2 = ImGui.GetItemRectMax(ctx)
      local next_button_x2 = last_button_x2 + item_spacing_x + button_sz_w -- Expected position if next button was on same line
      if n + 1 < buttons_count and next_button_x2 < window_visible_x2 then
        ImGui.SameLine(ctx)
      end
      ImGui.PopID(ctx)
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Groups') then
    if not widgets.groups then
      widgets.groups = {
        values = reaper.new_array({0.5, 0.20, 0.80, 0.60, 0.25}),
      }
    end

    demo.HelpMarker(
      'BeginGroup() basically locks the horizontal position for new line. \z
       EndGroup() bundles the whole group so that you can use "item" functions such as \z
       IsItemHovered()/IsItemActive() or SameLine() etc. on the whole group.')
    ImGui.BeginGroup(ctx)
    ImGui.BeginGroup(ctx)
    ImGui.Button(ctx, 'AAA')
    ImGui.SameLine(ctx)
    ImGui.Button(ctx, 'BBB')
    ImGui.SameLine(ctx)
    ImGui.BeginGroup(ctx)
    ImGui.Button(ctx, 'CCC')
    ImGui.Button(ctx, 'DDD')
    ImGui.EndGroup(ctx)
    ImGui.SameLine(ctx)
    ImGui.Button(ctx, 'EEE')
    ImGui.EndGroup(ctx)
    ImGui.SetItemTooltip(ctx, 'First group hovered')

    -- Capture the group size and create widgets using the same size
    local size_w, size_h = ImGui.GetItemRectSize(ctx)
    local item_spacing_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)

    ImGui.PlotHistogram(ctx, '##values', widgets.groups.values, 0, nil, 0.0, 1.0, size_w, size_h)

    ImGui.Button(ctx, 'ACTION', (size_w - item_spacing_x) * 0.5, size_h)
    ImGui.SameLine(ctx)
    ImGui.Button(ctx, 'REACTION', (size_w - item_spacing_x) * 0.5, size_h)
    ImGui.EndGroup(ctx)
    ImGui.SameLine(ctx)

    ImGui.Button(ctx, 'LEVERAGE\nBUZZWORD', size_w, size_h)
    ImGui.SameLine(ctx)

    if ImGui.BeginListBox(ctx, 'List', size_w, size_h) then
      ImGui.Selectable(ctx, 'Selected', true)
      ImGui.Selectable(ctx, 'Not Selected', false)
      ImGui.EndListBox(ctx)
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Text Baseline Alignment') then
    do
      ImGui.BulletText(ctx, 'Text baseline:')
      ImGui.SameLine(ctx); demo.HelpMarker(
        'This is testing the vertical alignment that gets applied on text to keep it aligned with widgets. \z
        Lines only composed of text or "small" widgets use less vertical space than lines with framed widgets.')
      ImGui.Indent(ctx)

      ImGui.Text(ctx, 'KO Blahblah'); ImGui.SameLine(ctx)
      ImGui.Button(ctx, 'Some framed item'); ImGui.SameLine(ctx)
      demo.HelpMarker('Baseline of button will look misaligned with text..')

      -- If your line starts with text, call AlignTextToFramePadding() to align text to upcoming widgets.
      -- (because we don't know what's coming after the Text() statement, we need to move the text baseline
      -- down by FramePadding.y ahead of time)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, 'OK Blahblah'); ImGui.SameLine(ctx)
      ImGui.Button(ctx, 'Some framed item##2'); ImGui.SameLine(ctx)
      demo.HelpMarker('We call AlignTextToFramePadding() to vertically align the text baseline by +FramePadding.y')

      -- SmallButton() uses the same vertical padding as Text
      ImGui.Button(ctx, 'TEST##1'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'TEST'); ImGui.SameLine(ctx)
      ImGui.SmallButton(ctx, 'TEST##2')

      -- If your line starts with text, call AlignTextToFramePadding() to align text to upcoming widgets.
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, 'Text aligned to framed item'); ImGui.SameLine(ctx)
      ImGui.Button(ctx, 'Item##1'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Item'); ImGui.SameLine(ctx)
      ImGui.SmallButton(ctx, 'Item##2'); ImGui.SameLine(ctx)
      ImGui.Button(ctx, 'Item##3')

      ImGui.Unindent(ctx)
    end

    ImGui.Spacing(ctx)

    do
      ImGui.BulletText(ctx, 'Multi-line text:')
      ImGui.Indent(ctx)
      ImGui.Text(ctx, 'One\nTwo\nThree'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Hello\nWorld'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Banana')

      ImGui.Text(ctx, 'Banana'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Hello\nWorld'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'One\nTwo\nThree')

      ImGui.Button(ctx, 'HOP##1'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Banana'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Hello\nWorld'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Banana')

      ImGui.Button(ctx, 'HOP##2'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Hello\nWorld'); ImGui.SameLine(ctx)
      ImGui.Text(ctx, 'Banana')
      ImGui.Unindent(ctx)
    end

    ImGui.Spacing(ctx)

    do
      ImGui.BulletText(ctx, 'Misc items:')
      ImGui.Indent(ctx)

      -- SmallButton() sets FramePadding to zero. Text baseline is aligned to match baseline of previous Button.
      ImGui.Button(ctx, '80x80', 80, 80)
      ImGui.SameLine(ctx)
      ImGui.Button(ctx, '50x50', 50, 50)
      ImGui.SameLine(ctx)
      ImGui.Button(ctx, 'Button()')
      ImGui.SameLine(ctx)
      ImGui.SmallButton(ctx, 'SmallButton()')

      -- Tree
      -- (here the node appears after a button and has odd intent, so we use ImGui.TreeNodeFlags_DrawLinesNone to disable hierarchy outline)
      local spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
      ImGui.Button(ctx, 'Button##1')
      ImGui.SameLine(ctx, 0.0, spacing)
      if ImGui.TreeNode(ctx, 'Node##1', ImGui.TreeNodeFlags_DrawLinesNone) then
        -- Placeholder tree data
        for i = 0, 5 do
          ImGui.BulletText(ctx, ('Item %d..'):format(i))
        end
        ImGui.TreePop(ctx)
      end

      -- Vertically align text node a bit lower so it'll be vertically centered with upcoming widget.
      -- Otherwise you can use SmallButton() (smaller fit).
      ImGui.AlignTextToFramePadding(ctx)

      -- Common mistake to avoid: if we want to SameLine after TreeNode we need to do it before we add
      -- other contents below the node.
      local node_open = ImGui.TreeNode(ctx, 'Node##2')
      ImGui.SameLine(ctx, 0.0, spacing); ImGui.Button(ctx, 'Button##2')
      if node_open then
        -- Placeholder tree data
        for i = 0, 5 do
          ImGui.BulletText(ctx, ('Item %d..'):format(i))
        end
        ImGui.TreePop(ctx)
      end

      -- Bullet
      ImGui.Button(ctx, 'Button##3')
      ImGui.SameLine(ctx, 0.0, spacing)
      ImGui.BulletText(ctx, 'Bullet text')

      ImGui.AlignTextToFramePadding(ctx)
      ImGui.BulletText(ctx, 'Node')
      ImGui.SameLine(ctx, 0.0, spacing); ImGui.Button(ctx, 'Button##4')
      ImGui.Unindent(ctx)
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Scrolling') then
    if not layout.scrolling then
      layout.scrolling = {
        track_item       = 50,
        enable_track     = true,
        enable_extra_decorations = false,
        scroll_to_off_px = 0.0,
        scroll_to_pos_px = 200.0,
        lines = 7,
        show_horizontal_contents_size_demo_window = false,
      }
    end

    -- Vertical scroll functions
    demo.HelpMarker('Use SetScrollHereY() or SetScrollFromPosY() to scroll to a given vertical position.')

    rv,layout.scrolling.enable_extra_decorations = ImGui.Checkbox(ctx, 'Decoration', layout.scrolling.enable_extra_decorations)

    rv,layout.scrolling.enable_track = ImGui.Checkbox(ctx, 'Track', layout.scrolling.enable_track)
    ImGui.PushItemWidth(ctx, 100)
    ImGui.SameLine(ctx, 140)
    rv,layout.scrolling.track_item = ImGui.DragInt(ctx, '##item', layout.scrolling.track_item, 0.25, 0, 99, 'Item = %d')
    if rv then
      layout.scrolling.enable_track = true
    end

    local scroll_to_off = ImGui.Button(ctx, 'Scroll Offset')
    ImGui.SameLine(ctx, 140)
    rv,layout.scrolling.scroll_to_off_px = ImGui.DragDouble(ctx, '##off', layout.scrolling.scroll_to_off_px, 1.00, 0, FLT_MAX, '+%.0f px')
    if rv then
      scroll_to_off = true
    end

    local scroll_to_pos = ImGui.Button(ctx, 'Scroll To Pos')
    ImGui.SameLine(ctx, 140)
    rv,layout.scrolling.scroll_to_pos_px = ImGui.DragDouble(ctx, '##pos', layout.scrolling.scroll_to_pos_px, 1.00, -10, FLT_MAX, 'X/Y = %.0f px')
    if rv then
      scroll_to_pos = true
    end
    ImGui.PopItemWidth(ctx)

    if scroll_to_off or scroll_to_pos then
      layout.scrolling.enable_track = false
    end

    local names = {'Top', '25%', 'Center', '75%', 'Bottom'}
    local item_spacing_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    local child_w = (ImGui.GetContentRegionAvail(ctx) - 4 * item_spacing_x) / #names
    local child_flags = layout.scrolling.enable_extra_decorations and ImGui.WindowFlags_MenuBar or ImGui.WindowFlags_None
    if child_w < 1.0 then
      child_w = 1.0
    end
    ImGui.PushID(ctx, '##VerticalScrolling')
    for i,name in ipairs(names) do
      if i > 1 then ImGui.SameLine(ctx) end
      ImGui.BeginGroup(ctx)
      ImGui.Text(ctx, name)

      if ImGui.BeginChild(ctx, i, child_w, 200.0, ImGui.ChildFlags_Borders, child_flags) then
        if ImGui.BeginMenuBar(ctx) then
          ImGui.Text(ctx, 'abc')
          ImGui.EndMenuBar(ctx)
        end
        if scroll_to_off then
          ImGui.SetScrollY(ctx, layout.scrolling.scroll_to_off_px)
        end
        if scroll_to_pos then
          ImGui.SetScrollFromPosY(ctx, select(2, ImGui.GetCursorStartPos(ctx)) + layout.scrolling.scroll_to_pos_px, (i - 1) * 0.25)
        end
        for item = 0, 99 do
          if layout.scrolling.enable_track and item == layout.scrolling.track_item then
            ImGui.TextColored(ctx, 0xFFFF00FF, ('Item %d'):format(item))
            ImGui.SetScrollHereY(ctx, (i - 1) * 0.25) -- 0.0:top, 0.5:center, 1.0:bottom
          else
            ImGui.Text(ctx, ('Item %d'):format(item))
          end
        end
        local scroll_y = ImGui.GetScrollY(ctx)
        local scroll_max_y = ImGui.GetScrollMaxY(ctx)
        ImGui.EndChild(ctx)
        ImGui.Text(ctx, ('%.0f/%.0f'):format(scroll_y, scroll_max_y))
      else
        ImGui.Text(ctx, 'N/A')
      end
      ImGui.EndGroup(ctx)
    end
    ImGui.PopID(ctx)

    -- Horizontal scroll functions
    ImGui.Spacing(ctx)
    demo.HelpMarker(
      "Use SetScrollHereX() or SetScrollFromPosX() to scroll to a given horizontal position.\n\n\z
       Because the clipping rectangle of most window hides half worth of WindowPadding on the \z
       left/right, using SetScrollFromPosX(+1) will usually result in clipped text whereas the \z
       equivalent SetScrollFromPosY(+1) wouldn't.")
    ImGui.PushID(ctx, '##HorizontalScrolling')
    local scrollbar_size = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ScrollbarSize)
    local window_padding_y = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_WindowPadding))
    local child_height = ImGui.GetTextLineHeight(ctx) + scrollbar_size + window_padding_y * 2.0
    local child_flags = ImGui.WindowFlags_HorizontalScrollbar
    if layout.scrolling.enable_extra_decorations then
      child_flags = child_flags | ImGui.WindowFlags_AlwaysVerticalScrollbar
    end
    for i,name in ipairs(names) do
      local scroll_x, scroll_max_x = 0.0, 0.0
      if ImGui.BeginChild(ctx, i, -100, child_height, ImGui.ChildFlags_Borders, child_flags) then
        if scroll_to_off then
          ImGui.SetScrollX(ctx, layout.scrolling.scroll_to_off_px)
        end
        if scroll_to_pos then
          ImGui.SetScrollFromPosX(ctx, ImGui.GetCursorStartPos(ctx) + layout.scrolling.scroll_to_pos_px, (i - 1) * 0.25)
        end
        for item = 0, 99 do
          if item > 0 then
            ImGui.SameLine(ctx)
          end
          if layout.scrolling.enable_track and item == layout.scrolling.track_item then
            ImGui.TextColored(ctx, 0xFFFF00FF, ('Item %d'):format(item))
            ImGui.SetScrollHereX(ctx, (i - 1) * 0.25) -- 0.0:left, 0.5:center, 1.0:right
          else
            ImGui.Text(ctx, ('Item %d'):format(item))
          end
        end
        scroll_x = ImGui.GetScrollX(ctx)
        scroll_max_x = ImGui.GetScrollMaxX(ctx)
        ImGui.EndChild(ctx)
      end
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, ('%s\n%.0f/%.0f'):format(name, scroll_x, scroll_max_x))
      ImGui.Spacing(ctx)
    end
    ImGui.PopID(ctx)

    -- Miscellaneous Horizontal Scrolling Demo
    demo.HelpMarker(
      'Horizontal scrolling for a window is enabled via the WindowFlags_HorizontalScrollbar flag.\n\n\z
       You may want to also explicitly specify content width by using SetNextWindowContentWidth() before Begin().')
    rv,layout.scrolling.lines = ImGui.SliderInt(ctx, 'Lines', layout.scrolling.lines, 1, 15)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 3.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 2.0, 1.0)
    local scrolling_child_width = ImGui.GetFrameHeightWithSpacing(ctx) * 7 + 30
    local scroll_x, scroll_max_x = 0.0, 0.0
    if ImGui.BeginChild(ctx, 'scrolling', 0, scrolling_child_width, ImGui.ChildFlags_Borders, ImGui.WindowFlags_HorizontalScrollbar) then
      for line = 0, layout.scrolling.lines - 1 do
        -- Display random stuff. For the sake of this trivial demo we are using basic Button() + SameLine()
        -- If you want to create your own time line for a real application you may be better off manipulating
        -- the cursor position yourself, aka using SetCursorPos/SetCursorScreenPos to position the widgets
        -- yourself. You may also want to use the lower-level ImDrawList API.
        local num_buttons = 10 + ((line & 1 ~= 0) and line * 9 or line * 3)
        for n = 0, num_buttons - 1 do
          if n > 0 then ImGui.SameLine(ctx) end
          ImGui.PushID(ctx, n + line * 1000)
          local label
          if n % 15 == 0 then
            label = 'FizzBuzz'
          elseif n % 3 == 0 then
            label = 'Fizz'
          elseif n % 5 == 0 then
            label = 'Buzz'
          else
            label = tostring(n)
          end
          local hue = n * 0.05
          ImGui.PushStyleColor(ctx, ImGui.Col_Button, demo.HSV(hue, 0.6, 0.6))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, demo.HSV(hue, 0.7, 0.7))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, demo.HSV(hue, 0.8, 0.8))
          ImGui.Button(ctx, label, 40.0 + math.sin(line + n) * 20.0, 0.0)
          ImGui.PopStyleColor(ctx, 3)
          ImGui.PopID(ctx)
        end
      end
      scroll_x = ImGui.GetScrollX(ctx)
      scroll_max_x = ImGui.GetScrollMaxX(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx, 2)
    local scroll_x_delta = 0.0
    ImGui.SmallButton(ctx, '<<')
    if ImGui.IsItemActive(ctx) then
      scroll_x_delta = (0 - ImGui.GetDeltaTime(ctx)) * 1000.0
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, 'Scroll from code'); ImGui.SameLine(ctx)
    ImGui.SmallButton(ctx, '>>')
    if ImGui.IsItemActive(ctx) then
      scroll_x_delta = ImGui.GetDeltaTime(ctx) * 1000.0
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, ('%.0f/%.0f'):format(scroll_x, scroll_max_x))
    if scroll_x_delta ~= 0.0 then
      -- Demonstrate a trick: you can use Begin to set yourself in the context of another window
      -- (here we are already out of your child window)
      if ImGui.BeginChild(ctx, 'scrolling') then
        ImGui.SetScrollX(ctx, ImGui.GetScrollX(ctx) + scroll_x_delta)
        ImGui.EndChild(ctx)
      end
    end
    ImGui.Spacing(ctx)

    rv,layout.scrolling.show_horizontal_contents_size_demo_window =
      ImGui.Checkbox(ctx, 'Show Horizontal contents size demo window',
      layout.scrolling.show_horizontal_contents_size_demo_window)

    if layout.scrolling.show_horizontal_contents_size_demo_window then
      if not layout.horizontal_window then
        layout.horizontal_window = {
          show_h_scrollbar      = true,
          show_button           = true,
          show_tree_nodes       = true,
          show_text_wrapped     = false,
          show_columns          = true,
          show_tab_bar          = true,
          show_child            = false,
          explicit_content_size = false,
          contents_size_x       = 300.0,
        }
      end

      if layout.horizontal_window.explicit_content_size then
        ImGui.SetNextWindowContentSize(ctx, layout.horizontal_window.contents_size_x, 0.0)
      end
      rv,layout.scrolling.show_horizontal_contents_size_demo_window =
        ImGui.Begin(ctx, 'Horizontal contents size demo window', true,
          layout.horizontal_window.show_h_scrollbar and ImGui.WindowFlags_HorizontalScrollbar or ImGui.WindowFlags_None)
      if rv then
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 2, 0)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 2, 0)
        demo.HelpMarker(
          "Test how different widgets react and impact the work rectangle growing when horizontal scrolling is enabled.\n\n\z
           Use 'Metrics->Tools->Show windows rectangles' to visualize rectangles.")
        rv,layout.horizontal_window.show_h_scrollbar =
          ImGui.Checkbox(ctx, 'H-scrollbar', layout.horizontal_window.show_h_scrollbar)
        rv,layout.horizontal_window.show_button =
          ImGui.Checkbox(ctx, 'Button', layout.horizontal_window.show_button)             -- Will grow contents size (unless explicitly overwritten)
        rv,layout.horizontal_window.show_tree_nodes =
          ImGui.Checkbox(ctx, 'Tree nodes', layout.horizontal_window.show_tree_nodes)     -- Will grow contents size and display highlight over full width
        rv,layout.horizontal_window.show_text_wrapped =
          ImGui.Checkbox(ctx, 'Text wrapped', layout.horizontal_window.show_text_wrapped) -- Will grow and use contents size
        rv,layout.horizontal_window.show_columns =
          ImGui.Checkbox(ctx, 'Columns', layout.horizontal_window.show_columns)           -- Will use contents size
        rv,layout.horizontal_window.show_tab_bar =
          ImGui.Checkbox(ctx, 'Tab bar', layout.horizontal_window.show_tab_bar)           -- Will use contents size
        rv,layout.horizontal_window.show_child =
          ImGui.Checkbox(ctx, 'Child', layout.horizontal_window.show_child)               -- Will grow and use contents size
        rv,layout.horizontal_window.explicit_content_size =
          ImGui.Checkbox(ctx, 'Explicit content size', layout.horizontal_window.explicit_content_size)
        ImGui.Text(ctx, ('Scroll %.1f/%.1f %.1f/%.1f'):format(ImGui.GetScrollX(ctx), ImGui.GetScrollMaxX(ctx), ImGui.GetScrollY(ctx), ImGui.GetScrollMaxY(ctx)))
        if layout.horizontal_window.explicit_content_size then
          ImGui.SameLine(ctx)
          ImGui.SetNextItemWidth(ctx, 100)
          rv,layout.horizontal_window.contents_size_x =
            ImGui.DragDouble(ctx, '##csx', layout.horizontal_window.contents_size_x)
          local x, y = ImGui.GetCursorScreenPos(ctx)
          local draw_list = ImGui.GetWindowDrawList(ctx)
          ImGui.DrawList_AddRectFilled(draw_list, x, y, x + 10, y + 10, 0xFFFFFFFF)
          ImGui.DrawList_AddRectFilled(draw_list, x + layout.horizontal_window.contents_size_x - 10, y, x + layout.horizontal_window.contents_size_x, y + 10, 0xFFFFFFFF)
          ImGui.Dummy(ctx, 0, 10)
        end
        ImGui.PopStyleVar(ctx, 2)
        ImGui.Separator(ctx)
        if layout.horizontal_window.show_button then
          ImGui.Button(ctx, 'this is a 300-wide button', 300, 0)
        end
        if layout.horizontal_window.show_tree_nodes then
          if ImGui.TreeNode(ctx, 'this is a tree node') then
            if ImGui.TreeNode(ctx, 'another one of those tree node...') then
              ImGui.Text(ctx, 'Some tree contents')
              ImGui.TreePop(ctx)
            end
            ImGui.TreePop(ctx)
          end
          ImGui.CollapsingHeader(ctx, 'CollapsingHeader', true)
        end
        if layout.horizontal_window.show_text_wrapped then
          ImGui.TextWrapped(ctx, 'This text should automatically wrap on the edge of the work rectangle.')
        end
        if layout.horizontal_window.show_columns then
          ImGui.Text(ctx, 'Tables:')
          if ImGui.BeginTable(ctx, 'table', 4, ImGui.TableFlags_Borders) then
            for n = 0, 3 do
              ImGui.TableNextColumn(ctx)
              ImGui.Text(ctx, ('Width %.2f'):format(ImGui.GetContentRegionAvail(ctx)))
            end
            ImGui.EndTable(ctx)
          end
          -- ImGui.Text(ctx, 'Columns:')
          -- ImGui.Columns(ctx, 4)
          -- for n = 0, 3 do
          --   ImGui.Text(ctx, ('Width %.2f'):format(ImGui.GetColumnWidth()))
          --   ImGui.NextColumn(ctx)
          -- end
          -- ImGui.Columns(ctx, 1)
        end
        if layout.horizontal_window.show_tab_bar and ImGui.BeginTabBar(ctx, 'Hello') then
          if ImGui.BeginTabItem(ctx, 'OneOneOne') then ImGui.EndTabItem(ctx) end
          if ImGui.BeginTabItem(ctx, 'TwoTwoTwo') then ImGui.EndTabItem(ctx) end
          if ImGui.BeginTabItem(ctx, 'ThreeThreeThree') then ImGui.EndTabItem(ctx) end
          if ImGui.BeginTabItem(ctx, 'FourFourFour') then ImGui.EndTabItem(ctx) end
          ImGui.EndTabBar(ctx)
        end
        if layout.horizontal_window.show_child then
          if ImGui.BeginChild(ctx, 'child', 0, 0, ImGui.ChildFlags_Borders) then
            ImGui.EndChild(ctx)
          end
        end
        ImGui.End(ctx)
      end
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Text Clipping') then
    if not layout.clipping then
      layout.clipping = {
        size_w   = 100.0, size_h   = 100.0,
        offset_x =  30.0, offset_y =  30.0,
      }
    end

    rv,layout.clipping.size_w,layout.clipping.size_h =
      ImGui.DragDouble2(ctx, 'size', layout.clipping.size_w, layout.clipping.size_h,
      0.5, 1.0, 200.0, '%.0f')
    ImGui.TextWrapped(ctx, '(Click and drag to scroll)')

    demo.HelpMarker(
      '(Left) Using PushClipRect():\n\z
       Will alter ImGui hit-testing logic + DrawList rendering.\n\z
       (use this if you want your clipping rectangle to affect interactions)\n\n\z
       (Center) Using DrawList_PushClipRect():\n\z
       Will alter DrawList rendering only.\n\z
       (use this as a shortcut if you are only using DrawList calls)\n\n\z
       (Right) Using DrawList_AddText() with a fine ClipRect:\n\z
       Will alter only this specific DrawList_AddText() rendering.\n\z
       This is often used internally to avoid altering the clipping rectangle and minimize draw calls.')

    for n = 0, 2 do
      if n > 0 then ImGui.SameLine(ctx) end

      ImGui.PushID(ctx, n)
      ImGui.InvisibleButton(ctx, '##canvas', layout.clipping.size_w, layout.clipping.size_h)
      if ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, ImGui.MouseButton_Left) then
        local mouse_delta_x, mouse_delta_y = ImGui.GetMouseDelta(ctx)
        layout.clipping.offset_x = layout.clipping.offset_x + mouse_delta_x
        layout.clipping.offset_y = layout.clipping.offset_y + mouse_delta_y
      end
      ImGui.PopID(ctx)

      if ImGui.IsItemVisible(ctx) then -- Skip rendering as DrawList elements are not clipped.
        local p0_x, p0_y = ImGui.GetItemRectMin(ctx)
        local p1_x, p1_y = ImGui.GetItemRectMax(ctx)
        local text_str = 'Line 1 hello\nLine 2 clip me!'
        local text_pos_x, text_pos_y = p0_x + layout.clipping.offset_x, p0_y + layout.clipping.offset_y

        local draw_list = ImGui.GetWindowDrawList(ctx)
        if n == 0 then
          ImGui.PushClipRect(ctx, p0_x, p0_y, p1_x, p1_y, true)
          ImGui.DrawList_AddRectFilled(draw_list, p0_x, p0_y, p1_x, p1_y, 0x5a5a78ff)
          ImGui.DrawList_AddText(draw_list, text_pos_x, text_pos_y, 0xffffffff, text_str)
          ImGui.PopClipRect(ctx)
        elseif n == 1 then
          ImGui.DrawList_PushClipRect(draw_list, p0_x, p0_y, p1_x, p1_y, true)
          ImGui.DrawList_AddRectFilled(draw_list, p0_x, p0_y, p1_x, p1_y, 0x5a5a78ff)
          ImGui.DrawList_AddText(draw_list, text_pos_x, text_pos_y, 0xffffffff, text_str)
          ImGui.DrawList_PopClipRect(draw_list)
        elseif n == 2 then
          ImGui.DrawList_AddRectFilled(draw_list, p0_x, p0_y, p1_x, p1_y, 0x5a5a78ff)
          ImGui.DrawList_AddTextEx(draw_list, ImGui.GetFont(ctx), ImGui.GetFontSize(ctx),
            text_pos_x, text_pos_y, 0xffffffff, text_str, 0.0,
            p0_x, p0_y, p1_x, p1_y)
        end
      end
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Overlap Mode') then
    if not layout.overlap then
      layout.overlap = {
        enable_allow_overlap = true,
      }
    end

    demo.HelpMarker(
      "Hit-testing is by default performed in item submission order, which generally is perceived as 'back-to-front'.\n\n\z
       By using SetNextItemAllowOverlap() you can notify that an item may be overlapped by another. \z
       Doing so alters the hovering logic: items using AllowOverlap mode requires an extra frame to accept hovered state.")
    rv, layout.overlap.enable_allow_overlap = ImGui.Checkbox(ctx, 'Enable AllowOverlap', layout.overlap.enable_allow_overlap)

    local button1_pos_x, button1_pos_y = ImGui.GetCursorScreenPos(ctx)
    local button2_pos_x, button2_pos_y = button1_pos_x + 50.0, button1_pos_y + 50.0
    if layout.overlap.enable_allow_overlap then
      ImGui.SetNextItemAllowOverlap(ctx)
    end
    ImGui.Button(ctx, 'Button 1', 80, 80)
    ImGui.SetCursorScreenPos(ctx, button2_pos_x, button2_pos_y)
    ImGui.Button(ctx, 'Button 2', 80, 80)

    -- This is typically used with width-spanning items.
    -- (note that Selectable() has a dedicated flag SelectableFlags_AllowOverlap, which is a shortcut
    -- for using SetNextItemAllowOverlap(). For demo purpose we use SetNextItemAllowOverlap() here.)
    if layout.overlap.enable_allow_overlap then
      ImGui.SetNextItemAllowOverlap(ctx)
    end
    ImGui.Selectable(ctx, 'Some Selectable', false)
    ImGui.SameLine(ctx)
    ImGui.SmallButton(ctx, '++')

    ImGui.TreePop(ctx)
  end
end

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Layout & Scrolling', true)
  if visible then
    demo.DemoWindowLayout()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
