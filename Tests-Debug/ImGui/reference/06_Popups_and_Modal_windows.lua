-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Popups & Modal windows
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Popups & Modal windows')
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
-- Contenido de la seccion: Popups & Modal windows
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

function demo.DemoWindowPopups()
  if not ImGui.CollapsingHeader(ctx, 'Popups & Modal windows') then return end

  local rv

  -- The properties of popups windows are:
  -- - They block normal mouse hovering detection outside them. (*)
  -- - Unless modal, they can be closed by clicking anywhere outside them, or by pressing Escape.
  -- - Their visibility state (~bool) is held internally by Dear ImGui instead of being held by the programmer as
  --   we are used to with regular Begin() calls. User can manipulate the visibility state by calling OpenPopup().
  -- (*) One can use IsItemHovered(HoveredFlags_AllowWhenBlockedByPopup) to bypass it and detect hovering even
  --     when normally blocked by a popup.
  -- Those three properties are connected. The library needs to hold their visibility state BECAUSE it can close
  -- popups at any time.

  -- Typical use for regular windows:
  --   bool my_tool_is_active = false; if (ImGui.Button("Open")) my_tool_is_active = true; [...] if (my_tool_is_active) Begin("My Tool", &my_tool_is_active) { [...] } End();
  -- Typical use for popups:
  --   if (ImGui.Button("Open")) ImGui.OpenPopup("MyPopup"); if (ImGui.BeginPopup("MyPopup") { [...] EndPopup(); }

  -- With popups we have to go through a library call (here OpenPopup) to manipulate the visibility state.
  -- This may be a bit confusing at first but it should quickly make sense. Follow on the examples below.

  if ImGui.TreeNode(ctx, 'Popups') then
    if not popups.popups then
      popups.popups = {
        selected_fish = -1,
        toggles = {true, false, false, false, false},
      }
    end

    ImGui.TextWrapped(ctx,
      'When a popup is active, it inhibits interacting with windows that are behind the popup. \z
       Clicking outside the popup closes it.')

    local names = {'Bream', 'Haddock', 'Mackerel', 'Pollock', 'Tilefish'}

    -- Simple selection popup (if you want to show the current selection inside the Button itself,
    -- you may want to build a string using the "###" operator to preserve a constant ID with a variable label)
    if ImGui.Button(ctx, 'Select..') then
      ImGui.OpenPopup(ctx, 'my_select_popup')
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, names[popups.popups.selected_fish] or '<None>')
    if ImGui.BeginPopup(ctx, 'my_select_popup') then
      ImGui.SeparatorText(ctx, 'Aquarium')
      for i,fish in ipairs(names) do
        if ImGui.Selectable(ctx, fish) then
          popups.popups.selected_fish = i
        end
      end
      ImGui.EndPopup(ctx)
    end

    -- Showing a menu with toggles
    if ImGui.Button(ctx, 'Toggle..') then
      ImGui.OpenPopup(ctx, 'my_toggle_popup')
    end
    if ImGui.BeginPopup(ctx, 'my_toggle_popup') then
      for i,fish in ipairs(names) do
        rv,popups.popups.toggles[i] = ImGui.MenuItem(ctx, fish, '', popups.popups.toggles[i])
      end
      if ImGui.BeginMenu(ctx, 'Sub-menu') then
        ImGui.MenuItem(ctx, 'Click me')
        ImGui.EndMenu(ctx)
      end

      ImGui.Separator(ctx)
      ImGui.Text(ctx, 'Tooltip here')
      ImGui.SetItemTooltip(ctx, 'I am a tooltip over a popup')

      if ImGui.Button(ctx, 'Stacked Popup') then
        ImGui.OpenPopup(ctx, 'another popup')
      end
      if ImGui.BeginPopup(ctx, 'another popup') then
        for i,fish in ipairs(names) do
          rv,popups.popups.toggles[i] = ImGui.MenuItem(ctx, fish, '', popups.popups.toggles[i])
        end
        if ImGui.BeginMenu(ctx, 'Sub-menu') then
          ImGui.MenuItem(ctx, 'Click me')
          if ImGui.Button(ctx, 'Stacked Popup') then
            ImGui.OpenPopup(ctx, 'another popup')
          end
          if ImGui.BeginPopup(ctx, 'another popup') then
            ImGui.Text(ctx, 'I am the last one here.')
            ImGui.EndPopup(ctx)
          end
          ImGui.EndMenu(ctx)
        end
        ImGui.EndPopup(ctx)
      end
      ImGui.EndPopup(ctx)
    end

    -- Call the more complete ShowExampleMenuFile which we use in various places of this demo
    if ImGui.Button(ctx, 'With a menu..') then
      ImGui.OpenPopup(ctx, 'my_file_popup')
    end
    if ImGui.BeginPopup(ctx, 'my_file_popup', ImGui.WindowFlags_MenuBar) then
      if ImGui.BeginMenuBar(ctx) then
        if ImGui.BeginMenu(ctx, 'File') then
          demo.ShowExampleMenuFile()
          ImGui.EndMenu(ctx)
        end
        if ImGui.BeginMenu(ctx, 'Edit') then
          ImGui.MenuItem(ctx, 'Dummy')
          ImGui.EndMenu(ctx)
        end
        ImGui.EndMenuBar(ctx)
      end
      ImGui.Text(ctx, 'Hello from popup!')
      ImGui.Button(ctx, 'This is a dummy button..')
      ImGui.EndPopup(ctx)
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Context menus') then
    if not popups.context then
      popups.context = {
        value = 0.5,
        name  = 'Label1',
        selected = 0,
      }
    end

    demo.HelpMarker('"Context" functions are simple helpers to associate a Popup to a given Item or Window identifier.')

    -- BeginPopupContextItem() is a helper to provide common/simple popup behavior of essentially doing:
    --     if (id == 0)
    --         id = GetItemID(); // Use last item id
    --     if (IsItemHovered() && IsMouseReleased(MouseButton_Right))
    --         OpenPopup(id);
    --     return BeginPopup(id);
    -- For advanced uses you may want to replicate and customize this code.
    -- See more details in BeginPopupContextItem().

    -- Example 1
    -- When used after an item that has an ID (e.g. Button), we can skip providing an ID to BeginPopupContextItem(),
    -- and BeginPopupContextItem() will use the last item ID as the popup ID.
    do
      local names = {'Label1', 'Label2', 'Label3', 'Label4', 'Label5'}
      for n, name in ipairs(names) do
        if ImGui.Selectable(ctx, name, popups.context.selected == n) then
          popups.context.selected = n
        end
        if ImGui.BeginPopupContextItem(ctx) then -- use last item id as popup id
          popups.context.selected = n
          ImGui.Text(ctx, ('This a popup for "%s"!'):format(name))
          if ImGui.Button(ctx, 'Close') then
            ImGui.CloseCurrentPopup(ctx)
          end
          ImGui.EndPopup(ctx)
        end
        ImGui.SetItemTooltip(ctx, 'Right-click to open popup')
      end
    end

    -- Example 2
    -- Popup on a Text() element which doesn't have an identifier: we need to provide an identifier to BeginPopupContextItem().
    -- Using an explicit identifier is also convenient if you want to activate the popups from different locations.
    do
      demo.HelpMarker("Text() elements don't have stable identifiers so we need to provide one.")
      ImGui.Text(ctx, ('Value = %.6f <-- (1) right-click this text'):format(popups.context.value))
      if ImGui.BeginPopupContextItem(ctx, 'my popup') then
        if ImGui.Selectable(ctx, 'Set to zero') then popups.context.value = 0.0      end
        if ImGui.Selectable(ctx, 'Set to PI')   then popups.context.value = 3.141592 end
        ImGui.SetNextItemWidth(ctx, -FLT_MIN)
        rv,popups.context.value = ImGui.DragDouble(ctx, '##Value', popups.context.value, 0.1, 0.0, 0.0)
        ImGui.EndPopup(ctx)
      end

      -- We can also use OpenPopupOnItemClick() to toggle the visibility of a given popup.
      -- Here we make it that right-clicking this other text element opens the same popup as above.
      -- The popup itself will be submitted by the code above.
      ImGui.Text(ctx, '(2) Or right-click this text')
      ImGui.OpenPopupOnItemClick(ctx, 'my popup', ImGui.PopupFlags_MouseButtonRight)

      -- Back to square one: manually open the same popup.
      if ImGui.Button(ctx, '(3) Or click this button') then
        ImGui.OpenPopup(ctx, 'my popup')
      end
    end

    -- Example 3
    -- When using BeginPopupContextItem() with an implicit identifier (NULL == use last item ID),
    -- we need to make sure your item identifier is stable.
    -- In this example we showcase altering the item label while preserving its identifier, using the ### operator (see FAQ).
    do
      demo.HelpMarker('Showcase using a popup ID linked to item ID, with the item having a changing label + stable ID using the ### operator.')
      ImGui.Button(ctx, ('Button: %s###Button'):format(popups.context.name)) -- ### operator override ID ignoring the preceding label
      if ImGui.BeginPopupContextItem(ctx) then
        ImGui.Text(ctx, 'Edit name:')
        rv,popups.context.name = ImGui.InputText(ctx, '##edit', popups.context.name)
        if ImGui.Button(ctx, 'Close') then
          ImGui.CloseCurrentPopup(ctx)
        end
        ImGui.EndPopup(ctx)
      end
      ImGui.SameLine(ctx); ImGui.Text(ctx, '(<-- right-click here)')
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Modals') then
    if not popups.modal then
      popups.modal = {
        dont_ask_me_next_time = false,
        item  = 1,
        color = 0x66b30080,
      }
    end

    ImGui.TextWrapped(ctx, 'Modal windows are like popups but the user cannot close them by clicking outside.')

    if ImGui.Button(ctx, 'Delete..') then
      ImGui.OpenPopup(ctx, 'Delete?')
    end

    -- Always center this window when appearing
    local center_x, center_y = ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx))
    ImGui.SetNextWindowPos(ctx, center_x, center_y, ImGui.Cond_Appearing, 0.5, 0.5)

    if ImGui.BeginPopupModal(ctx, 'Delete?', nil, ImGui.WindowFlags_AlwaysAutoResize) then
      ImGui.Text(ctx, 'All those beautiful files will be deleted.\nThis operation cannot be undone!')
      ImGui.Separator(ctx)

      --static int unused_i = 0;
      --ImGui.Combo("Combo", &unused_i, "Delete\0Delete harder\0");

      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
      rv,popups.modal.dont_ask_me_next_time =
        ImGui.Checkbox(ctx, "Don't ask me next time", popups.modal.dont_ask_me_next_time)
      ImGui.PopStyleVar(ctx)

      if ImGui.Button(ctx, 'OK', 120, 0) then ImGui.CloseCurrentPopup(ctx) end
      ImGui.SetItemDefaultFocus(ctx)
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'Cancel', 120, 0) then ImGui.CloseCurrentPopup(ctx) end
      ImGui.EndPopup(ctx)
    end

    if ImGui.Button(ctx, 'Stacked modals..') then
      ImGui.OpenPopup(ctx, 'Stacked 1')
    end
    if ImGui.BeginPopupModal(ctx, 'Stacked 1', nil, ImGui.WindowFlags_MenuBar) then
      if ImGui.BeginMenuBar(ctx) then
        if ImGui.BeginMenu(ctx, 'File') then
          if ImGui.MenuItem(ctx, 'Some menu item') then end
          ImGui.EndMenu(ctx)
        end
        ImGui.EndMenuBar(ctx)
      end
      ImGui.Text(ctx, 'Hello from Stacked The First\nUsing style.Colors[Col_ModalWindowDimBg] behind it.')

      -- Testing behavior of widgets stacking their own regular popups over the modal.
      rv,popups.modal.item  = ImGui.Combo(ctx, 'Combo', popups.modal.item, 'aaaa\0bbbb\0cccc\0dddd\0eeee\0')
      rv,popups.modal.color = ImGui.ColorEdit4(ctx, 'Color', popups.modal.color)

      if ImGui.Button(ctx, 'Add another modal..') then
        ImGui.OpenPopup(ctx, 'Stacked 2')
      end

      -- Also demonstrate passing p_open=true to BeginPopupModal(), this will create a regular close button which
      -- will close the popup.
      local unused_open = true
      if ImGui.BeginPopupModal(ctx, 'Stacked 2', unused_open) then
        ImGui.Text(ctx, 'Hello from Stacked The Second!')
        rv,popups.modal.color = ImGui.ColorEdit4(ctx, 'Color', popups.modal.color) -- Allow opening another nested popup
        if ImGui.Button(ctx, 'Close') then
          ImGui.CloseCurrentPopup(ctx)
        end
        ImGui.EndPopup(ctx)
      end

      if ImGui.Button(ctx, 'Close') then
        ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.EndPopup(ctx)
    end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Menus inside a regular window') then
    ImGui.TextWrapped(ctx, "Below we are testing adding menu items to a regular window. It's rather unusual but should work!")
    ImGui.Separator(ctx)

    ImGui.MenuItem(ctx, 'Menu item', 'Ctrl+M')
    if ImGui.BeginMenu(ctx, 'Menu inside a regular window') then
      demo.ShowExampleMenuFile()
      ImGui.EndMenu(ctx)
    end
    ImGui.Separator(ctx)
    ImGui.TreePop(ctx)
  end
end

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Popups & Modal windows', true)
  if visible then
    demo.DemoWindowPopups()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
