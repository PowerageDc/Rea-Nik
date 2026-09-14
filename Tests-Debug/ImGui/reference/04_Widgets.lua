-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Widgets
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Widgets')
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
-- Contenido de la seccion: Widgets
-------------------------------------------------------------------------------

local function DemoWindowWidgetsBasic()
  local rv
  if not ImGui.TreeNode(ctx, 'Basic') then return end

  if not widgets.basic then
    widgets.basic = {
      clicked = 0,
      check   = true,
      radio   = 0,
      counter = 0,
      curitem = 0,
      str0    = 'Hello, world!',
      str1    = '',
      vec4a   = reaper.new_array({0.10, 0.20, 0.30, 0.44}),
      i0      = 123,
      i1      = 50,
      i2      = 42,
      i3      = 128,
      i4      = 0,
      d0      = 999999.00000001,
      d1      = 1e10,
      d2      = 1.00,
      d3      = 0.0067,
      d4      = 0.123,
      d5      = 0.0,
      angle   = 0.0,
      elem    = 1,
      col1    = 0xff0033,   -- 0xRRGGBB
      col2    = 0x66b2007f, -- 0xRRGGBBAA
      listcur = 0,
    }
  end

  ImGui.SeparatorText(ctx, 'General')
  if ImGui.Button(ctx, 'Button') then
    widgets.basic.clicked = widgets.basic.clicked + 1
  end
  if widgets.basic.clicked & 1 ~= 0 then
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, 'Thanks for clicking me!')
  end

  rv,widgets.basic.check = ImGui.Checkbox(ctx, 'checkbox', widgets.basic.check)

  rv,widgets.basic.radio = ImGui.RadioButtonEx(ctx, 'radio a', widgets.basic.radio, 0); ImGui.SameLine(ctx)
  rv,widgets.basic.radio = ImGui.RadioButtonEx(ctx, 'radio b', widgets.basic.radio, 1); ImGui.SameLine(ctx)
  rv,widgets.basic.radio = ImGui.RadioButtonEx(ctx, 'radio c', widgets.basic.radio, 2)

  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextLinkOpenURL(ctx, 'Hyperlink', 'https://forum.cockos.com/showthread.php?t=250419')

  -- Color buttons, demonstrate using PushID() to add unique identifier in the ID stack, and changing style.
  for i = 0, 6 do
    if i > 0 then
      ImGui.SameLine(ctx)
    end
    ImGui.PushID(ctx, i)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button,        demo.HSV(i / 7.0, 0.6, 0.6, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, demo.HSV(i / 7.0, 0.7, 0.7, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  demo.HSV(i / 7.0, 0.8, 0.8, 1.0))
    ImGui.Button(ctx, 'Click')
    ImGui.PopStyleColor(ctx, 3)
    ImGui.PopID(ctx)
  end

  -- Use AlignTextToFramePadding() to align text baseline to the baseline of framed widgets elements
  -- (otherwise a Text+SameLine+Button sequence will have the text a little too high by default!)
  -- See 'Demo->Layout->Text Baseline Alignment' for details.
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, 'Hold to repeat:')
  ImGui.SameLine(ctx)

  -- Arrow buttons with Repeater
  local spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
  ImGui.PushItemFlag(ctx, ImGui.ItemFlags_ButtonRepeat, true)
  if ImGui.ArrowButton(ctx, '##left', ImGui.Dir_Left) then
    widgets.basic.counter = widgets.basic.counter - 1
  end
  ImGui.SameLine(ctx, 0.0, spacing)
  if ImGui.ArrowButton(ctx, '##right', ImGui.Dir_Right) then
    widgets.basic.counter = widgets.basic.counter + 1
  end
  ImGui.PopItemFlag(ctx)
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, ('%d'):format(widgets.basic.counter))

  ImGui.Button(ctx, 'Tooltip')
  ImGui.SetItemTooltip(ctx, 'I am a tooltip')

  ImGui.LabelText(ctx, 'label', 'Value')

  ImGui.SeparatorText(ctx, 'Inputs')

  do
    rv,widgets.basic.str0 = ImGui.InputText(ctx, 'input text', widgets.basic.str0)
    ImGui.SameLine(ctx); demo.HelpMarker(
      'USER:\n\z
       Hold Shift or use mouse to select text.\n\z
       Ctrl+Left/Right to word jump.\n\z
       Ctrl+A or double-click to select all.\n\z
       Ctrl+X,Ctrl+C,Ctrl+V for clipboard.\n\z
       Ctrl+Z to undo, Ctrl+Y/Ctrl+Shift+Z to redo.\n\z
       Escape to revert.')

    rv,widgets.basic.str1 = ImGui.InputTextWithHint(ctx, 'input text (w/ hint)', 'enter text here', widgets.basic.str1)

    rv,widgets.basic.i0 = ImGui.InputInt(ctx, 'input int', widgets.basic.i0)

    rv,widgets.basic.d0 = ImGui.InputDouble(ctx, 'input double', widgets.basic.d0, 0.01, 1.0, '%.8f')
    rv,widgets.basic.d1 = ImGui.InputDouble(ctx, 'input scientific', widgets.basic.d1, 0.0, 0.0, '%e')
    ImGui.SameLine(ctx); demo.HelpMarker(
      'You can input value using the scientific notation,\n\z
       e.g. "1e+8" becomes "100000000".')

    ImGui.InputDoubleN(ctx, 'input reaper.array', widgets.basic.vec4a)
  end

  ImGui.SeparatorText(ctx, 'Drags')

  do
    rv,widgets.basic.i1 = ImGui.DragInt(ctx, 'drag int', widgets.basic.i1, 1)
    ImGui.SameLine(ctx); demo.HelpMarker(
      'Click and drag to edit value.\n\z
       Hold Shift/Alt for faster/slower edit.\n\z
       Double-click or Ctrl+click to input value.')

    rv,widgets.basic.i2 = ImGui.DragInt(ctx, 'drag int 0..100', widgets.basic.i2, 1, 0, 100, '%d%%', ImGui.SliderFlags_AlwaysClamp)
    rv,widgets.basic.i3 = ImGui.DragInt(ctx, 'drag int wrap 100..200', widgets.basic.i3, 1, 100, 200, '%d', ImGui.SliderFlags_WrapAround)

    rv,widgets.basic.d2 = ImGui.DragDouble(ctx, 'drag double', widgets.basic.d2, 0.005)
    rv,widgets.basic.d3 = ImGui.DragDouble(ctx, 'drag small double', widgets.basic.d3, 0.0001, 0.0, 0.0, '%.06f ns')
    -- rv,widgets.basic.d4 = ImGui.DragDouble(ctx, 'drag wrap -1..1', widgets.basic.d4, 0.005, -1.0, 1.0, nil, ImGui.SliderFlags_WrapAround)
  end

  ImGui.SeparatorText(ctx, 'Sliders')

  do
    rv,widgets.basic.i4 = ImGui.SliderInt(ctx, 'slider int', widgets.basic.i4, -1, 3)
    ImGui.SameLine(ctx); demo.HelpMarker('Ctrl+click to input value.')

    rv,widgets.basic.d4 = ImGui.SliderDouble(ctx, 'slider double', widgets.basic.d4, 0.0, 1.0, 'ratio = %.3f')
    rv,widgets.basic.d5 = ImGui.SliderDouble(ctx, 'slider double (log)', widgets.basic.d5, -10.0, 10.0, '%.4f', ImGui.SliderFlags_Logarithmic)

    rv,widgets.basic.angle = ImGui.SliderAngle(ctx, 'slider angle', widgets.basic.angle)

    -- Using the format string to display a name instead of an integer.
    -- Here we completely omit '%d' from the format string, so it'll only display a name.
    -- This technique can also be used with DragInt().
    local elements = {'Fire', 'Earth', 'Air', 'Water'}
    local current_elem = elements[widgets.basic.elem] or 'Unknown'
    rv,widgets.basic.elem = ImGui.SliderInt(ctx, 'slider enum', widgets.basic.elem, 1, #elements, current_elem) -- Use ImGuiSliderFlags_NoInput flag to disable Ctrl+Click here.
    ImGui.SameLine(ctx)
    demo.HelpMarker(
      'Using the format string parameter to display a name instead \z
       of the underlying integer.')
  end

  ImGui.SeparatorText(ctx, 'Selectors/Pickers')

  do
    rv,widgets.basic.col1 = ImGui.ColorEdit3(ctx, 'color 1', widgets.basic.col1)
    ImGui.SameLine(ctx); demo.HelpMarker(
      'Click on the color square to open a color picker.\n\z
       Click and hold to use drag and drop.\n\z
       Right-click on the color square to show options.\n\z
       Ctrl+click on individual component to input value.')

    rv, widgets.basic.col2 = ImGui.ColorEdit4(ctx, 'color 2', widgets.basic.col2)
  end

  do
    -- Using the _simplified_ one-liner Combo() api here
    -- See "Combo" section for examples of how to use the more flexible BeginCombo()/EndCombo() api.
    local items = 'AAAA\0BBBB\0CCCC\0DDDD\0EEEE\0FFFF\0GGGG\0HHHH\0IIIIIII\0JJJJ\0KKKKKKK\0'
    rv,widgets.basic.curitem = ImGui.Combo(ctx, 'combo', widgets.basic.curitem, items)
    ImGui.SameLine(ctx); demo.HelpMarker(
      'Using the simplified one-liner Combo API here.\n\z
       Refer to the "Combo" section below for an explanation of how to use the more flexible and general BeginCombo/EndCombo API.')
  end

  do
    -- Using the _simplified_ one-liner ListBox() api here
    -- See "List boxes" section for examples of how to use the more flexible BeginListBox()/EndListBox() api.
    local items = 'Apple\0Banana\0Cherry\0Kiwi\0Mango\0Orange\0Pineapple\0Strawberry\0Watermelon\0'
    rv,widgets.basic.listcur = ImGui.ListBox(ctx, 'listbox\n(single select)', widgets.basic.listcur, items, 4)
    ImGui.SameLine(ctx)
    demo.HelpMarker(
      'Using the simplified one-liner ListBox API here.\n\z
       Refer to the "List boxes" section below for an explanation of how to use\z
       the more flexible and general BeginListBox/EndListBox API.')
  end

  -- Testing ImGuiOnceUponAFrame helper.
  -- static ImGuiOnceUponAFrame once;
  -- for i = 1, 5 do
  --   if (once)
  --     ImGui.Text(ctx, 'This will be displayed only once.')
  -- end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsBullets()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsBullets()
  if not ImGui.TreeNode(ctx, 'Bullets') then return end

  ImGui.BulletText(ctx, 'Bullet point 1')
  ImGui.BulletText(ctx, 'Bullet point 2\nOn multiple lines')
  if ImGui.TreeNode(ctx, 'Tree node') then
    ImGui.BulletText(ctx, 'Another bullet point')
    ImGui.TreePop(ctx)
  end
  ImGui.Bullet(ctx); ImGui.Text(ctx, 'Bullet point 3 (two calls)')
  ImGui.Bullet(ctx); ImGui.SmallButton(ctx, 'Button')

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsCollapsingHeaders()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsCollapsingHeaders()
  local rv
  if not ImGui.TreeNode(ctx, 'Collapsing Headers') then return end

  if not widgets.cheads then
    widgets.cheads = {
      closable_group = true,
    }
  end

  rv,widgets.cheads.closable_group = ImGui.Checkbox(ctx, 'Show 2nd header', widgets.cheads.closable_group)

  if ImGui.CollapsingHeader(ctx, 'Header', nil, ImGui.TreeNodeFlags_None) then
    ImGui.Text(ctx, ('IsItemHovered: %s'):format(ImGui.IsItemHovered(ctx)))
    for i = 0, 4 do
      ImGui.Text(ctx, ('Some content %s'):format(i))
    end
  end

  if widgets.cheads.closable_group then
    rv,widgets.cheads.closable_group = ImGui.CollapsingHeader(ctx, 'Header with a close button', true)
    if rv then
      ImGui.Text(ctx, ('IsItemHovered: %s'):format(ImGui.IsItemHovered(ctx)))
      for i = 0, 4 do
        ImGui.Text(ctx, ('More content %d'):format(i))
      end
    end
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsColorAndPickers()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsColorAndPickers()
  local rv
  if not ImGui.TreeNode(ctx, 'Color/Picker Widgets') then return end

  if not widgets.colors then
    widgets.colors = {
      rgba               = 0x72909ac8,
      base_flags         = ImGui.ColorEditFlags_None,
      saved_palette      = nil, -- filled later
      backup_color       = nil,
      no_border          = false,
      color_picker_flags = ImGui.ColorEditFlags_AlphaBar,
      ref_color          = false,
      ref_color_rgba     = 0xff00ff80,
      display_mode       = 0,
      picker_mode        = 0,
      hsva               = 0x3bffffff,
      raw_hsv            = reaper.new_array(4),
    }
  end

  ImGui.SeparatorText(ctx, 'Options')
  rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_NoAlpha', widgets.colors.base_flags, ImGui.ColorEditFlags_NoAlpha)
  if rv then
    widgets.colors.rgba = widgets.colors.base_flags & ImGui.ColorEditFlags_NoAlpha ~= 0 and demo.RgbaToArgb(widgets.colors.rgba) or demo.ArgbToRgba(widgets.colors.rgba)
  end
  rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_AlphaOpaque', widgets.colors.base_flags, ImGui.ColorEditFlags_AlphaOpaque)
  rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_AlphaNoBg', widgets.colors.base_flags, ImGui.ColorEditFlags_AlphaNoBg)
  rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_AlphaPreviewHalf', widgets.colors.base_flags, ImGui.ColorEditFlags_AlphaPreviewHalf)
  rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_NoDragDrop', widgets.colors.base_flags, ImGui.ColorEditFlags_NoDragDrop)
  rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_NoOptions', widgets.colors.base_flags, ImGui.ColorEditFlags_NoOptions); ImGui.SameLine(ctx); demo.HelpMarker('Right-click on the individual color widget to show options.')
  -- rv,widgets.colors.base_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_HDR', widgets.colors.base_flags, ImGui.ColorEditFlags_HDR); ImGui::SameLine(ctx); HelpMarker('Currently all this does is to lift the 0..1 limits on dragging widgets.')

  ImGui.SeparatorText(ctx, 'Inline color editor')
  ImGui.Text(ctx, 'Color widget:')
  ImGui.SameLine(ctx); demo.HelpMarker(
    'Click on the color square to open a color picker.\n\z
     Ctrl+click on individual component to input value.\n')
  local has_alpha = widgets.colors.base_flags & ImGui.ColorEditFlags_NoAlpha == 0
  local argb = has_alpha and demo.RgbaToArgb(widgets.colors.rgba) or widgets.colors.rgba
  rv,argb = ImGui.ColorEdit3(ctx, 'MyColor##1', argb, widgets.colors.base_flags)
  if rv then
    widgets.colors.rgba = has_alpha and demo.ArgbToRgba(argb) or argb
  end

  ImGui.Text(ctx, 'Color widget HSV with Alpha:')
  rv,widgets.colors.rgba = ImGui.ColorEdit4(ctx, 'MyColor##2', widgets.colors.rgba, ImGui.ColorEditFlags_DisplayHSV | widgets.colors.base_flags)

  ImGui.Text(ctx, 'Color widget with Float Display:')
  rv,widgets.colors.rgba = ImGui.ColorEdit4(ctx, 'MyColor##2f', widgets.colors.rgba, ImGui.ColorEditFlags_Float | widgets.colors.base_flags)

  ImGui.Text(ctx, 'Color button with Picker:')
  ImGui.SameLine(ctx); demo.HelpMarker(
    'With the ColorEditFlags_NoInputs flag you can hide all the slider/text inputs.\n\z
     With the ColorEditFlags_NoLabel flag you can pass a non-empty label which will only \z
     be used for the tooltip and picker popup.')
  rv,widgets.colors.rgba = ImGui.ColorEdit4(ctx, 'MyColor##3', widgets.colors.rgba, ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoLabel | widgets.colors.base_flags)

  ImGui.Text(ctx, 'Color button with Custom Picker Popup:')

  -- Generate a default palette. The palette will persist and can be edited.
  if not widgets.colors.saved_palette then
    widgets.colors.saved_palette = {}
    for n = 0, 31 do
      table.insert(widgets.colors.saved_palette, demo.HSV(n / 31.0, 0.8, 0.8))
    end
  end

  local open_popup = ImGui.ColorButton(ctx, 'MyColor##3b', widgets.colors.rgba, widgets.colors.base_flags)
  ImGui.SameLine(ctx, 0, (ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)))
  open_popup = ImGui.Button(ctx, 'Palette') or open_popup
  if open_popup then
    ImGui.OpenPopup(ctx, 'mypicker')
    widgets.colors.backup_color = widgets.colors.rgba
  end
  if ImGui.BeginPopup(ctx, 'mypicker') then
    ImGui.Text(ctx, 'MY CUSTOM COLOR PICKER WITH AN AMAZING PALETTE!')
    ImGui.Separator(ctx)
    rv,widgets.colors.rgba = ImGui.ColorPicker4(ctx, '##picker', widgets.colors.rgba, widgets.colors.base_flags | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoSmallPreview)
    ImGui.SameLine(ctx)

    ImGui.BeginGroup(ctx) -- Lock X position
    ImGui.Text(ctx, 'Current')
    ImGui.ColorButton(ctx, '##current', widgets.colors.rgba,
      ImGui.ColorEditFlags_NoPicker |
      ImGui.ColorEditFlags_AlphaPreviewHalf, 60, 40)
    ImGui.Text(ctx, 'Previous')
    if ImGui.ColorButton(ctx, '##previous', widgets.colors.backup_color,
        ImGui.ColorEditFlags_NoPicker |
        ImGui.ColorEditFlags_AlphaPreviewHalf, 60, 40) then
      widgets.colors.rgba = widgets.colors.backup_color
    end
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Palette')
    local palette_button_flags = ImGui.ColorEditFlags_NoAlpha  |
                                  ImGui.ColorEditFlags_NoPicker |
                                  ImGui.ColorEditFlags_NoTooltip
    for n,c in ipairs(widgets.colors.saved_palette) do
      ImGui.PushID(ctx, n)
      if ((n - 1) % 8) ~= 0 then
        ImGui.SameLine(ctx, 0.0, select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)))
      end

      if ImGui.ColorButton(ctx, '##palette', c, palette_button_flags, 20, 20) then
        widgets.colors.rgba = (c << 8) | (widgets.colors.rgba & 0xFF) -- Preserve alpha!
      end

      -- Allow user to drop colors into each palette entry. Note that ColorButton() is already a
      -- drag source by default, unless specifying the ColorEditFlags_NoDragDrop flag.
      if ImGui.BeginDragDropTarget(ctx) then
        local drop_color
        rv,drop_color = ImGui.AcceptDragDropPayloadRGB(ctx)
        if rv then
          widgets.colors.saved_palette[n] = drop_color
        end
        rv,drop_color = ImGui.AcceptDragDropPayloadRGBA(ctx)
        if rv then
          widgets.colors.saved_palette[n] = drop_color >> 8
        end
        ImGui.EndDragDropTarget(ctx)
      end

      ImGui.PopID(ctx)
    end
    ImGui.EndGroup(ctx)
    ImGui.EndPopup(ctx)
  end

  ImGui.Text(ctx, 'Color button only:')
  rv,widgets.colors.no_border = ImGui.Checkbox(ctx, 'ColorEditFlags_NoBorder', widgets.colors.no_border)
  ImGui.ColorButton(ctx, 'MyColor##3c', widgets.colors.rgba,
    widgets.colors.base_flags | (widgets.colors.no_border and ImGui.ColorEditFlags_NoBorder or 0),
    80, 80)

  ImGui.SeparatorText(ctx, 'Color picker')
  ImGui.PushID(ctx, 'Color picker')
  rv,widgets.colors.color_picker_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_NoAlpha', widgets.colors.color_picker_flags, ImGui.ColorEditFlags_NoAlpha)
  rv,widgets.colors.color_picker_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_AlphaBar', widgets.colors.color_picker_flags, ImGui.ColorEditFlags_AlphaBar)
  rv,widgets.colors.color_picker_flags = ImGui.CheckboxFlags(ctx, 'ColorEditFlags_NoSidePreview', widgets.colors.color_picker_flags, ImGui.ColorEditFlags_NoSidePreview)
  if widgets.colors.color_picker_flags & ImGui.ColorEditFlags_NoSidePreview ~= 0 then
    ImGui.SameLine(ctx)
    rv,widgets.colors.ref_color = ImGui.Checkbox(ctx, 'With Ref Color', widgets.colors.ref_color)
    if widgets.colors.ref_color then
      ImGui.SameLine(ctx)
      rv,widgets.colors.ref_color_rgba = ImGui.ColorEdit4(ctx, '##RefColor',
        widgets.colors.ref_color_rgba, ImGui.ColorEditFlags_NoInputs | widgets.colors.base_flags)
    end
  end

  rv,widgets.colors.picker_mode = ImGui.Combo(ctx, 'Picker Mode', widgets.colors.picker_mode, 'Auto/Current\0ColorEditFlags_PickerHueBar\0ColorEditFlags_PickerHueWheel\0')
  ImGui.SameLine(ctx); demo.HelpMarker('When not specified explicitly, user can right-click the picker to change mode.')

  rv,widgets.colors.display_mode = ImGui.Combo(ctx, 'Display Mode', widgets.colors.display_mode, 'Auto/Current\0ColorEditFlags_NoInputs\0ColorEditFlags_DisplayRGB\0ColorEditFlags_DisplayHSV\0ColorEditFlags_DisplayHex\0')
  ImGui.SameLine(ctx); demo.HelpMarker(
    "ColorEdit defaults to displaying RGB inputs if you don't specify a display mode, \z
     but the user can change it with a right-click on those inputs.\n\nColorPicker defaults to displaying RGB+HSV+Hex \z
     if you don't specify a display mode.\n\nYou can change the defaults using SetColorEditOptions().")

  local flags = widgets.colors.base_flags | widgets.colors.color_picker_flags
  if widgets.colors.picker_mode  == 1 then flags = flags | ImGui.ColorEditFlags_PickerHueBar   end
  if widgets.colors.picker_mode  == 2 then flags = flags | ImGui.ColorEditFlags_PickerHueWheel end
  if widgets.colors.display_mode == 1 then flags = flags | ImGui.ColorEditFlags_NoInputs       end -- Disable all RGB/HSV/Hex displays
  if widgets.colors.display_mode == 2 then flags = flags | ImGui.ColorEditFlags_DisplayRGB     end -- Override display mode
  if widgets.colors.display_mode == 3 then flags = flags | ImGui.ColorEditFlags_DisplayHSV     end
  if widgets.colors.display_mode == 4 then flags = flags | ImGui.ColorEditFlags_DisplayHex     end

  has_alpha = widgets.colors.color_picker_flags & ImGui.ColorEditFlags_NoAlpha == 0
  local color = has_alpha and widgets.colors.rgba or demo.RgbaToArgb(widgets.colors.rgba)
  local ref_color = has_alpha and widgets.colors.ref_color_rgba or demo.RgbaToArgb(widgets.colors.ref_color_rgba)
  rv,color = ImGui.ColorPicker4(ctx, 'MyColor##4', color, flags,
    widgets.colors.ref_color and ref_color or nil)
  if rv then
    widgets.colors.rgba = has_alpha and color or demo.ArgbToRgba(color)
  end

  ImGui.Text(ctx, 'Set defaults in code:')
  ImGui.SameLine(ctx); demo.HelpMarker(
    "SetColorEditOptions() is designed to allow you to set boot-time default.\n\z
     We don't have Push/Pop functions because you can force options on a per-widget basis if needed, \z
     and the user can change non-forced ones with the options menu.\nWe don't have a getter to avoid\z
     encouraging you to persistently save values that aren't forward-compatible.")
  if ImGui.Button(ctx, 'Default: Uint8 + HSV + Hue Bar') then
    ImGui.SetColorEditOptions(ctx, ImGui.ColorEditFlags_Uint8 | ImGui.ColorEditFlags_DisplayHSV | ImGui.ColorEditFlags_PickerHueBar)
  end
  if ImGui.Button(ctx, 'Default: Float + Hue Wheel') then -- (NOTE: removed HDR for ReaImGui as we use uint32 for color i/o)
    ImGui.SetColorEditOptions(ctx, ImGui.ColorEditFlags_Float | ImGui.ColorEditFlags_PickerHueWheel)
  end

  -- Always display a small version of both types of pickers
  -- (that's in order to make it more visible in the demo to people who are skimming quickly through it)
  local color = demo.RgbaToArgb(widgets.colors.rgba)
  ImGui.Text(ctx, 'Both types:')
  local w = (ImGui.GetContentRegionAvail(ctx) - select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))) * 0.40
  ImGui.SetNextItemWidth(ctx, w)
  rv,color = ImGui.ColorPicker3(ctx, '##MyColor##5', color, ImGui.ColorEditFlags_PickerHueBar | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
  if rv then widgets.colors.rgba = demo.ArgbToRgba(color) end
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, w)
  rv,color = ImGui.ColorPicker3(ctx, '##MyColor##6', color, ImGui.ColorEditFlags_PickerHueWheel | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoAlpha)
  if rv then widgets.colors.rgba = demo.ArgbToRgba(color) end
  ImGui.PopID(ctx)

  -- HSV encoded support (to avoid RGB<>HSV round trips and singularities when S==0 or V==0)
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, 'HSV encoded colors')
  ImGui.SameLine(ctx); demo.HelpMarker(
    'By default, colors are given to ColorEdit and ColorPicker in RGB, but ColorEditFlags_InputHSV \z
     allows you to store colors as HSV and pass them to ColorEdit and ColorPicker as HSV. This comes with the \z
     added benefit that you can manipulate hue values with the picker even when saturation or value are zero.')
  ImGui.Text(ctx, 'Color widget with InputHSV:')
  rv,widgets.colors.hsva = ImGui.ColorEdit4(ctx, 'HSV shown as RGB##1', widgets.colors.hsva,
    ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_InputHSV | ImGui.ColorEditFlags_Float)
  rv,widgets.colors.hsva = ImGui.ColorEdit4(ctx, 'HSV shown as HSV##1', widgets.colors.hsva,
    ImGui.ColorEditFlags_DisplayHSV | ImGui.ColorEditFlags_InputHSV | ImGui.ColorEditFlags_Float)

  local raw_hsv = widgets.colors.raw_hsv
  raw_hsv[1] = (widgets.colors.hsva >> 24 & 0xFF) / 255.0 -- H
  raw_hsv[2] = (widgets.colors.hsva >> 16 & 0xFF) / 255.0 -- S
  raw_hsv[3] = (widgets.colors.hsva >>  8 & 0xFF) / 255.0 -- V
  raw_hsv[4] = (widgets.colors.hsva       & 0xFF) / 255.0 -- A
  if ImGui.DragDoubleN(ctx, 'Raw HSV values', raw_hsv, 0.01, 0.0, 1.0) then
    widgets.colors.hsva =
      (demo.round(raw_hsv[1] * 0xFF) << 24) |
      (demo.round(raw_hsv[2] * 0xFF) << 16) |
      (demo.round(raw_hsv[3] * 0xFF) <<  8) |
      (demo.round(raw_hsv[4] * 0xFF)      )
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsComboBoxes()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsComboBoxes()
  local rv
  if not ImGui.TreeNode(ctx, 'Combo') then return end

  if not widgets.combos then
    widgets.combos = {
      flags  = ImGui.ComboFlags_None,
      filter = ImGui.CreateTextFilter(),
      item_selected_idx = 1,
      item_current_2 =  0,
      item_current_3 = -1,
    }
    ImGui.Attach(ctx, widgets.combos.filter)
  end

  -- Combo Boxes are also called "Dropdown" in other systems
  -- Expose flags as checkbox for the demo
  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_PopupAlignLeft', widgets.combos.flags, ImGui.ComboFlags_PopupAlignLeft)
  ImGui.SameLine(ctx); demo.HelpMarker('Only makes a difference if the popup is larger than the combo')

  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_NoArrowButton', widgets.combos.flags, ImGui.ComboFlags_NoArrowButton)
  if rv then widgets.combos.flags = widgets.combos.flags & ~ImGui.ComboFlags_NoPreview end -- Clear incompatible flags

  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_NoPreview', widgets.combos.flags, ImGui.ComboFlags_NoPreview)
  if rv then widgets.combos.flags = widgets.combos.flags & ~(ImGui.ComboFlags_NoArrowButton | ImGui.ComboFlags_WidthFitPreview) end -- Clear incompatible flags

  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_WidthFitPreview', widgets.combos.flags, ImGui.ComboFlags_WidthFitPreview)
  if rv then widgets.combos.flags = widgets.combos.flags & ~ImGui.ComboFlags_NoPreview end

  -- Override default popup height
  local height_mask = ImGui.ComboFlags_HeightSmall | ImGui.ComboFlags_HeightRegular | ImGui.ComboFlags_HeightLarge | ImGui.ComboFlags_HeightLargest
  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_HeightSmall', widgets.combos.flags, ImGui.ComboFlags_HeightSmall)
  if rv then widgets.combos.flags = widgets.combos.flags & ~(height_mask & ~ImGui.ComboFlags_HeightSmall)   end
  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_HeightRegular', widgets.combos.flags, ImGui.ComboFlags_HeightRegular)
  if rv then widgets.combos.flags = widgets.combos.flags & ~(height_mask & ~ImGui.ComboFlags_HeightRegular) end
  rv,widgets.combos.flags = ImGui.CheckboxFlags(ctx, 'ComboFlags_HeightLargest', widgets.combos.flags, ImGui.ComboFlags_HeightLargest)
  if rv then widgets.combos.flags = widgets.combos.flags & ~(height_mask & ~ImGui.ComboFlags_HeightLargest) end

  -- Using the generic BeginCombo() API, you have full control over how to display the combo contents.
  -- (your selection data could be an index, a pointer to the object, an id for the object, a flag intrusively
  -- stored in the object itself, etc.)
  local combo_items = {'AAAA', 'BBBB', 'CCCC', 'DDDD', 'EEEE', 'FFFF', 'GGGG', 'HHHH', 'IIII', 'JJJJ', 'KKKK', 'LLLLLLL', 'MMMM', 'OOOOOOO'}

  -- Pass in the preview value visible before opening the combo (it could technically be different contents or not pulled from items[])
  local combo_preview_value = combo_items[widgets.combos.item_selected_idx]

  if ImGui.BeginCombo(ctx, 'combo 1', combo_preview_value, widgets.combos.flags) then
    for i,v in ipairs(combo_items) do
      local is_selected = widgets.combos.item_selected_idx == i
      if ImGui.Selectable(ctx, combo_items[i], is_selected) then
        widgets.combos.item_selected_idx = i
      end

      -- Set the initial focus when opening the combo (scrolling + keyboard navigation focus)
      if is_selected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndCombo(ctx)
  end

  -- Show case embedding a filter using a simple trick: displaying the filter inside combo contents.
  -- See https://github.com/ocornut/imgui/issues/718 for advanced/esoteric alternatives.
  if ImGui.BeginCombo(ctx, 'combo 2 (w/ filter)', combo_preview_value, widgets.combos.flags) then
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
      ImGui.TextFilter_Clear(widgets.combos.filter)
    end
    ImGui.SetNextItemShortcut(ctx, ImGui.Mod_Ctrl | ImGui.Key_F)
    ImGui.TextFilter_Draw(widgets.combos.filter, ctx, '##Filter', -FLT_MIN)

    for n,v in ipairs(combo_items) do
      local is_selected = widgets.combos.item_selected_idx == n
      if ImGui.TextFilter_PassFilter(widgets.combos.filter, combo_items[n]) then
        if ImGui.Selectable(ctx, combo_items[n], is_selected) then
          widgets.combos.item_selected_idx = n
        end
      end
    end
    ImGui.EndCombo(ctx)
  end

  ImGui.Spacing(ctx)
  ImGui.SeparatorText(ctx, 'One-liner variants')
  demo.HelpMarker("The Combo() function is not greatly useful apart from cases were you want to embed all options in a single string.\nFlags above don't apply to this section.")

  -- Simplified one-liner Combo() API, using values packed in a single constant string
  -- This is a convenience for when the selection set is small and known when writing the script.
---@diagnostic disable-next-line: cast-local-type
  combo_items = 'aaaa\0bbbb\0cccc\0dddd\0eeee\0'
  rv,widgets.combos.current_item2 = ImGui.Combo(ctx, 'combo 3 (one-liner)', widgets.combos.current_item2, combo_items)

  -- Simplified one-liner Combo() using an array of const char*
  -- If the selection isn't within 0..count, Combo won't display a preview
  rv,widgets.combos.current_item3 = ImGui.Combo(ctx, 'combo 4 (out of range)', widgets.combos.current_item3, combo_items)

  -- Simplified one-liner Combo() using an accessor function
  -- static int item_current_4 = 0;
  -- ImGui.Combo("combo 5 (function)", &item_current_4, [](void* data, int n) { return ((const char**)data)[n]; }, items, IM_ARRAYSIZE(items));

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsDataTypes()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsDataTypes()
  -- This API is not implemented in ReaImGui
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsDisableBlocks()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsDisableBlocks()
  if ImGui.TreeNode(ctx, 'Disable Blocks') then
---@diagnostic disable-next-line: lowercase-global
    rv,widgets.disable_all = ImGui.Checkbox(ctx, 'Disable entire section above', widgets.disable_all)
    ImGui.SameLine(ctx); demo.HelpMarker('Demonstrate using BeginDisabled()/EndDisabled() across other sections.')
    ImGui.TreePop(ctx)
  end
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsDragAndDrop()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsDragAndDrop()
  local rv
  if not ImGui.TreeNode(ctx, 'Drag and Drop') then return end

  if not widgets.dragdrop then
    widgets.dragdrop = {
      color1 = 0xFF0033,
      color2 = 0x66B30080,
      mode   = 0,
      names  = {
        'Bobby', 'Beatrice', 'Betty',
        'Brianna', 'Barry', 'Bernard',
        'Bibi', 'Blaine', 'Bryn',
      },
      items = {'Item One', 'Item Two', 'Item Three', 'Item Four', 'Item Five'},
      files = {},
    }
  end

  if ImGui.TreeNode(ctx, 'Drag and drop in standard widgets') then
    -- ColorEdit widgets automatically act as drag source and drag target.
    -- They are using standardized payload types accessible using
    -- AcceptDragDropPayloadRGB or AcceptDragDropPayloadRGBA
    -- to allow your own widgets to use colors in their drag and drop interaction.
    -- Also see 'Demo->Widgets->Color/Picker Widgets->Palette' demo.
    demo.HelpMarker('You can drag from the color squares.')
    rv,widgets.dragdrop.color1 = ImGui.ColorEdit3(ctx, 'color 1', widgets.dragdrop.color1)
    rv,widgets.dragdrop.color2 = ImGui.ColorEdit4(ctx, 'color 2', widgets.dragdrop.color2)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Drag and drop to copy/swap items') then
    local mode_copy, mode_move, mode_swap = 0, 1, 2
    if ImGui.RadioButton(ctx, 'Copy', widgets.dragdrop.mode == mode_copy) then widgets.dragdrop.mode = mode_copy end ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, 'Move', widgets.dragdrop.mode == mode_move) then widgets.dragdrop.mode = mode_move end ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, 'Swap', widgets.dragdrop.mode == mode_swap) then widgets.dragdrop.mode = mode_swap end
    for n,name in ipairs(widgets.dragdrop.names) do
      ImGui.PushID(ctx, n)
      if ((n-1) % 3) ~= 0 then
        ImGui.SameLine(ctx)
      end
      ImGui.Button(ctx, name, 60, 60)

      -- Our buttons are both drag sources and drag targets here!
      if ImGui.BeginDragDropSource(ctx, ImGui.DragDropFlags_None) then
        -- Set payload to carry the index of our item (could be anything)
        ImGui.SetDragDropPayload(ctx, 'DND_DEMO_CELL', tostring(n))

        -- Display preview (could be anything, e.g. when dragging an image we could decide to display
        -- the filename and a small preview of the image, etc.)
        if widgets.dragdrop.mode == mode_copy then ImGui.Text(ctx, ('Copy %s'):format(name)) end
        if widgets.dragdrop.mode == mode_move then ImGui.Text(ctx, ('Move %s'):format(name)) end
        if widgets.dragdrop.mode == mode_swap then ImGui.Text(ctx, ('Swap %s'):format(name)) end
        ImGui.EndDragDropSource(ctx)
      end
      if ImGui.BeginDragDropTarget(ctx) then
        local payload
        rv,payload = ImGui.AcceptDragDropPayload(ctx, 'DND_DEMO_CELL')
        if rv then
          local payload_n = tonumber(payload)
          if payload_n ~= nil then
            if widgets.dragdrop.mode == mode_copy then
              widgets.dragdrop.names[n] = widgets.dragdrop.names[payload_n]
            end
            if widgets.dragdrop.mode == mode_move then
              widgets.dragdrop.names[n] = widgets.dragdrop.names[payload_n]
              widgets.dragdrop.names[payload_n] = ''
            end
            if widgets.dragdrop.mode == mode_swap then
              widgets.dragdrop.names[n] = widgets.dragdrop.names[payload_n]
              widgets.dragdrop.names[payload_n] = name
            end
          end
        end
        ImGui.EndDragDropTarget(ctx)
      end
      ImGui.PopID(ctx)
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Drag to reorder items (simple)') then
    -- FIXME: there is temporary (usually single-frame) ID Conflict during reordering as a same item may be submitting twice.
    -- This code was always slightly faulty but in a way which was not easily noticeable.
    -- Until we fix this, enable ImGuiItemFlags_AllowDuplicateId to disable detecting the issue.
    ImGui.PushItemFlag(ctx, ImGui.ItemFlags_AllowDuplicateId, true)

    -- Simple reordering
    demo.HelpMarker(
      "We don't use the drag and drop api at all here! \z
        Instead we query when the item is held but not hovered, and order items accordingly.")
    for n,item in ipairs(widgets.dragdrop.items) do
      ImGui.Selectable(ctx, item)

      if ImGui.IsItemActive(ctx) and not ImGui.IsItemHovered(ctx) then
        local mouse_delta = select(2, ImGui.GetMouseDragDelta(ctx, nil, nil, ImGui.MouseButton_Left))
        local n_next = n + (mouse_delta < 0 and -1 or 1)
        if n_next >= 1 and n_next <= #widgets.dragdrop.items then
          widgets.dragdrop.items[n] = widgets.dragdrop.items[n_next]
          widgets.dragdrop.items[n_next] = item
          ImGui.ResetMouseDragDelta(ctx, ImGui.MouseButton_Left)
        end
      end
    end

    ImGui.PopItemFlag(ctx)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Tooltip at target location') then
    for n = 0, 1 do
      -- Drop targets
      ImGui.Button(ctx, 'drop here##' .. n)
      if ImGui.BeginDragDropTarget(ctx) then
        local drop_target_flags = ImGui.DragDropFlags_AcceptBeforeDelivery | ImGui.DragDropFlags_AcceptNoPreviewTooltip
        local ok, rgba = ImGui.AcceptDragDropPayloadRGBA(ctx, nil, drop_target_flags)
        if ok then
          ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_NotAllowed)
          ImGui.SetTooltip(ctx, 'Cannot drop here!')
        end
        ImGui.EndDragDropTarget(ctx)
      end

      -- Drop source
      if n == 0 then
        ImGui.ColorButton(ctx, 'drag me', 0xFF0033FF)
      end
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Drag and drop files') then
    if ImGui.BeginChild(ctx, '##drop_files', -FLT_MIN, 100, ImGui.ChildFlags_FrameStyle) then
      if #widgets.dragdrop.files == 0 then
        ImGui.Text(ctx, 'Drag and drop files here...')
      else
        ImGui.Text(ctx, ('Received %d file(s):'):format(#widgets.dragdrop.files))
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, 'Clear') then
          widgets.dragdrop.files = {}
        end
      end
      for _, file in ipairs(widgets.dragdrop.files) do
        ImGui.Bullet(ctx)
        ImGui.TextWrapped(ctx, file)
      end
      ImGui.EndChild(ctx)
    end

    if ImGui.BeginDragDropTarget(ctx) then
      local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
      if rv then
        widgets.dragdrop.files = {}
        for i = 0, count - 1 do
          local filename
          rv,filename = ImGui.GetDragDropPayloadFile(ctx, i)
          table.insert(widgets.dragdrop.files, filename)
        end
      end
      ImGui.EndDragDropTarget(ctx)
    end

    ImGui.TreePop(ctx)
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsDragsAndSliders()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsDragsAndSliders()
  local rv
  if not ImGui.TreeNode(ctx, 'Drag/Slider Flags') then return end

  if not widgets.sliders then
    widgets.sliders = {
      flags    = ImGui.SliderFlags_None,
      drag_d   = 0.5,
      drag_i   = 50,
      slider_d = 0.5,
      slider_i = 50,
    }
  end

  -- Demonstrate using advanced flags for DragXXX and SliderXXX functions. Note that the flags are the same!
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_AlwaysClamp', widgets.sliders.flags, ImGui.SliderFlags_AlwaysClamp)
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_ClampOnInput', widgets.sliders.flags, ImGui.SliderFlags_ClampOnInput)
  ImGui.SameLine(ctx); demo.HelpMarker('Clamp value to min/max bounds when input manually with Ctrl+Click. By default Ctrl+Click allows going out of bounds.')
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_ClampZeroRange', widgets.sliders.flags, ImGui.SliderFlags_ClampZeroRange)
  ImGui.SameLine(ctx); demo.HelpMarker("Clamp even if min==max==0. Otherwise DragXXX functions don't clamp.")
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_Logarithmic', widgets.sliders.flags, ImGui.SliderFlags_Logarithmic)
  ImGui.SameLine(ctx); demo.HelpMarker('Enable logarithmic editing (more precision for small values).')
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_NoRoundToFormat', widgets.sliders.flags, ImGui.SliderFlags_NoRoundToFormat)
  ImGui.SameLine(ctx); demo.HelpMarker('Disable rounding underlying value to match precision of the format string (e.g. %.3f values are rounded to those 3 digits).')
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_NoInput', widgets.sliders.flags, ImGui.SliderFlags_NoInput)
  ImGui.SameLine(ctx); demo.HelpMarker('Disable Ctrl+Click or Enter key allowing to input text directly into the widget.')
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_NoSpeedTweaks', widgets.sliders.flags, ImGui.SliderFlags_NoSpeedTweaks)
  ImGui.SameLine(ctx); demo.HelpMarker('Disable keyboard modifiers altering tweak speed. Useful if you want to alter tweak speed yourself based on your own logic.')
  rv,widgets.sliders.flags = ImGui.CheckboxFlags(ctx, 'SliderFlags_WrapAround', widgets.sliders.flags, ImGui.SliderFlags_WrapAround)
  ImGui.SameLine(ctx); demo.HelpMarker('Enable wrapping around from max to min and from min to max (only supported by DragXXX() functions)')

  -- Drags
  ImGui.Text(ctx, ('Underlying double value: %f'):format(widgets.sliders.drag_d))
  rv,widgets.sliders.drag_d = ImGui.DragDouble(ctx, 'DragDouble (0 -> 1)', widgets.sliders.drag_d, 0.005, 0.0, 1.0, '%.3f', widgets.sliders.flags)
  rv,widgets.sliders.drag_d = ImGui.DragDouble(ctx, 'DragDouble (0 -> +inf)', widgets.sliders.drag_d, 0.005, 0.0, DBL_MAX, '%.3f', widgets.sliders.flags)
  rv,widgets.sliders.drag_d = ImGui.DragDouble(ctx, 'DragDouble (-inf -> 1)', widgets.sliders.drag_d, 0.005, -DBL_MAX, 1.0, '%.3f', widgets.sliders.flags)
  rv,widgets.sliders.drag_d = ImGui.DragDouble(ctx, 'DragDouble (-inf -> +inf)', widgets.sliders.drag_d, 0.005, -DBL_MAX, DBL_MAX, '%.3f', widgets.sliders.flags)
  -- rv,widgets.sliders.drag_d = ImGui.DragDouble(ctx, 'DragDouble (0 -> 0)', widgets.sliders.drag_d, 0.005, 0, 0, '%.3f', widgets.sliders.flags) -- To test ClampZeroRange
  -- rv,widgets.sliders.drag_d = ImGui.DragDouble(ctx, 'DragDouble (100 -> 100)', widgets.sliders.drag_d, 0.005, 100, 100, '%.3f', widgets.sliders.flags)
  rv,widgets.sliders.drag_i = ImGui.DragInt(ctx, 'DragInt (0 -> 100)', widgets.sliders.drag_i, 0.5, 0, 100, '%d', widgets.sliders.flags)

  -- Sliders
  local flags_for_sliders = widgets.sliders.flags & ~ImGui.SliderFlags_WrapAround
  ImGui.Text(ctx, ('Underlying float value: %f'):format(widgets.sliders.slider_d))
  rv,widgets.sliders.slider_d = ImGui.SliderDouble(ctx, 'SliderDouble (0 -> 1)', widgets.sliders.slider_d, 0.0, 1.0, '%.3f', flags_for_sliders)
  rv,widgets.sliders.slider_i = ImGui.SliderInt(ctx, 'SliderInt (0 -> 100)', widgets.sliders.slider_i, 0, 100, '%d', flags_for_sliders)

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsFonts()
-------------------------------------------------------------------------------

-- local function DemoWindowWidgetsFonts()
--   if not ImGui.TreeNode(ctx, 'Fonts') then return end
--   ImFontAtlas* atlas = ImGui::GetIO().Fonts;
--   ImGui.ShowFontAtlas(ctx, atlas)
--   -- FIXME-NEWATLAS: Provide a demo to add/create a procedural font?
--   ImGui.TreePop(ctx)
-- end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsImages()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsImages()
  local rv
  if not ImGui.TreeNode(ctx, 'Images') then return end

  if not widgets.images then
    widgets.images = {
      pressed_count = 0,
    }
  end
  if not ImGui.ValidatePtr(widgets.images.bitmap, 'ImGui_Image*') then
    -- see "Dump file to string literal" in ReaPack
    widgets.images.bitmap = ImGui.CreateImageFromMem(
      "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\z
       \x00\x00\x01\x9D\x00\x00\x00\x45\x08\x00\x00\x00\x00\xB4\xAE\x64\z
       \x88\x00\x00\x06\x2D\x49\x44\x41\x54\x78\xDA\xED\x9D\xBF\x6E\xE3\z
       \x36\x1C\xC7\xBF\xC3\x01\x77\xC3\x19\x47\x2F\x09\x70\x68\x21\x08\z
       \x87\x03\x32\x14\x08\x24\x20\x1E\x3A\xA4\x03\x81\x2B\xD0\xB1\x30\z
       \xF4\x06\xEA\x18\x64\xE2\xD4\xB1\x83\xF3\x00\x1D\xB8\x76\xF4\xD0\z
       \x17\xE0\x2B\xE8\x15\xF4\x0A\x7A\x85\x5F\x07\x4A\xB2\x9D\x88\xB4\z
       \xA4\x23\x6D\xDA\xE5\x6F\x49\x22\x3A\x24\xCD\x8F\xF9\xFB\x4B\xC9\z
       \xA0\x21\x51\x14\x25\x04\xC1\xD0\xC5\x12\xDB\xB8\x32\xA1\xD2\x29\z
       \x01\xD6\xC4\xA5\x09\x93\x8E\x00\x80\x32\x2E\x4D\x90\x74\x14\x00\z
       \x00\x75\x5C\x9B\x10\xE9\xA4\x9A\x4E\xDC\x3C\x21\xD2\xD9\x02\x00\z
       \x44\x89\x68\x79\x02\xA4\xB3\x06\xC0\x14\x29\x48\x07\xBD\xF3\xFF\z
       \xDD\x7A\x4A\xE9\x95\x0E\x00\x56\x11\x11\xB8\x8F\xDE\xAF\x5E\x84\z
       \xF0\x49\xA7\x02\x74\xB0\x03\x17\xAA\x2D\xD2\x71\xBB\x7E\x0A\xED\z
       \xA6\x01\x54\xA4\x13\x1A\x1D\xD1\x51\x01\x44\xA4\x13\x1E\x9D\xB4\z
       \xB3\x3F\x65\xA4\x13\x1A\x9D\x6D\xBB\x65\x6A\xB8\x70\x0B\x22\x1D\z
       \xD7\x76\x47\x74\x61\x4F\xA4\x13\x20\x1D\x6D\x76\x4A\x60\x1D\xE9\z
       \x9C\x9D\x4E\xC5\x0F\x24\x43\xC6\x39\xE7\x8F\xEF\x80\x84\x7F\xB7\z
       \x80\xFB\x96\xC7\xEC\xF1\xF0\xEF\x2F\x4B\xE0\x43\xC2\x4F\x20\xD9\z
       \xCF\x03\x17\x13\x17\x43\x3F\x3C\x70\x9E\x65\x59\xF6\xD7\xEB\x4F\z
       \x77\xAD\x35\x9B\xC0\x85\x78\xD4\xEA\x70\x9A\x1B\x76\xBA\x2C\xE1\z
       \xA0\x53\xEB\x64\xEF\x70\x4E\x04\x00\x02\x83\x63\x36\x0C\x60\x74\z
       \x71\x74\x9A\x35\x3A\x69\xAE\x93\x4E\xBE\x26\x9D\x6C\x2B\x2F\x8F\z
       \x0E\xEF\xE1\xA0\xBA\x4E\x3A\x65\xDA\xE6\xA9\xEB\x8B\xA3\x23\x77\z
       \x70\x18\x5D\x27\x1D\x89\xBA\x66\x70\x92\x29\x70\x4C\xA7\xD9\x70\z
       \x20\x15\x66\x3A\xF9\x8E\x8E\x18\xDD\xC1\x65\xD1\xA9\xB1\xC9\x01\z
       \xA4\x4D\x68\x74\x86\x0D\xFE\x3E\x9D\x1D\x9C\xBC\x19\xDD\xC1\x65\z
       \xD1\x69\x6B\xA3\x6E\xCE\x4C\xB9\xA3\x63\x32\xF8\xFB\x74\xDE\xD9\z
       \xE0\xB8\xF7\x18\xCE\x42\x87\xC3\x95\x5E\x73\x49\xC7\x64\xF0\xF7\z
       \xE9\x24\x9D\x5A\x6B\x26\x74\x10\x36\x9D\x46\x1D\xCA\x33\x00\x64\z
       \xCA\x2A\xFF\x3E\x17\x8F\x59\xF1\xA7\x3A\x2A\x50\x8E\xE4\x79\xB7\z
       \xB6\x1F\x0F\x1A\x5E\xF0\xD2\xFF\x9E\xFD\xFE\x15\xF8\x5A\xFC\x33\z
       \xA9\x83\xF9\x82\x62\xE0\x62\x51\x38\xE8\x39\xCB\x94\x02\x80\x3F\z
       \x50\x8B\x03\xF9\x06\x00\xB7\x4F\xC2\x22\x4F\xF7\x78\xFF\xAD\x28\z
       \x8A\xD5\x6D\x21\x8E\x08\xC4\x44\x79\xFA\x25\x01\x3E\xAD\xDE\x5C\z
       \xBF\xDD\x2D\xEE\x61\x63\x81\xDD\x24\x12\xCB\x7C\x8C\x1D\x1C\x19\z
       \xD8\xF6\xE6\x86\x5E\xBD\x5A\x89\xEF\x97\x24\x11\x02\x00\x0A\xBC\z
       \x76\x81\x8E\x3A\xD3\x15\x03\xD3\x2F\x68\x72\xE9\x58\xB3\x19\x0D\z
       \xB7\xD1\xE0\xEF\x6B\x36\x6E\x31\x96\x1E\x3C\x86\x93\xDB\x9D\x8A\z
       \x1D\xA5\x53\xB3\xCE\x2A\x35\x22\x67\xB5\x4B\x3A\x66\xC3\xAD\x8C\z
       \x06\x7F\x2C\x1D\x0F\x1E\xC3\xA9\xE9\x34\x29\x00\xB6\xC5\xE6\x88\z
       \x79\xDE\xF6\xE1\x45\xE9\x92\x8E\xD9\x70\x2B\xA3\xC1\x1F\x4B\xC7\z
       \x83\xC7\x30\x99\xCE\x61\xAA\x73\x32\x1D\x0E\x00\x92\x52\x4B\xED\z
       \xA0\xEA\xDD\xED\x2D\x80\xAE\x90\x3A\x89\x8E\x29\x28\xB4\x84\xFA\z
       \x8A\xCB\x1C\xC8\x45\x6D\xCD\x15\xD8\xE8\xF0\x67\x43\x07\x23\x72\z
       \x0C\x86\x09\x4F\xA6\x83\x03\x99\x4A\x47\x68\x38\x54\x5A\xFE\x53\z
       \xF4\x1F\x30\x79\x6C\x0C\x03\x1D\xA3\x8A\xB7\x84\xFA\x8A\x8F\xC9\z
       \xE4\x58\xE9\x58\xDA\x8E\xE4\x18\x4C\x13\x3E\x2D\x9D\xAA\x9B\xC2\z
       \xD6\x12\x8B\xF2\xBE\xE3\x1A\x38\x5A\x3F\xC5\x04\x15\x5F\x59\x0C\z
       \xB7\x5F\x3A\x56\x8F\xC1\x3C\xE1\xD3\xD2\xE1\x00\x72\x22\xA2\xC6\z
       \x12\x8C\xEE\x75\x2C\x19\xF2\x6A\x2A\x1D\x8B\x6D\xB1\x18\x6E\xBF\z
       \x74\xAC\x1E\x83\x79\xC2\x27\xA5\x23\x81\xCE\x55\xCE\xF9\x18\x3A\z
       \x73\x72\x05\x36\xDB\x62\x31\xDC\x7E\xE9\xD8\x3C\x06\xCB\x84\x4F\z
       \x41\xA7\xAF\x5C\x2F\x00\x7C\xD1\x85\xD3\x05\x96\x9F\x93\x87\xE1\z
       \x5A\x34\x80\x11\xF5\xE8\xB6\x80\xFC\xE6\x95\x8B\xDD\xEC\x5E\x97\z
       \x78\xB3\xE5\xDD\x02\x58\x24\x43\xF5\xE0\x6C\x69\x2C\x1F\xEB\x4A\z
       \x3B\xE7\x9C\xF3\x65\x66\x9E\x90\xB5\xED\x47\xE3\xC0\xB6\x09\x1F\z
       \x5E\x78\xBC\xBB\x59\x00\xF8\xF8\x83\x83\xCA\xF5\x72\xA9\x17\xFA\z
       \x57\xEC\xAB\x7D\x4E\x44\x54\x75\x7B\x39\x55\xB3\xF7\x4E\x67\x48\z
       \x31\x41\xC5\x2B\x8B\x0D\xF3\xBB\x77\x66\xDA\xA4\x83\xBD\x23\x18\z
       \x00\x51\xD3\xFD\xBD\x97\x78\xA7\x3B\x49\x50\x31\xAB\x07\xC3\x47\z
       \xD0\xB1\x04\x77\x98\x63\x5B\xCE\x49\xC7\x62\x93\xF6\x96\xA7\xC9\z
       \x01\xF0\x9A\x88\x9E\xEF\xBC\xD0\xE1\xDA\x25\xA8\xD9\xBE\x6E\x2C\z
       \x2D\x1E\x35\x11\x11\x95\x6A\x5A\x70\x87\x39\xB6\xE5\x9C\x74\x2C\z
       \x36\x69\x8F\xCE\x1A\x60\x3A\x44\x17\x6B\x2F\x74\x72\x40\xEA\x71\z
       \x90\x0B\xCE\x64\xC9\xD0\x67\x05\x06\xA3\x51\x22\xA2\x86\x4D\x33\z
       \xA4\x04\x69\x0C\x0A\xC3\xA4\x63\x89\x62\x77\x74\x14\xB0\x6E\xDA\z
       \x0F\xEF\xC6\x0B\x1D\x9D\x5E\xAB\x01\x26\x89\x04\x1A\xAD\x9F\x52\z
       \x4B\x26\x87\x88\x36\x7C\x62\x70\x87\x39\x04\xCE\x4A\x47\x8D\xC8\z
       \xE4\x94\xED\xAD\x68\x55\xEE\xE6\x66\xF5\x21\x3A\xA9\x4E\xCF\x6C\z
       \xFA\xF7\x5C\xEA\xD4\x81\x29\x0B\x4A\x54\xA5\xF5\xC4\xE0\xEE\x3A\z
       \xE9\xA4\xB2\xD7\xFA\x4E\xCA\x96\x43\x76\x87\x53\x7F\x0B\x42\x1B\z
       \x8F\xF2\xA1\xE3\xBA\xBB\x0A\x42\x95\x0E\x06\xA3\xCC\x12\xDC\x5D\z
       \x27\x1D\x10\x11\xA9\xDC\xD9\x99\x85\xB7\x74\xD6\x2D\x1D\xBD\x0E\z
       \x3A\x11\x5A\x0F\xA6\x39\x9B\x12\x4C\x2A\xB5\x2D\x79\x65\x4E\xC5\z
       \x19\x82\xBB\xEB\xA4\x93\x6F\xA8\x2A\x01\xA4\x8E\x6E\x1A\x7D\x1B\z
       \x8D\x26\x58\x72\xCE\x33\xE8\xB8\xEF\xE6\x43\x17\x8B\x0D\xC6\x9A\z
       \x77\xC9\xCD\xD2\x10\xAE\x72\xCE\xCD\x51\xA5\xED\x60\xB5\x39\xE2\z
       \xF4\x1E\x8D\xCE\x6B\xDB\x45\xA3\x0F\x4B\x00\xCB\xCF\x3F\xB9\x3A\z
       \xA1\x3D\x14\x8D\xE6\x44\x44\x4C\x9B\x35\x81\xF6\x87\xE3\xF3\x82\z
       \xD7\xB9\x77\x5C\xCB\x40\x9E\x2D\x47\x4D\x44\x42\x8F\xD9\xBE\x69\z
       \xA1\x91\x45\x3A\x67\xA7\x23\xF5\x68\x39\x24\x11\xD5\xDA\x59\x2B\z
       \x5D\x1F\xE6\x8F\x74\x66\xD2\xA1\x1C\x15\x11\x35\x1C\x65\x3F\x74\z
       \x0A\x15\xE9\x84\x41\xA7\x6A\x5D\xE0\x8D\x68\x5F\x40\x12\xAE\x1F\z
       \xD6\x11\xE9\xCC\xA5\x43\x72\x2F\x42\x59\xE7\x44\x0D\x63\x55\xA4\z
       \x13\x0A\x1D\x92\x5D\x2E\x8F\x48\x80\xEA\x1C\x92\x22\x9D\x60\xE8\z
       \x90\x4A\xC1\x65\xDD\xFA\x08\x8C\xB9\x7F\x3C\x68\xA4\x33\x8D\xCE\z
       \xE1\x49\xDD\xA7\xD5\x27\x00\xC9\x2D\x80\xF7\xAB\x27\xE1\x5C\x2C\z
       \x47\x77\x8B\x64\x4E\xDB\xD8\x93\xBA\x1E\xDA\xB0\x12\x9E\x64\x77\z
       \x52\xF7\xF5\x29\x77\xF5\x77\x51\x64\x45\xF1\xDB\xDE\xE9\x71\x87\z
       \x62\x39\xF6\xFE\x92\xCD\x6B\x1B\x79\x70\xFC\xC5\x7D\x9B\x77\xA9\z
       \x4D\xAA\xA6\x71\x6F\x73\xBC\x68\xB6\xD1\xCA\xC2\x83\xD6\xF3\x2F\z
       \x38\xAD\x56\x8D\x74\xE6\x2F\x57\xB3\x11\x9B\x26\xD2\x09\x93\x8E\z
       \x62\xDD\x83\x0D\x23\x9D\xE0\xE8\x34\xBA\x6C\xC6\x03\xA4\xE3\x57\z
       \x2E\x82\xCE\x06\x7B\x4F\xA2\xAE\x83\xF2\x0A\x22\x9D\xBE\xA6\xD9\z
       \xDE\xFF\xA1\x22\x9D\x00\xF7\x8E\x3E\xE5\x54\x32\x8A\x74\x42\xA2\z
       \xD3\xDE\xA2\x21\xB5\x0D\x2A\x4F\x4D\x87\xE4\xB9\xD6\x40\xD2\x05\z
       \xD0\x21\x8E\x94\xAF\xF5\x6C\xD6\x9E\xBE\x07\xE1\xE2\x1E\xA7\x17\z
       \x0E\x9D\xAA\xAF\x18\x94\xBE\x32\x7C\x91\xCE\xFC\xE5\x92\x0C\xA2\z
       \x22\xDA\x72\x6F\x4F\x9F\xBB\xB8\x47\xEF\x0B\x0A\x86\x4E\x77\x77\z
       \x48\x1A\xBF\xBA\x2A\x0C\x79\xF3\xE4\x49\x29\x44\xFC\xD6\xB7\x50\z
       \xE4\x3F\xB8\xA9\x68\x06\x1B\x45\x77\x96\x00\x00\x00\x00\x49\x45\z
       \x4E\x44\xAE\x42\x60\x82")
  end

  ImGui.TextWrapped(ctx, 'Hover the texture for a zoomed view!')

  -- Consider using the lower-level Draw List API, via ImGui.DrawList_AddImage(ImGui.GetWindowDrawList()).
  local my_tex_w, my_tex_h = ImGui.Image_GetSize(widgets.images.bitmap)
  do
    rv,widgets.images.use_text_color_for_tint =
      ImGui.Checkbox(ctx, 'Use Text Color for Tint', widgets.images.use_text_color_for_tint)
    ImGui.Text(ctx, ('%.0fx%.0f'):format(my_tex_w, my_tex_h))
    local pos_x, pos_y = ImGui.GetCursorScreenPos(ctx)
    local uv_min_x, uv_min_y = 0.0, 0.0 -- Top-left
    local uv_max_x, uv_max_y = 1.0, 1.0 -- Lower-right
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ImageBorderSize, math.max(1.0, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ImageBorderSize)))
    ImGui.ImageWithBg(ctx, widgets.images.bitmap, my_tex_w, my_tex_h,
      uv_min_x, uv_min_y, uv_max_x, uv_max_y, 0x000000FF)
    if ImGui.BeginItemTooltip(ctx) then
      local region_sz = 32.0
      local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
      local region_x = mouse_x - pos_x - region_sz * 0.5
      local region_y = mouse_y - pos_y - region_sz * 0.5
      local zoom = 4.0
      if region_x < 0.0 then region_x = 0.0
      elseif region_x > my_tex_w - region_sz then region_x = my_tex_w - region_sz end
      if region_y < 0.0 then region_y = 0.0
      elseif region_y > my_tex_h - region_sz then region_y = my_tex_h - region_sz end
      ImGui.Text(ctx, ('Min: (%.2f, %.2f)'):format(region_x, region_y))
      ImGui.Text(ctx, ('Max: (%.2f, %.2f)'):format(region_x + region_sz, region_y + region_sz))
      local uv0_x, uv0_y = region_x / my_tex_w, region_y / my_tex_h
      local uv1_x, uv1_y = (region_x + region_sz) / my_tex_w, (region_y + region_sz) / my_tex_h
      ImGui.ImageWithBg(ctx, widgets.images.bitmap, region_sz * zoom, region_sz * zoom,
        uv0_x, uv0_y, uv1_x, uv1_y, 0x000000FF)
      ImGui.EndTooltip(ctx)
    end
    ImGui.PopStyleVar(ctx)
  end
  ImGui.TextWrapped(ctx, 'And now some textured buttons...')
  -- static int pressed_count = 0;
  for i = 0, 8 do
    -- UV coordinates are (0.0, 0.0) and (1.0, 1.0) to display an entire textures.
    -- Here we are trying to display only a 32x32 pixels area of the texture, hence the UV computation.
    -- Read about UV coordinates here: https://github.com/ocornut/imgui/wiki/Image-Loading-and-Displaying-Examples
    if i > 0 then
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, i - 1, i - 1)
    end
    local size_w, size_h = 32.0, 32.0                     -- Size of the image we want to make visible
    local uv0_x, uv0_y = 0.0, 0.0                         -- UV coordinates for lower-left
    local uv1_x, uv1_y = 32.0 / my_tex_w, 32.0 / my_tex_h -- UV coordinates for (32,32) in our texture
    local bg_col = 0x000000FF   -- Black background
    local tint_col = 0xFFFFFFFF -- No tint
    if ImGui.ImageButton(ctx, i, widgets.images.bitmap, size_w, size_h, uv0_x, uv0_y, uv1_x, uv1_y, bg_col, tint_col) then
      widgets.images.pressed_count = widgets.images.pressed_count + 1
    end
    if i > 0 then
      ImGui.PopStyleVar(ctx)
    end
    ImGui.SameLine(ctx)
  end
  ImGui.NewLine(ctx)
  ImGui.Text(ctx, ('Pressed %d times.'):format(widgets.images.pressed_count))
  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsListBoxes()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsListBoxes()
  local rv
  if not ImGui.TreeNode(ctx, 'List boxes') then return end

  if not widgets.lists then
    widgets.lists = {selected_idx = 1, item_highlight = false}
  end

  -- BeginListBox() is essentially a thin wrapper to using BeginChild()/EndChild()
  -- using the ChildFlags_FrameStyle flag for stylistic changes + displaying a label.

  -- Using the generic BeginListBox() API, you have full control over how to display the combo contents.
  -- (your selection data could be an index, a pointer to the object, an id for the object, a flag intrusively
  -- stored in the object itself, etc.)
  local items = {'AAAA', 'BBBB', 'CCCC', 'DDDD', 'EEEE', 'FFFF', 'GGGG', 'HHHH', 'IIII', 'JJJJ', 'KKKK', 'LLLLLLL', 'MMMM', 'OOOOOOO'}

  local item_highlighted_idx = -1
  rv, widgets.lists.item_highlight = ImGui.Checkbox(ctx, 'Highlight hovered item in second listbox', widgets.lists.item_highlight)

  if ImGui.BeginListBox(ctx, 'listbox 1') then
    for n,v in ipairs(items) do
      local is_selected = widgets.lists.selected_idx == n
      if ImGui.Selectable(ctx, v, is_selected) then
        widgets.lists.selected_idx = n
      end

      if widgets.lists.item_highlight and ImGui.IsItemHovered(ctx) then
        widgets.lists.item_highlighted_idx = n
      end

      -- Set the initial focus when opening the combo (scrolling + keyboard navigation focus)
      if is_selected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndListBox(ctx)
  end
  ImGui.SameLine(ctx); demo.HelpMarker('Here we are sharing selection state between both boxes.')

  -- Custom size: use all width, 5 items tall
  ImGui.Text(ctx, 'Full-width:')
  if ImGui.BeginListBox(ctx, '##listbox 2', -FLT_MIN, 5 * ImGui.GetTextLineHeightWithSpacing(ctx)) then
    for n,v in ipairs(items) do
      local is_selected = widgets.lists.selected_idx == n
      local flags = widgets.lists.item_highlighted_idx == n and ImGui.SelectableFlags_Highlight or 0
      if ImGui.Selectable(ctx, v, is_selected, flags) then
        widgets.lists.current_idx = n
      end

      -- Set the initial focus when opening the combo (scrolling + keyboard navigation focus)
      if is_selected then
        ImGui.SetItemDefaultFocus(ctx)
      end
    end
    ImGui.EndListBox(ctx)
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsMultiComponents()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsMultiComponents()
  local rv
  if not ImGui.TreeNode(ctx, 'Multi-component Widgets') then return end

  if not widgets.multi_component then
    widgets.multi_component = {
      vec4d = {0.10, 0.20, 0.30, 0.44},
      vec4i = {1, 5, 100, 255},
      vec5a = reaper.new_array({0.10, 0.20, 0.30, 0.44, 0.55}),
      range = {
        begin_f = 10.0,
        end_f   = 90.0,
        begin_i = 100,
        end_i   = 1000,
      }
    }
  end

  local vec4d = widgets.multi_component.vec4d
  local vec4i = widgets.multi_component.vec4i

  ImGui.SeparatorText(ctx, '2-wide')
  rv,vec4d[1],vec4d[2] = ImGui.InputDouble2(ctx, 'input double2', vec4d[1], vec4d[2])
  rv,vec4d[1],vec4d[2] = ImGui.DragDouble2(ctx, 'drag double2', vec4d[1], vec4d[2], 0.01, 0.0, 1.0)
  rv,vec4d[1],vec4d[2] = ImGui.SliderDouble2(ctx, 'slider double2', vec4d[1], vec4d[2], 0.0, 1.0)
  rv,vec4i[1],vec4i[2] = ImGui.InputInt2(ctx, 'input int2', vec4i[1], vec4i[2])
  rv,vec4i[1],vec4i[2] = ImGui.DragInt2(ctx, 'drag int2', vec4i[1], vec4i[2], 1, 0, 255)
  rv,vec4i[1],vec4i[2] = ImGui.SliderInt2(ctx, 'slider int2', vec4i[1], vec4i[2], 0, 255)

  ImGui.SeparatorText(ctx, '3-wide')
  rv,vec4d[1],vec4d[2],vec4d[3] = ImGui.InputDouble3(ctx, 'input double3', vec4d[1], vec4d[2], vec4d[3])
  rv,vec4d[1],vec4d[2],vec4d[3] = ImGui.DragDouble3(ctx, 'drag double3', vec4d[1], vec4d[2], vec4d[3], 0.01, 0.0, 1.0)
  rv,vec4d[1],vec4d[2],vec4d[3] = ImGui.SliderDouble3(ctx, 'slider double3', vec4d[1], vec4d[2], vec4d[3], 0.0, 1.0)
  rv,vec4i[1],vec4i[2],vec4i[3] = ImGui.InputInt3(ctx, 'input int3', vec4i[1], vec4i[2], vec4i[3])
  rv,vec4i[1],vec4i[2],vec4i[3] = ImGui.DragInt3(ctx, 'drag int3', vec4i[1], vec4i[2], vec4i[3], 1, 0, 255)
  rv,vec4i[1],vec4i[2],vec4i[3] = ImGui.SliderInt3(ctx, 'slider int3', vec4i[1], vec4i[2], vec4i[3], 0, 255)

  ImGui.SeparatorText(ctx, '4-wide')
  rv,vec4d[1],vec4d[2],vec4d[3],vec4d[4] = ImGui.InputDouble4(ctx, 'input double4', vec4d[1], vec4d[2], vec4d[3], vec4d[4])
  rv,vec4d[1],vec4d[2],vec4d[3],vec4d[4] = ImGui.DragDouble4(ctx, 'drag double4', vec4d[1], vec4d[2], vec4d[3], vec4d[4], 0.01, 0.0, 1.0)
  rv,vec4d[1],vec4d[2],vec4d[3],vec4d[4] = ImGui.SliderDouble4(ctx, 'slider double4', vec4d[1], vec4d[2], vec4d[3], vec4d[4], 0.0, 1.0)
  rv,vec4i[1],vec4i[2],vec4i[3],vec4i[4] = ImGui.InputInt4(ctx, 'input int4', vec4i[1], vec4i[2], vec4i[3], vec4i[4])
  rv,vec4i[1],vec4i[2],vec4i[3],vec4i[4] = ImGui.DragInt4(ctx, 'drag int4', vec4i[1], vec4i[2], vec4i[3], vec4i[4], 1, 0, 255)
  rv,vec4i[1],vec4i[2],vec4i[3],vec4i[4] = ImGui.SliderInt4(ctx, 'slider int4', vec4i[1], vec4i[2], vec4i[3], vec4i[4], 0, 255)
  ImGui.Spacing(ctx)

  ImGui.SeparatorText(ctx, 'N-wide')
  ImGui.InputDoubleN(ctx, 'input reaper.array', widgets.multi_component.vec5a)
  ImGui.DragDoubleN(ctx, 'drag reaper.array', widgets.multi_component.vec5a, 0.01, 0.0, 1.0)
  ImGui.SliderDoubleN(ctx, 'slider reaper.array', widgets.multi_component.vec5a, 0.0, 1.0)

  ImGui.SeparatorText(ctx, 'Ranges')
  local range = widgets.multi_component.range
  rv,range.begin_f,range.end_f = ImGui.DragFloatRange2(ctx, 'range float', range.begin_f, range.end_f, 0.25, 0.0, 100.0, 'Min: %.1f %%', 'Max: %.1f %%', ImGui.SliderFlags_AlwaysClamp)
  rv,range.begin_i,range.end_i = ImGui.DragIntRange2(ctx, 'range int', range.begin_i, range.end_i, 5, 0, 1000, 'Min: %d units', 'Max: %d units')
  rv,range.begin_i,range.end_i = ImGui.DragIntRange2(ctx, 'range int (no bounds)', range.begin_i, range.end_i, 5, 0, 0, 'Min: %d units', 'Max: %d units')

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsPlotting()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsPlotting()
  local rv
  if not ImGui.TreeNode(ctx, 'Plotting') then return end

  local PLOT1_SIZE = 90
  local plot2_funcs   = {
    function(i) return math.sin(i * 0.1) end, -- sin
    function(i) return (i & 1) == 1 and 1.0 or -1.0 end, --saw
  }

  if not widgets.plots then
    widgets.plots = {
      animate = true,
      frame_times = reaper.new_array({0.6, 0.1, 1.0, 0.5, 0.92, 0.1, 0.2}),
      plot1 = {
        offset       = 1,
        refresh_time = 0.0,
        phase        = 0.0,
        data         = reaper.new_array(PLOT1_SIZE),
      },
      plot2 = {
        func = 0,
        size = 70,
        fill = true,
        data = reaper.new_array(1),
      },
    }
    widgets.plots.plot1.data.clear()
  end

  rv,widgets.plots.animate = ImGui.Checkbox(ctx, 'Animate', widgets.plots.animate)

  -- Plot as lines and plot as histogram
  ImGui.PlotLines(ctx, 'Frame Times', widgets.plots.frame_times)
  ImGui.PlotHistogram(ctx, 'Histogram', widgets.plots.frame_times, 0, nil, 0.0, 1.0, 0, 80.0)
  -- ImGui.SameLine(ctx); demo.HelpMarker('Consider using ImPlot instead!')

  -- Fill an array of contiguous float values to plot
  if not widgets.plots.animate or widgets.plots.plot1.refresh_time == 0.0 then
    widgets.plots.plot1.refresh_time = ImGui.GetTime(ctx)
  end
  while widgets.plots.plot1.refresh_time < ImGui.GetTime(ctx) do -- Create data at fixed 60 Hz rate for the demo
    widgets.plots.plot1.data[widgets.plots.plot1.offset] = math.cos(widgets.plots.plot1.phase)
    widgets.plots.plot1.offset = (widgets.plots.plot1.offset % PLOT1_SIZE) + 1
    widgets.plots.plot1.phase = widgets.plots.plot1.phase + (0.10 * widgets.plots.plot1.offset)
    widgets.plots.plot1.refresh_time = widgets.plots.plot1.refresh_time + (1.0 / 60.0)
  end

  -- Plots can display overlay texts
  -- (in this example, we will display an average value)
  do
    local average = 0.0
    for n = 1, PLOT1_SIZE do
      average = average + widgets.plots.plot1.data[n]
    end
    average = average / PLOT1_SIZE

    local overlay = ('avg %f'):format(average)
    ImGui.PlotLines(ctx, 'Lines', widgets.plots.plot1.data, widgets.plots.plot1.offset - 1, overlay, -1.0, 1.0, 0, 80.0)
  end

  ImGui.SeparatorText(ctx, 'Functions')
  ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
  rv,widgets.plots.plot2.func = ImGui.Combo(ctx, 'func', widgets.plots.plot2.func, 'Sin\0Saw\0')
  local funcChanged = rv
  ImGui.SameLine(ctx)
  rv,widgets.plots.plot2.size = ImGui.SliderInt(ctx, 'Sample count', widgets.plots.plot2.size, 1, 400)

  -- Use functions to generate output
  if funcChanged or rv or widgets.plots.plot2.fill then
    widgets.plots.plot2.fill = false -- fill the first time
    widgets.plots.plot2.data = reaper.new_array(widgets.plots.plot2.size)
    for n = 1, widgets.plots.plot2.size do
      widgets.plots.plot2.data[n] = plot2_funcs[widgets.plots.plot2.func + 1](n - 1)
    end
  end

  ImGui.PlotLines(ctx, 'Lines##2', widgets.plots.plot2.data, 0, nil, -1.0, 1.0, 0, 80)
  ImGui.PlotHistogram(ctx, 'Histogram##2', widgets.plots.plot2.data, 0, nil, -1.0, 1.0, 0, 80)

  -- ImGui.Text(ctx, 'Need better plotting and graphing? Consider using ImPlot:')
  -- ImGui.TextLinkOpenURL(ctx, 'https://github.com/epezent/implot')
  -- ImGui.Separator(ctx)

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsProgressBars()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsProgressBars()
  if not ImGui.TreeNode(ctx, 'Progress Bars') then return end

  if not widgets.progress_bars then
    widgets.progress_bars = {
      progress     = 0.0,
      progress_dir = 1,
    }
  end

  -- Animate a simple progress bar
  widgets.progress_bars.progress = widgets.progress_bars.progress +
    (widgets.progress_bars.progress_dir * 0.4 * ImGui.GetDeltaTime(ctx))
  if widgets.progress_bars.progress >= 1.1 then
    widgets.progress_bars.progress = 1.1
    widgets.progress_bars.progress_dir = widgets.progress_bars.progress_dir * -1
  elseif widgets.progress_bars.progress <= -0.1 then
    widgets.progress_bars.progress = -0.1
    widgets.progress_bars.progress_dir = widgets.progress_bars.progress_dir * -1
  end

  -- Typically we would use (-1.0,0.0) or (-FLT_MIN,0.0) to use all available width,
  -- or (width,0.0) for a specified width. (0.0,0.0) uses ItemWidth.
  ImGui.ProgressBar(ctx, widgets.progress_bars.progress, 0.0, 0.0)
  ImGui.SameLine(ctx, 0.0, (ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)))
  ImGui.Text(ctx, 'Progress Bar')

  local progress_saturated = demo.clamp(widgets.progress_bars.progress, 0.0, 1.0);
  local buf = ('%d/%d'):format(math.floor(progress_saturated * 1753), 1753)
  ImGui.ProgressBar(ctx, widgets.progress_bars.progress, 0.0, 0.0, buf);

  -- Pass an animated negative value, e.g. -1.0f * (float)ImGui::GetTime() is the recommended value.
  -- Adjust the factor if you want to adjust the animation speed.
  ImGui.ProgressBar(ctx, -1.0 * ImGui.GetTime(ctx), 0.0, 0.0, 'Searching...')
  ImGui.SameLine(ctx, 0.0, (ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)))
  ImGui.Text(ctx, 'Indeterminate')

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsQueryingStatuses()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsQueryingStatuses()
  local rv

  if ImGui.TreeNode(ctx, 'Querying Item Status (Edited/Active/Hovered etc.)') then
    if not widgets.query_item then
      widgets.query_item = {
        item_type   = 1,
        b           = false,
        color       = 0xFF8000FF,
        str         = '',
        current     = 1,
        d4a         = {1.0, 0.5, 0.0, 1.0},
      }
    end

    -- Select an item type
    rv,widgets.query_item.item_type = ImGui.Combo(ctx, 'Item Type', widgets.query_item.item_type,
      'Text\0Button\0Button (w/ repeat)\0Checkbox\0SliderDouble\0\z
       InputText\0InputTextMultiline\0InputDouble\0InputDouble3\0ColorEdit4\0\z
       Selectable\0MenuItem\0TreeNode\0TreeNode (w/ double-click)\0Combo\0ListBox\0')

    ImGui.SameLine(ctx)
    demo.HelpMarker(
      'Testing how various types of items are interacting with the IsItemXXX \z
       functions. Note that the bool return value of most ImGui function is \z
       generally equivalent to calling ImGui.IsItemHovered().')

    if widgets.query_item.item_disabled then
      ImGui.BeginDisabled(ctx, true)
    end

    -- Submit selected items so we can query their status in the code following it.
    local item_type = widgets.query_item.item_type
    if item_type == 0  then -- Testing text items with no identifier/interaction
      ImGui.Text(ctx, 'ITEM: Text')
    end
    if item_type == 1  then -- Testing button
      rv = ImGui.Button(ctx, 'ITEM: Button')
    end
    if item_type == 2  then -- Testing button (with repeater)
      ImGui.PushItemFlag(ctx, ImGui.ItemFlags_ButtonRepeat, true)
      rv = ImGui.Button(ctx, 'ITEM: Button')
      ImGui.PopItemFlag(ctx)
    end
    if item_type == 3  then -- Testing checkbox
      rv,widgets.query_item.b = ImGui.Checkbox(ctx, 'ITEM: Checkbox', widgets.query_item.b)
    end
    if item_type == 4  then -- Testing basic item
      rv,widgets.query_item.d4a[1] = ImGui.SliderDouble(ctx, 'ITEM: SliderDouble', widgets.query_item.d4a[1], 0.0, 1.0)
    end
    if item_type == 5  then -- Testing input text (which handles tabbing)
      rv,widgets.query_item.str = ImGui.InputText(ctx, 'ITEM: InputText', widgets.query_item.str)
    end
    if item_type == 6  then -- Testing input text (which uses a child window)
      rv,widgets.query_item.str = ImGui.InputTextMultiline(ctx, 'ITEM: InputTextMultiline', widgets.query_item.str)
    end
    if item_type == 7  then -- Testing +/- buttons on scalar input
      rv,widgets.query_item.d4a[1] = ImGui.InputDouble(ctx, 'ITEM: InputDouble', widgets.query_item.d4a[1], 1.0)
    end
    if item_type == 8  then -- Testing multi-component items (IsItemXXX flags are reported merged)
      local d4a = widgets.query_item.d4a
      rv,d4a[1],d4a[2],d4a[3] = ImGui.InputDouble3(ctx, 'ITEM: InputDouble3', d4a[1], d4a[2], d4a[3])
    end
    if item_type == 9  then -- Testing multi-component items (IsItemXXX flags are reported merged)
      rv,widgets.query_item.color = ImGui.ColorEdit4(ctx, 'ITEM: ColorEdit', widgets.query_item.color)
    end
    if item_type == 10 then -- Testing selectable item
      rv = ImGui.Selectable(ctx, 'ITEM: Selectable')
    end
    if item_type == 11  then -- Testing menu item (they use ButtonFlags_PressedOnRelease button policy)
      rv = ImGui.MenuItem(ctx, 'ITEM: MenuItem')
    end
    if item_type == 12 then -- Testing tree node
      rv = ImGui.TreeNode(ctx, 'ITEM: TreeNode')
      if rv then ImGui.TreePop(ctx) end
    end
    if item_type == 13 then -- Testing tree node with ButtonFlags_PressedOnDoubleClick button policy.
      rv = ImGui.TreeNode(ctx, 'ITEM: TreeNode w/ TreeNodeFlags_OpenOnDoubleClick',
        ImGui.TreeNodeFlags_OpenOnDoubleClick | ImGui.TreeNodeFlags_NoTreePushOnOpen)
    end
    if item_type == 14 then
      rv,widgets.query_item.current = ImGui.Combo(ctx, 'ITEM: Combo', widgets.query_item.current, 'Apple\0Banana\0Cherry\0Kiwi\0')
    end
    if item_type == 15 then
      rv,widgets.query_item.current = ImGui.ListBox(ctx, 'ITEM: ListBox', widgets.query_item.current, 'Apple\0Banana\0Cherry\0Kiwi\0')
    end

    local hovered_delay_none = ImGui.IsItemHovered(ctx)
    local hovered_delay_stationary = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_Stationary)
    local hovered_delay_short = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort)
    local hovered_delay_normal = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal)
    local hovered_delay_tooltip = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_ForTooltip) -- = Normal + Stationary

    -- Display the values of IsItemHovered() and other common item state functions.
    -- Note that the HoveredFlags_XXX flags can be combined.
    -- Because BulletText is an item itself and that would affect the output of IsItemXXX functions,
    -- we query every state in a single call to avoid storing them and to simplify the code.
    ImGui.BulletText(ctx,
      ('Return value = %s\n\z
        IsItemFocused() = %s\n\z
        IsItemHovered() = %s\n\z
        IsItemHovered(_AllowWhenBlockedByPopup) = %s\n\z
        IsItemHovered(_AllowWhenBlockedByActiveItem) = %s\n\z
        IsItemHovered(_AllowWhenOverlappedByItem) = %s\n\z
        IsItemHovered(_AllowWhenOverlappedByWindow) = %s\n\z
        IsItemHovered(_AllowWhenDisabled) = %s\n\z
        IsItemHovered(_RectOnly) = %s\n\z
        IsItemActive() = %s\n\z
        IsItemEdited() = %s\n\z
        IsItemActivated() = %s\n\z
        IsItemDeactivated() = %s\n\z
        IsItemDeactivatedAfterEdit() = %s\n\z
        IsItemVisible() = %s\n\z
        IsItemClicked() = %s\n\z
        IsItemToggledOpen() = %s\n\z
        GetItemRectMin() = (%.1f, %.1f)\n\z
        GetItemRectMax() = (%.1f, %.1f)\n\z
        GetItemRectSize() = (%.1f, %.1f)'):format(
      rv,
      ImGui.IsItemFocused(ctx),
      ImGui.IsItemHovered(ctx),
      ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenBlockedByPopup),
      ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenBlockedByActiveItem),
      ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenOverlappedByItem),
      ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenOverlappedByWindow),
      ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled),
      ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_RectOnly),
      ImGui.IsItemActive(ctx),
      ImGui.IsItemEdited(ctx),
      ImGui.IsItemActivated(ctx),
      ImGui.IsItemDeactivated(ctx),
      ImGui.IsItemDeactivatedAfterEdit(ctx),
      ImGui.IsItemVisible(ctx),
      ImGui.IsItemClicked(ctx),
      ImGui.IsItemToggledOpen(ctx),
      ImGui.GetItemRectMin(ctx), select(2, ImGui.GetItemRectMin(ctx)),
      ImGui.GetItemRectMax(ctx), select(2, ImGui.GetItemRectMax(ctx)),
      ImGui.GetItemRectSize(ctx), select(2, ImGui.GetItemRectSize(ctx))
    ))
    ImGui.BulletText(ctx,
      ('with Hovering Delay or Stationary test:\n\z
        IsItemHovered() = %s\n\z
        IsItemHovered(_Stationary) = %s\n\z
        IsItemHovered(_DelayShort) = %s\n\z
        IsItemHovered(_DelayNormal) = %s\n\z
        IsItemHovered(_Tooltip) = %s'):format(
      hovered_delay_none, hovered_delay_stationary, hovered_delay_short, hovered_delay_normal, hovered_delay_tooltip))

    if widgets.query_item.item_disabled then
      ImGui.EndDisabled(ctx)
    end

    ImGui.InputText(ctx, 'unused', '', ImGui.InputTextFlags_ReadOnly)
    ImGui.SameLine(ctx)
    demo.HelpMarker('This widget is only here to be able to tab-out of the widgets above and see e.g. Deactivated() status.')
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Querying Window Status (Focused/Hovered etc.)') then
    if not widgets.query_window then
      widgets.query_window = {
        embed_all_inside_a_child_window = false,
        test_window = false,
      }
    end
    rv,widgets.query_window.embed_all_inside_a_child_window =
      ImGui.Checkbox(ctx, 'Embed everything inside a child window for testing _RootWindow flag.',
      widgets.query_window.embed_all_inside_a_child_window)
    local visible = true
    if widgets.query_window.embed_all_inside_a_child_window then
      visible = ImGui.BeginChild(ctx, 'outer_child', 0, ImGui.GetFontSize(ctx) * 20, ImGui.ChildFlags_Borders)
    end

    if visible then
      -- Testing IsWindowFocused() function with its various flags.
      ImGui.BulletText(ctx,
        ('IsWindowFocused() = %s\n\z
          IsWindowFocused(_ChildWindows) = %s\n\z
          IsWindowFocused(_ChildWindows|_NoPopupHierarchy) = %s\n\z
          IsWindowFocused(_ChildWindows|_DockHierarchy) = %s\n\z
          IsWindowFocused(_ChildWindows|_RootWindow) = %s\n\z
          IsWindowFocused(_ChildWindows|_RootWindow|_NoPopupHierarchy) = %s\n\z
          IsWindowFocused(_ChildWindows|_RootWindow|_DockHierarchy) = %s\n\z
          IsWindowFocused(_RootWindow) = %s\n\z
          IsWindowFocused(_RootWindow|_NoPopupHierarchy) = %s\n\z
          IsWindowFocused(_RootWindow|_DockHierarchy) = %s\n\z
          IsWindowFocused(_AnyWindow) = %s'):format(
        ImGui.IsWindowFocused(ctx),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows | ImGui.FocusedFlags_NoPopupHierarchy),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows | ImGui.FocusedFlags_DockHierarchy),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows | ImGui.FocusedFlags_RootWindow),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows | ImGui.FocusedFlags_RootWindow | ImGui.FocusedFlags_NoPopupHierarchy),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows | ImGui.FocusedFlags_RootWindow | ImGui.FocusedFlags_DockHierarchy),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootWindow),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootWindow | ImGui.FocusedFlags_NoPopupHierarchy),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootWindow | ImGui.FocusedFlags_DockHierarchy),
        ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_AnyWindow)))

      -- Testing IsWindowHovered() function with its various flags.
      ImGui.BulletText(ctx,
        ('IsWindowHovered() = %s\n\z
          IsWindowHovered(_AllowWhenBlockedByPopup) = %s\n\z
          IsWindowHovered(_AllowWhenBlockedByActiveItem) = %s\n\z
          IsWindowHovered(_ChildWindows) = %s\n\z
          IsWindowHovered(_ChildWindows|_NoPopupHierarchy) = %s\n\z
          IsWindowHovered(_ChildWindows|_DockHierarchy) = %s\n\z
          IsWindowHovered(_ChildWindows|_RootWindow) = %s\n\z
          IsWindowHovered(_ChildWindows|_RootWindow|_NoPopupHierarchy) = %s\n\z
          IsWindowHovered(_ChildWindows|_RootWindow|_DockHierarchy) = %s\n\z
          IsWindowHovered(_RootWindow) = %s\n\z
          IsWindowHovered(_RootWindow|_NoPopupHierarchy) = %s\n\z
          IsWindowHovered(_RootWindow|_DockHierarchy) = %s\n\z
          IsWindowHovered(_ChildWindows|_AllowWhenBlockedByPopup) = %s\n\z
          IsWindowHovered(_AnyWindow) = %s\n\z
          IsWindowHovered(_Stationary) = %s'):format(
        ImGui.IsWindowHovered(ctx),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AllowWhenBlockedByPopup),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AllowWhenBlockedByActiveItem),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_NoPopupHierarchy),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_DockHierarchy),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_RootWindow),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_RootWindow | ImGui.HoveredFlags_NoPopupHierarchy),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_RootWindow | ImGui.HoveredFlags_DockHierarchy),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_RootWindow),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_RootWindow | ImGui.HoveredFlags_NoPopupHierarchy),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_RootWindow | ImGui.HoveredFlags_DockHierarchy),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows | ImGui.HoveredFlags_AllowWhenBlockedByPopup),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_AnyWindow),
        ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_Stationary)))

      if ImGui.BeginChild(ctx, 'child', 0, 50, ImGui.ChildFlags_Borders) then
        ImGui.Text(ctx, 'This is another child window for testing the _ChildWindows flag.')
        ImGui.EndChild(ctx)
      end
      if widgets.query_window.embed_all_inside_a_child_window then
        ImGui.EndChild(ctx)
      end
    end

    -- Calling IsItemHovered() after begin returns the hovered status of the title bar.
    -- This is useful in particular if you want to create a context menu associated to the title bar of a window.
    -- This will also work when docked into a Tab (the Tab replace the Title Bar and guarantee the same properties).
    rv,widgets.query_window.test_window = ImGui.Checkbox(ctx, 'Hovered/Active tests after Begin() for title bar testing', widgets.query_window.test_window)
    if widgets.query_window.test_window then
      -- FIXME-DOCK: This window cannot be docked within the ImGui Demo window, this will cause a feedback loop and get them stuck.
      -- Could we fix this through an WindowClass feature? Or an API call to tag our parent as "don't skip items"?
      rv,widgets.query_window.test_window = ImGui.Begin(ctx, 'Title bar Hovered/Active tests', true)
      if rv then
        if ImGui.BeginPopupContextItem(ctx) then -- <-- This is using IsItemHovered()
          if ImGui.MenuItem(ctx, 'Close') then widgets.query_window.test_window = false end
          ImGui.EndPopup(ctx)
        end
        ImGui.Text(ctx,
          ('IsItemHovered() after begin = %s (== is title bar hovered)\n\z
            IsItemActive() after begin = %s (== is window being clicked/moved)\n')
          :format(ImGui.IsItemHovered(ctx), ImGui.IsItemActive(ctx)))
        ImGui.End(ctx)
      end
    end

    ImGui.TreePop(ctx)
  end
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsSelectables()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsSelectables()
  --ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once)
  local rv;
  if not ImGui.TreeNode(ctx, 'Selectables') then return end

  if not widgets.selectables then
    widgets.selectables = {
      basic    = {false, false, false, false},
      sameline = {false, false, false},
      columns  = {false, false, false, false, false, false, false, false, false, false},
      grid = {
        {true,  false, false, false},
        {false, true,  false, false},
        {false, false, true,  false},
        {false, false, false, true },
      },
      align = {
        {true,  false, true },
        {false, true , false},
        {true,  false, true },
      },
    }
  end

  -- Selectable() has 2 overloads:
  -- - The one taking "bool selected" as a read-only selection information.
  --   When Selectable() has been clicked it returns true and you can alter selection state accordingly.
  -- - The one taking "bool* p_selected" as a read-write selection information (convenient in some cases)
  -- The earlier is more flexible, as in real application your selection may be stored in many different ways
  -- and not necessarily inside a bool value (e.g. in flags within objects, as an external list, etc).
  if ImGui.TreeNode(ctx, 'Basic') then
    rv,widgets.selectables.basic[1] = ImGui.Selectable(ctx, '1. I am selectable', widgets.selectables.basic[1])
    rv,widgets.selectables.basic[2] = ImGui.Selectable(ctx, '2. I am selectable', widgets.selectables.basic[2])
    rv,widgets.selectables.basic[3] = ImGui.Selectable(ctx, '3. I am selectable', widgets.selectables.basic[3])
    if ImGui.Selectable(ctx, '4. I am double clickable', widgets.selectables.basic[4], ImGui.SelectableFlags_AllowDoubleClick) then
      if ImGui.IsMouseDoubleClicked(ctx, 0) then
        widgets.selectables.basic[4] = not widgets.selectables.basic[4]
      end
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Rendering more items on the same line') then
    -- (1) Using SetNextItemAllowOverlap()
    -- (2) Using the Selectable() override that takes "bool* p_selected" parameter, the bool value is toggled automatically.
    ImGui.SetNextItemAllowOverlap(ctx); rv,widgets.selectables.sameline[1] = ImGui.Selectable(ctx, 'main.c',    widgets.selectables.sameline[1])
    ImGui.SameLine(ctx); ImGui.SmallButton(ctx, 'Link 1')
    ImGui.SetNextItemAllowOverlap(ctx); rv,widgets.selectables.sameline[2] = ImGui.Selectable(ctx, 'Hello.cpp', widgets.selectables.sameline[2])
    ImGui.SameLine(ctx); ImGui.SmallButton(ctx, 'Link 2')
    ImGui.SetNextItemAllowOverlap(ctx); rv,widgets.selectables.sameline[3] = ImGui.Selectable(ctx, 'Hello.h',   widgets.selectables.sameline[3])
    ImGui.SameLine(ctx); ImGui.SmallButton(ctx, 'Link 3')
    ImGui.TreePop(ctx)
  end
  if ImGui.TreeNode(ctx, 'In Tables') then
    if ImGui.BeginTable(ctx, 'split1', 3, ImGui.TableFlags_Resizable | ImGui.TableFlags_NoSavedSettings | ImGui.TableFlags_Borders) then
      for i,sel in ipairs(widgets.selectables.columns) do
        ImGui.TableNextColumn(ctx)
        rv,widgets.selectables.columns[i] = ImGui.Selectable(ctx, ('Item %d'):format(i-1), sel)
      end
      ImGui.EndTable(ctx)
    end
    ImGui.Spacing(ctx)
    if ImGui.BeginTable(ctx, 'split2', 3, ImGui.TableFlags_Resizable | ImGui.TableFlags_NoSavedSettings | ImGui.TableFlags_Borders) then
      for i,sel in ipairs(widgets.selectables.columns) do
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx)
        rv,widgets.selectables.columns[i] = ImGui.Selectable(ctx, ('Item %d'):format(i-1), sel, ImGui.SelectableFlags_SpanAllColumns)
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, 'Some other contents')
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, '123456')
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  -- Add in a bit of silly fun...
  if ImGui.TreeNode(ctx, 'Grid') then
    local winning_state = true -- If all cells are selected...
    for ri,row in ipairs(widgets.selectables.grid) do
      for ci,sel in ipairs(row) do
        if not sel then
          winning_state = false
          break
        end
      end
    end
    if winning_state then
      local time = ImGui.GetTime(ctx)
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign,
        0.5 + 0.5 * math.cos(time * 2.0), 0.5 + 0.5 * math.sin(time * 3.0))
    end

    for ri,row in ipairs(widgets.selectables.grid) do
      for ci,col in ipairs(row) do
        if ci > 1 then
          ImGui.SameLine(ctx)
        end
        ImGui.PushID(ctx, ri * #widgets.selectables.grid + ci)
        if ImGui.Selectable(ctx, 'Sailor', col, 0, 50, 50) then
          -- Toggle clicked cell + toggle neighbors
          row[ci] = not row[ci]
          if ci > 1 then row[ci - 1] = not row[ci - 1]; end
          if ci < 4 then row[ci + 1] = not row[ci + 1]; end
          if ri > 1 then widgets.selectables.grid[ri - 1][ci] = not widgets.selectables.grid[ri - 1][ci]; end
          if ri < 4 then widgets.selectables.grid[ri + 1][ci] = not widgets.selectables.grid[ri + 1][ci]; end
        end
        ImGui.PopID(ctx)
      end
    end

    if winning_state then
      ImGui.PopStyleVar(ctx)
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Alignment') then
    demo.HelpMarker(
      "By default, Selectables uses style.SelectableTextAlign but it can be overridden on a per-item \z
       basis using PushStyleVar(). You'll probably want to always keep your default situation to \z
       left-align otherwise it becomes difficult to layout multiple items on a same line")

    for y = 1, 3 do
      for x = 1, 3 do
        local align_x, align_y = (x-1) / 2.0, (y-1) / 2.0
        local name = ('(%.1f,%.1f)'):format(align_x, align_y)
        if x > 1 then ImGui.SameLine(ctx); end
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, align_x, align_y)
        local row = widgets.selectables.align[y]
        rv,row[x] = ImGui.Selectable(ctx, name, row[x], ImGui.SelectableFlags_None, 80, 80)
        ImGui.PopStyleVar(ctx)
      end
    end

    ImGui.TreePop(ctx)
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsSelectionAndMultiSelect()
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Multi-selection demos
-- Also read: https://github.com/ocornut/imgui/wiki/Multi-Select
-------------------------------------------------------------------------------

local function DemoWindowWidgetsSelectionAndMultiSelect()
  local rv
  if not ImGui.TreeNode(ctx, 'Selection State & Multi-Select') then return end

  if not widgets.multisel then
    widgets.multisel = {
      single = -1,
      basic  = {false, false, false, false, false},
    }
  end

  demo.HelpMarker('Selections can be built using Selectable(), TreeNode() or other widgets. Selection state is owned by application code/data.')

  -- Without any fancy API: manage single-selection yourself.
  if ImGui.TreeNode(ctx, 'Single-Select') then
    for i = 0, 4 do
      if ImGui.Selectable(ctx, ('Object %d'):format(i), widgets.multisel.single == i) then
        widgets.multisel.single = i
      end
    end
    ImGui.TreePop(ctx)
  end

  -- Demonstrate implementation a most-basic form of multi-selection manually
  -- This doesn't support the Shift modifier which requires BeginMultiSelect()!
  if ImGui.TreeNode(ctx, 'Multi-Select (manual/simplified, without BeginMultiSelect)') then
    demo.HelpMarker('Hold Ctrl and click to select multiple items.')
    for i,sel in ipairs(widgets.multisel.basic) do
      if ImGui.Selectable(ctx, ('Object %d'):format(i-1), sel) then
        if not ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) then -- Clear selection when Ctrl is not held
          for j = 1, #widgets.multisel.basic do
            widgets.multisel.basic[j] = false
          end
        end
        widgets.multisel.basic[i] = not sel
      end
    end
    ImGui.TreePop(ctx)
  end

  -- TODO Multi-selection API not exposed in ReaImGui yet!

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsTabs()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsTabs()
  local rv
  if not ImGui.TreeNode(ctx, 'Tabs') then return end

  if not widgets.tabs then
    widgets.tabs = {
      flags1  = ImGui.TabBarFlags_Reorderable,
      opened  = {true, true, true, true},
      flags2  = ImGui.TabBarFlags_AutoSelectNewTabs |
                ImGui.TabBarFlags_Reorderable       |
                ImGui.TabBarFlags_FittingPolicyResizeDown,
      active  = {1, 2, 3},
      next_id = 4,
      show_leading_button  = true,
      show_trailing_button = true,
    }
  end

  local fitting_policy_mask = ImGui.TabBarFlags_FittingPolicyResizeDown |
                              ImGui.TabBarFlags_FittingPolicyScroll

  if ImGui.TreeNode(ctx, 'Basic') then
    if ImGui.BeginTabBar(ctx, 'MyTabBar', ImGui.TabBarFlags_None) then
      if ImGui.BeginTabItem(ctx, 'Avocado') then
        ImGui.Text(ctx, 'This is the Avocado tab!\nblah blah blah blah blah')
        ImGui.EndTabItem(ctx)
      end
      if ImGui.BeginTabItem(ctx, 'Broccoli') then
        ImGui.Text(ctx, 'This is the Broccoli tab!\nblah blah blah blah blah')
        ImGui.EndTabItem(ctx)
      end
      if ImGui.BeginTabItem(ctx, 'Cucumber') then
        ImGui.Text(ctx, 'This is the Cucumber tab!\nblah blah blah blah blah')
        ImGui.EndTabItem(ctx)
      end
      ImGui.EndTabBar(ctx)
    end
    ImGui.Separator(ctx)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Advanced & Close Button') then
    -- Expose a couple of the available flags. In most cases you may just call BeginTabBar() with no flags (0).
    rv,widgets.tabs.flags1 = ImGui.CheckboxFlags(ctx, 'TabBarFlags_Reorderable', widgets.tabs.flags1, ImGui.TabBarFlags_Reorderable)
    rv,widgets.tabs.flags1 = ImGui.CheckboxFlags(ctx, 'TabBarFlags_AutoSelectNewTabs', widgets.tabs.flags1, ImGui.TabBarFlags_AutoSelectNewTabs)
    rv,widgets.tabs.flags1 = ImGui.CheckboxFlags(ctx, 'TabBarFlags_TabListPopupButton', widgets.tabs.flags1, ImGui.TabBarFlags_TabListPopupButton)
    rv,widgets.tabs.flags1 = ImGui.CheckboxFlags(ctx, 'TabBarFlags_NoCloseWithMiddleMouseButton', widgets.tabs.flags1, ImGui.TabBarFlags_NoCloseWithMiddleMouseButton)
    rv,widgets.tabs.flags1 = ImGui.CheckboxFlags(ctx, 'TabBarFlags_DrawSelectedOverline', widgets.tabs.flags1, ImGui.TabBarFlags_DrawSelectedOverline)

    if widgets.tabs.flags1 & fitting_policy_mask == 0 then
      widgets.tabs.flags1 = widgets.tabs.flags1 | ImGui.TabBarFlags_FittingPolicyResizeDown -- was FittingPolicyDefault_
    end
    if ImGui.CheckboxFlags(ctx, 'TabBarFlags_FittingPolicyResizeDown', widgets.tabs.flags1, ImGui.TabBarFlags_FittingPolicyResizeDown) then
      widgets.tabs.flags1 = widgets.tabs.flags1 & ~fitting_policy_mask | ImGui.TabBarFlags_FittingPolicyResizeDown
    end
    if ImGui.CheckboxFlags(ctx, 'TabBarFlags_FittingPolicyScroll', widgets.tabs.flags1, ImGui.TabBarFlags_FittingPolicyScroll) then
      widgets.tabs.flags1 = widgets.tabs.flags1 & ~fitting_policy_mask | ImGui.TabBarFlags_FittingPolicyScroll
    end

    -- Tab Bar
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, 'Opened:')
    local names = {'Artichoke', 'Beetroot', 'Celery', 'Daikon'}
    for n, opened in ipairs(widgets.tabs.opened) do
      ImGui.SameLine(ctx)
      rv,widgets.tabs.opened[n] = ImGui.Checkbox(ctx, names[n], opened)
    end

    -- Passing a bool* to BeginTabItem() is similar to passing one to Begin():
    -- the underlying bool will be set to false when the tab is closed.
    if ImGui.BeginTabBar(ctx, 'MyTabBar', widgets.tabs.flags1) then
      for n,opened in ipairs(widgets.tabs.opened) do
        if opened then
          rv,widgets.tabs.opened[n] = ImGui.BeginTabItem(ctx, names[n], true, ImGui.TabItemFlags_None)
          if rv then
            ImGui.Text(ctx, ('This is the %s tab!'):format(names[n]))
            if n & 1 == 0 then
              ImGui.Text(ctx, 'I am an odd tab.')
            end
            ImGui.EndTabItem(ctx)
          end
        end
      end
      ImGui.EndTabBar(ctx)
    end
    ImGui.Separator(ctx)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'TabItemButton & Leading/Trailing flags') then
    -- TabItemButton() and Leading/Trailing flags are distinct features which we will demo together.
    -- (It is possible to submit regular tabs with Leading/Trailing flags, or TabItemButton tabs without Leading/Trailing flags...
    -- but they tend to make more sense together)
    rv,widgets.tabs.show_leading_button = ImGui.Checkbox(ctx, 'Show Leading TabItemButton()', widgets.tabs.show_leading_button)
    rv,widgets.tabs.show_trailing_button = ImGui.Checkbox(ctx, 'Show Trailing TabItemButton()', widgets.tabs.show_trailing_button)

    -- Expose some other flags which are useful to showcase how they interact with Leading/Trailing tabs
    rv,widgets.tabs.flags2 = ImGui.CheckboxFlags(ctx, 'TabBarFlags_TabListPopupButton', widgets.tabs.flags2, ImGui.TabBarFlags_TabListPopupButton)
    if ImGui.CheckboxFlags(ctx, 'TabBarFlags_FittingPolicyResizeDown', widgets.tabs.flags2, ImGui.TabBarFlags_FittingPolicyResizeDown) then
      widgets.tabs.flags2 = widgets.tabs.flags2 & ~fitting_policy_mask | ImGui.TabBarFlags_FittingPolicyResizeDown
    end
    if ImGui.CheckboxFlags(ctx, 'TabBarFlags_FittingPolicyScroll', widgets.tabs.flags2, ImGui.TabBarFlags_FittingPolicyScroll) then
      widgets.tabs.flags2 = widgets.tabs.flags2 & ~fitting_policy_mask | ImGui.TabBarFlags_FittingPolicyScroll
    end

    if ImGui.BeginTabBar(ctx, 'MyTabBar', widgets.tabs.flags2) then
      -- Demo a Leading TabItemButton(): click the '?' button to open a menu
      if widgets.tabs.show_leading_button then
        if ImGui.TabItemButton(ctx, '?', ImGui.TabItemFlags_Leading | ImGui.TabItemFlags_NoTooltip) then
          ImGui.OpenPopup(ctx, 'MyHelpMenu')
        end
      end
      if ImGui.BeginPopup(ctx, 'MyHelpMenu') then
        ImGui.Selectable(ctx, 'Hello!')
        ImGui.EndPopup(ctx)
      end

      -- Demo Trailing Tabs: click the "+" button to add a new tab.
      -- (In your app you may want to use a font icon instead of the "+")
      -- We submit it before the regular tabs, but thanks to the TabItemFlags_Trailing flag it will always appear at the end.
      if widgets.tabs.show_trailing_button then
        if ImGui.TabItemButton(ctx, '+', ImGui.TabItemFlags_Trailing | ImGui.TabItemFlags_NoTooltip) then
          -- add new tab
          table.insert(widgets.tabs.active, widgets.tabs.next_id)
          widgets.tabs.next_id = widgets.tabs.next_id + 1
        end
      end

      -- Submit our regular tabs
      local n = 1
      while n <= #widgets.tabs.active do
        local name = ('%04d'):format(widgets.tabs.active[n]-1)
        local open
        rv,open = ImGui.BeginTabItem(ctx, name, true, ImGui.TabItemFlags_None)
        if rv then
          ImGui.Text(ctx, ('This is the %s tab!'):format(name))
          ImGui.EndTabItem(ctx)
        end

        if open then
          n = n + 1
        else
          table.remove(widgets.tabs.active, n)
        end
      end

      ImGui.EndTabBar(ctx)
    end
    ImGui.Separator(ctx)
    ImGui.TreePop(ctx)
  end
  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsVerticalSliders()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsText()
  local rv
  if not ImGui.TreeNode(ctx, 'Text') then return end

  if not widgets.text then
    widgets.text = {
      wrap_width = 200.0,
      utf8 = '日本語',
      custom_size = 16,
      custom_scale = 1.0,
    }
  end

  if ImGui.TreeNode(ctx, 'Colorful Text') then
    -- Using shortcut. You can use PushStyleColor()/PopStyleColor() for more flexibility.
    ImGui.TextColored(ctx, 0xFF00FFFF, 'Pink')
    ImGui.TextColored(ctx, 0xFFFF00FF, 'Yellow')
    ImGui.TextDisabled(ctx, 'Disabled')
    ImGui.SameLine(ctx); demo.HelpMarker('The TextDisabled color is stored in ImGuiStyle.')
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Font Size') then
    -- local global_scale = style.FontScaleMain * style.FontScaleDpi
    -- ImGui.Text(ctx, ('style.FontScaleMain = %0.2f'):format(style.FontScaleMain))
    -- ImGui.Text(ctx, ('style.FontScaleDpi = %0.2f'):format(style.FontScaleDpi))
    -- ImGui.Text(ctx, ('global_scale = ~%0.2f'):format(global_scale)) -- This is not technically accurate as internal scales may apply, but conceptually let's pretend it is.
    ImGui.Text(ctx, ('FontSize = %0.2f'):format(ImGui.GetFontSize(ctx)))

    -- ImGui.SeparatorText(ctx, '')
    rv, widgets.text.custom_size = ImGui.SliderDouble(ctx, 'Custom size', widgets.text.custom_size, 10.0, 100.0, '%.0f')
    ImGui.Text(ctx, 'ImGui.PushFont(nil, custom_size)')
    ImGui.PushFont(ctx, nil, widgets.text.custom_size)
    ImGui.Text(ctx, 'The quick brown fox jumps over the lazy dog.')
    -- ImGui.Text(ctx, ('FontSize = %.2f (== %.2f * global_scale)'):format(ImGui.GetFontSize(ctx), widgets.text.custom_size))
    ImGui.PopFont(ctx)

    -- ImGui.SeparatorText(ctx, '')
    -- rv, widgets.text.custom_scale = ImGui.SliderDouble(ctx, 'Custom scale', widgets.text.custom_scale, 0.5, 4.0, '%.2f')
    -- ImGui.Text(ctx, 'ImGui.PushFont(nil, style.FontSizeBase * custom_scale)')
    -- ImGui.PushFont(ctx, nil, style.FontSizeBase * widgets.text.custom_scale)
    -- ImGui.Text(ctx, ('FontSize = %.2f (== style.FontSizeBase * %.2f * global_scale)'):format(ImGui.GetFontSize(ctx), widgets.text.custom_scale))
    -- ImGui.PopFont(ctx)

    -- ImGui.SeparatorText(ctx, '')
    -- for scaling = 0.5, 4.0, 0.5 do
    --   ImGui.PushFont(ctx, nil, style.FontSizeBase * scaling)
    --   ImGui.Text(ctx, ('FontSize = %.2f (== style.FontSizeBase * %.2f * global_scale)'):format(ImGui.GetFontSize(ctx), scaling))
    --   ImGui.PopFont(ctx)
    -- end

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Word Wrapping') then
    -- Using shortcut. You can use PushTextWrapPos()/PopTextWrapPos() for more flexibility.
    ImGui.TextWrapped(ctx,
      'This text should automatically wrap on the edge of the window. The current implementation ' ..
      'for text wrapping follows simple rules suitable for English and possibly other languages.')
    ImGui.Spacing(ctx)

    rv,widgets.text.wrap_width = ImGui.SliderDouble(ctx, 'Wrap width', widgets.text.wrap_width, -20, 600, '%.0f')

    local draw_list = ImGui.GetWindowDrawList(ctx)
    for n = 0, 1 do
      ImGui.Text(ctx, ('Test paragraph %d:'):format(n))

      local screen_x, screen_y = ImGui.GetCursorScreenPos(ctx)
      local marker_min_x, marker_min_y = screen_x + widgets.text.wrap_width, screen_y
      local marker_max_x, marker_max_y = screen_x + widgets.text.wrap_width + 10, screen_y + ImGui.GetTextLineHeight(ctx)

      local window_x, window_y = ImGui.GetCursorPos(ctx)
      ImGui.PushTextWrapPos(ctx, window_x + widgets.text.wrap_width)

      if n == 0 then
        ImGui.Text(ctx, ('The lazy dog is a good dog. This paragraph should fit within %.0f pixels. Testing a 1 character word. The quick brown fox jumps over the lazy dog.'):format(widgets.text.wrap_width))
      else
        ImGui.Text(ctx, 'aaaaaaaa bbbbbbbb, c cccccccc,dddddddd. d eeeeeeee   ffffffff. gggggggg!hhhhhhhh')
      end

      -- Draw actual text bounding box, following by marker of our expected limit (should not overlap!)
      local text_min_x, text_min_y = ImGui.GetItemRectMin(ctx)
      local text_max_x, text_max_y = ImGui.GetItemRectMax(ctx)
      ImGui.DrawList_AddRect(draw_list, text_min_x, text_min_y, text_max_x, text_max_y, 0xFFFF00FF)
      ImGui.DrawList_AddRectFilled(draw_list, marker_min_x, marker_min_y, marker_max_x, marker_max_y, 0xFF00FFFF)

      ImGui.PopTextWrapPos(ctx)
    end

    ImGui.TreePop(ctx)
  end

  -- Not supported by the default built-in font TODO
  if ImGui.TreeNode(ctx, 'UTF-8 Text') then
    -- UTF-8 test with Japanese characters
    -- (Needs a suitable font? Try "Noto Sans CJK JP" or "Arial Unicode". See docs/FONTS.md for details.)
    ImGui.Text(ctx, 'Hiragana: かきくけこ (kakikukeko)')
    ImGui.Text(ctx, 'Kanjis: 日本語 (nihongo)')
    rv,widgets.text.utf8 = ImGui.InputText(ctx, 'UTF-8 input', widgets.text.utf8)

    ImGui.TreePop(ctx)
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsTextFilter()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsTextFilter()
  if not ImGui.TreeNode(ctx, 'Text Filter') then return end

  -- Helper class to easy setup a text filter.
  -- You may want to implement a more feature-full filtering scheme in your own application.
  if not widgets.filter then
    widgets.filter = ImGui.CreateTextFilter()
    -- prevent the filter object from being destroyed once unused for one or more frames
    ImGui.Attach(ctx, widgets.filter)
  end

  demo.HelpMarker('Not a widget per-se, but TextFilter is a helper to perform simple filtering on text strings.')
  ImGui.Text(ctx, [[Filter usage:
  ""         display all lines
  "xxx"      display lines containing "xxx"
  "xxx,yyy"  display lines containing "xxx" or "yyy"
  "-xxx"     hide lines containing "xxx"]])
  ImGui.TextFilter_Draw(widgets.filter, ctx)
  local lines = {'aaa1.c', 'bbb1.c', 'ccc1.c', 'aaa2.cpp', 'bbb2.cpp', 'ccc2.cpp', 'abc.h', 'hello, world'}
  for i, line in ipairs(lines) do
    if ImGui.TextFilter_PassFilter(widgets.filter, line) then
      ImGui.BulletText(ctx, line)
    end
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsTextInput()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsTextInput()
  local rv
  if not ImGui.TreeNode(ctx, 'Text Input') then return end

  if not widgets.input then
    widgets.input = {
      buf = {'', '', '', '', '', '', '', '', '', ''},
      password = 'hunter2',
    }
  end

  if ImGui.TreeNode(ctx, 'Multi-line Text Input') then
    if not widgets.input.multiline then
      widgets.input.multiline = {
        text = [[/*
 The Pentium F00F bug, shorthand for F0 0F C7 C8,
 the hexadecimal encoding of one offending instruction,
 more formally, the invalid operand with locked CMPXCHG8B
 instruction bug, is a design flaw in the majority of
 Intel Pentium, Pentium MMX, and Pentium OverDrive
 processors (all in the P5 microarchitecture).
*/

label:
	lock cmpxchg8b eax
]],
        flags = ImGui.InputTextFlags_AllowTabInput,
      }
    end
    rv,widgets.input.multiline.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_ReadOnly', widgets.input.multiline.flags, ImGui.InputTextFlags_ReadOnly);
    rv,widgets.input.multiline.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_AllowTabInput', widgets.input.multiline.flags, ImGui.InputTextFlags_AllowTabInput);
    ImGui.SameLine(ctx); demo.HelpMarker("When _AllowTabInput is set, passing through the widget with Tabbing doesn't automatically activate it, in order to also cycling through subsequent widgets.")
    rv,widgets.input.multiline.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_CtrlEnterForNewLine', widgets.input.multiline.flags, ImGui.InputTextFlags_CtrlEnterForNewLine);
    rv,widgets.input.multiline.text = ImGui.InputTextMultiline(ctx, '##source', widgets.input.multiline.text, -FLT_MIN, ImGui.GetTextLineHeight(ctx) * 16, widgets.input.multiline.flags)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Filtered Text Input') then
    if not ImGui.ValidatePtr(widgets.input.filterCasingSwap, 'ImGui_Function*') then
      -- Modify character input by altering 'data->Eventchar' (ImGuiInputTextFlags_CallbackCharFilter callback)
      widgets.input.filterCasingSwap = ImGui.CreateFunctionFromEEL([[
      diff = 'a' - 'A';
      EventChar >= 'a' && EventChar <= 'z' ? EventChar = EventChar - diff : // Lowercase becomes uppercase
      EventChar >= 'A' && EventChar <= 'Z' ? EventChar = EventChar + diff ; // Uppercase becomes lowercase
      ]])
    end
    if not ImGui.ValidatePtr(widgets.input.filterImGuiLetters, 'ImGui_Function*') then
      -- Only allow 'i' or 'm' or 'g' or 'u' or 'i' letters, filter out anything else
      widgets.input.filterImGuiLetters = ImGui.CreateFunctionFromEEL([[
      eat = 1; i = strlen(#allowed);
      while(
        i -= 1;
        str_getchar(#allowed, i) == EventChar ? eat = 0;
        eat && i;
      );
      eat ? EventChar = 0;
      ]])
      ImGui.Function_SetValue_String(widgets.input.filterImGuiLetters, '#allowed', 'imgui')
    end

    rv,widgets.input.buf[1] = ImGui.InputText(ctx, 'default',     widgets.input.buf[1])
    rv,widgets.input.buf[2] = ImGui.InputText(ctx, 'decimal',     widgets.input.buf[2], ImGui.InputTextFlags_CharsDecimal)
    rv,widgets.input.buf[3] = ImGui.InputText(ctx, 'hexadecimal', widgets.input.buf[3], ImGui.InputTextFlags_CharsHexadecimal | ImGui.InputTextFlags_CharsUppercase)
    rv,widgets.input.buf[4] = ImGui.InputText(ctx, 'uppercase',   widgets.input.buf[4], ImGui.InputTextFlags_CharsUppercase)
    rv,widgets.input.buf[5] = ImGui.InputText(ctx, 'no blank',    widgets.input.buf[5], ImGui.InputTextFlags_CharsNoBlank)
    rv,widgets.input.buf[6] = ImGui.InputText(ctx, 'casing swap', widgets.input.buf[6], ImGui.InputTextFlags_CallbackCharFilter, widgets.input.filterCasingSwap)
    rv,widgets.input.buf[7] = ImGui.InputText(ctx, '"imgui"',     widgets.input.buf[7], ImGui.InputTextFlags_CallbackCharFilter, widgets.input.filterImGuiLetters)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Password Input') then
    rv,widgets.input.password = ImGui.InputText(ctx, 'password', widgets.input.password, ImGui.InputTextFlags_Password)
    ImGui.SameLine(ctx); demo.HelpMarker("Display all characters as '*'.\nDisable clipboard cut and copy.\nDisable logging.\n")
    rv,widgets.input.password = ImGui.InputTextWithHint(ctx, 'password (w/ hint)', '<password>', widgets.input.password, ImGui.InputTextFlags_Password)
    rv,widgets.input.password = ImGui.InputText(ctx, 'password (clear)', widgets.input.password)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Completion, History, Edit Callbacks') then
    if not ImGui.ValidatePtr(widgets.input.callback, 'ImGui_Function*') then
      widgets.input.callback = ImGui.CreateFunctionFromEEL([[
      EventFlag == InputTextFlags_CallbackCompletion ?
        InputTextCallback_InsertChars(CursorPos, "..");
      EventFlag == InputTextFlags_CallbackHistory ? (
        EventKey == Key_UpArrow ? (
          InputTextCallback_DeleteChars(0, strlen(#Buf));
          InputTextCallback_InsertChars(0, "Pressed Up!");
          InputTextCallback_SelectAll();
        ) : EventKey == Key_DownArrow ? (
          InputTextCallback_DeleteChars(0, strlen(#Buf));
          InputTextCallback_InsertChars(0, "Pressed Down!");
          InputTextCallback_SelectAll();
        );
      );
      EventFlag == InputTextFlags_CallbackEdit ? (
        // Toggle casing of first character
        c = str_getchar(#Buf, 0);
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ? (
          str_setchar(#first, 0, c ~ 32);
          InputTextCallback_DeleteChars(0, 1);
          InputTextCallback_InsertChars(0, #first);
        );

        // Increment a counter
        edit_count += 1;
      );
      ]])
      local consts = {
        'InputTextFlags_CallbackCompletion',
        'InputTextFlags_CallbackEdit',
        'InputTextFlags_CallbackHistory',
        'Key_UpArrow',
        'Key_DownArrow',
      }
      for _, const in ipairs(consts) do
        ImGui.Function_SetValue(widgets.input.callback, const, ImGui[const])
      end
    end

    rv,widgets.input.buf[8] = ImGui.InputText(ctx, 'Completion', widgets.input.buf[8], ImGui.InputTextFlags_CallbackCompletion, widgets.input.callback)
    ImGui.SameLine(ctx); demo.HelpMarker(
      "Here we append \"..\" each time Tab is pressed. \z
        See 'Examples>Console' for a more meaningful demonstration of using this callback.")

    rv,widgets.input.buf[9] = ImGui.InputText(ctx, 'History', widgets.input.buf[9], ImGui.InputTextFlags_CallbackHistory, widgets.input.callback)
    ImGui.SameLine(ctx); demo.HelpMarker(
      "Here we replace and select text each time Up/Down are pressed. \z
        See 'Examples>Console' for a more meaningful demonstration of using this callback.")

    rv,widgets.input.buf[10] = ImGui.InputText(ctx, 'Edit', widgets.input.buf[10], ImGui.InputTextFlags_CallbackEdit, widgets.input.callback)
    ImGui.SameLine(ctx); demo.HelpMarker(
      'Here we toggle the casing of the first character on every edit + count edits.')
    local edit_count = ImGui.Function_GetValue(widgets.input.callback, 'edit_count')
    ImGui.SameLine(ctx); ImGui.Text(ctx, ('(%d)'):format(edit_count))

    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Eliding, Alignment') then
    if not widgets.input.align then
      widgets.input.align = {
        buf = '/path/to/some/folder/with/long/filename.cpp',
        flags = ImGui.InputTextFlags_ElideLeft,
      }
    end
    rv,widgets.input.align.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_ElideLeft', widgets.input.align.flags, ImGui.InputTextFlags_ElideLeft)
    rv,widgets.input.align.buf = ImGui.InputText(ctx, 'Path', widgets.input.align.buf, widgets.input.align.flags)
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Miscellaneous') then
    if not widgets.input.misc then
      widgets.input.misc = {
        buf = '',
        flags = ImGui.InputTextFlags_EscapeClearsAll,
      }
    end

    rv, widgets.input.misc.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_EscapeClearsAll', widgets.input.misc.flags, ImGui.InputTextFlags_EscapeClearsAll)
    rv, widgets.input.misc.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_ReadOnly', widgets.input.misc.flags, ImGui.InputTextFlags_ReadOnly)
    rv, widgets.input.misc.flags = ImGui.CheckboxFlags(ctx, 'InputTextFlags_NoUndoRedo', widgets.input.misc.flags, ImGui.InputTextFlags_NoUndoRedo)
    rv, widgets.input.misc.buf   = ImGui.InputText(ctx, 'Hello', widgets.input.misc.buf, widgets.input.misc.flags)
    ImGui.TreePop(ctx)
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsTooltips()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsTooltips()
  local rv
  if not ImGui.TreeNode(ctx, 'Tooltips') then return end

  if not widgets.tooltips then
    widgets.tooltips = {
      curve = reaper.new_array({0.6, 0.1, 1.0, 0.5, 0.92, 0.1, 0.2}),
      always_on = 0,
    }
  end

  ImGui.SeparatorText(ctx, 'General')

  -- Typical use cases:
  -- - Short-form (text only):      SetItemTooltip("Hello");
  -- - Short-form (any contents):   if (BeginItemTooltip()) { Text("Hello"); EndTooltip(); }

  -- - Full-form (text only):       if (IsItemHovered(...)) { SetTooltip("Hello"); }
  -- - Full-form (any contents):    if (IsItemHovered(...) && BeginTooltip()) { Text("Hello"); EndTooltip(); }

  demo.HelpMarker(
    'Tooltip are typically created by using a IsItemHovered() + SetTooltip() sequence.\n\n\z
     We provide a helper SetItemTooltip() function to perform the two with standards flags.')

  local sz_w, sz_h = -FLT_MIN, 0.0
  ImGui.Button(ctx, 'Basic', sz_w, sz_h)
  ImGui.SetItemTooltip(ctx, 'I am a tooltip')

  ImGui.Button(ctx, 'Fancy', sz_w, sz_h)
  if ImGui.BeginItemTooltip(ctx) then
    ImGui.Text(ctx, 'I am a fancy tooltip')
    ImGui.PlotLines(ctx, 'Curve', widgets.tooltips.curve)
    ImGui.Text(ctx, ('Sin(time) = %f'):format(math.sin(ImGui.GetTime(ctx))))
    ImGui.EndTooltip(ctx)
  end

  ImGui.SeparatorText(ctx, 'Always On')

  -- Showcase NOT relying on a IsItemHovered() to emit a tooltip.
  -- Here the tooltip is always emitted when 'always_on == true'.
  rv, widgets.tooltips.always_on = ImGui.RadioButtonEx(ctx, 'Off', widgets.tooltips.always_on, 0)
  ImGui.SameLine(ctx)
  rv, widgets.tooltips.always_on = ImGui.RadioButtonEx(ctx, 'Always On (Simple)', widgets.tooltips.always_on, 1)
  ImGui.SameLine(ctx)
  rv, widgets.tooltips.always_on = ImGui.RadioButtonEx(ctx, 'Always On (Advanced)', widgets.tooltips.always_on, 2)
  if widgets.tooltips.always_on == 1 then
    ImGui.SetTooltip(ctx, 'I am following you around.')
  elseif widgets.tooltips.always_on == 2 and ImGui.BeginTooltip(ctx) then
    ImGui.ProgressBar(ctx, math.sin(ImGui.GetTime(ctx)) * 0.5 + 0.5, ImGui.GetFontSize(ctx) * 25, 0.0)
    ImGui.EndTooltip(ctx)
  end

  ImGui.SeparatorText(ctx, 'Custom')

  demo.HelpMarker(
    'Passing HoveredFlags_ForTooltip to IsItemHovered() is the preferred way to standardize \z
     tooltip activation details across your application. You may however decide to use custom\z
     flags for a specific tooltip instance.')

  -- The following examples are passed for documentation purpose but may not be useful to most users.
  -- Passing HoveredFlags_ForTooltip to IsItemHovered() will pull HoveredFlags flags values from
  -- ConfigVar_HoverFlagsForTooltipMouse or ConfigVar_HoverFlagsForTooltipNav depending on whether mouse or keyboard/gamepad is being used.
  -- With default settings, HoveredFlags_ForTooltip is equivalent to HoveredFlags_DelayShort + HoveredFlags_Stationary.
  ImGui.Button(ctx, 'Manual', sz_w, sz_h)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_ForTooltip) then
    ImGui.SetTooltip(ctx, 'I am a manually emitted tooltip.')
  end

  ImGui.Button(ctx, 'DelayNone', sz_w, sz_h)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNone) then
    ImGui.SetTooltip(ctx, 'I am a tooltip with no delay.')
  end

  ImGui.Button(ctx, 'DelayShort', sz_w, sz_h)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort | ImGui.HoveredFlags_NoSharedDelay) then
    ImGui.SetTooltip(ctx, ('I am a tooltip with a short delay (%0.2f sec).'):format(ImGui.GetConfigVar(ctx, ImGui.ConfigVar_HoverDelayShort)))
  end

  ImGui.Button(ctx, 'DelayLong', sz_w, sz_h)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayNormal | ImGui.HoveredFlags_NoSharedDelay) then
    ImGui.SetTooltip(ctx, ('I am a tooltip with a long delay (%0.2f sec).'):format(ImGui.GetConfigVar(ctx, ImGui.ConfigVar_HoverDelayNormal)))
  end

  ImGui.Button(ctx, 'Stationary', sz_w, sz_h)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_Stationary) then
    ImGui.SetTooltip(ctx, 'I am a tooltip requiring mouse to be stationary before activating.')
  end

  -- Using ImGuiHoveredFlags_ForTooltip will pull flags from ConfigVar_HoverFlagsForTooltipMouse' or ConfigVar_HoverFlagsForTooltipNav,
  -- which default value include the HoveredFlags_AllowWhenDisabled flag.
  ImGui.BeginDisabled(ctx)
  ImGui.Button(ctx, 'Disabled item', sz_w, sz_h)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_ForTooltip) then
    ImGui.SetTooltip(ctx, 'I am a a tooltip for a disabled item.')
  end
  ImGui.EndDisabled(ctx)

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsTreeNodes()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsTreeNodes()
  local rv
  if not ImGui.TreeNode(ctx, 'Trees Nodes') then return end

  if not widgets.trees then
    widgets.trees = {}
  end

  -- See see "Examples -> Property Editor" (ShowExampleAppPropertyEditor() function) for a fancier, data-driven tree.
  if ImGui.TreeNode(ctx, 'Basic trees') then
    for i = 0, 4 do
      -- Use SetNextItemOpen() so set the default state of a node to be open. We could
      -- also use TreeNodeEx() with the TreeNodeFlags_DefaultOpen flag to achieve the same thing!
      if i == 0 then
        ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once)
      end

      if ImGui.TreeNodeEx(ctx, i, ('Child %d'):format(i)) then
        ImGui.Text(ctx, 'blah blah')
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, 'button') then end
        ImGui.TreePop(ctx)
      end
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, "Hierarchy lines") then
    if not widgets.trees.hierarchy then
      widgets.trees.hierarchy = {
        base_flags = ImGui.TreeNodeFlags_DrawLinesFull |
                     ImGui.TreeNodeFlags_DefaultOpen,
      }
    end

    -- demo.HelpMarker('Default option for DrawLinesXXX is stored in style.TreeLinesFlags')
    rv,widgets.trees.hierarchy.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_DrawLinesNone', widgets.trees.hierarchy.base_flags, ImGui.TreeNodeFlags_DrawLinesNone)
    rv,widgets.trees.hierarchy.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_DrawLinesFull', widgets.trees.hierarchy.base_flags, ImGui.TreeNodeFlags_DrawLinesFull)
    rv,widgets.trees.hierarchy.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_DrawLinesToNodes', widgets.trees.hierarchy.base_flags, ImGui.TreeNodeFlags_DrawLinesToNodes)

    if ImGui.TreeNode(ctx, 'Parent', widgets.trees.hierarchy.base_flags) then
      if ImGui.TreeNode(ctx, 'Child 1', widgets.trees.hierarchy.base_flags) then
        ImGui.Button(ctx, 'Button for Child 1')
        ImGui.TreePop(ctx)
      end
      if ImGui.TreeNode(ctx, 'Child 2', widgets.trees.hierarchy.base_flags) then
        ImGui.Button(ctx, 'Button for Child 2')
        ImGui.TreePop(ctx)
      end
      ImGui.Text(ctx, 'Remaining contents')
      ImGui.Text(ctx, 'Remaining contents')
      ImGui.TreePop(ctx)
    end
    ImGui.TreePop(ctx)
  end

  if ImGui.TreeNode(ctx, 'Advanced, with Selectable nodes') then
    if not widgets.trees.advanced then
      widgets.trees.advanced = {
        base_flags = ImGui.TreeNodeFlags_OpenOnArrow |
                    ImGui.TreeNodeFlags_OpenOnDoubleClick |
                    ImGui.TreeNodeFlags_SpanAvailWidth,
        align_label_with_current_x_position = false,
        test_drag_and_drop = false,
        selection_mask = 1 << 2,
      }
    end
    demo.HelpMarker(
      'This is a more typical looking tree with selectable nodes.\n\z
       Click to select, Ctrl+Click to toggle, click on arrows or double-click to open.')
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_OpenOnArrow',       widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_OpenOnArrow)
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_OpenOnDoubleClick', widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_OpenOnDoubleClick)
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanAvailWidth',    widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_SpanAvailWidth); ImGui.SameLine(ctx); demo.HelpMarker('Extend hit area to all available width instead of allowing more items to be laid out after the node.')
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanFullWidth',     widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_SpanFullWidth)
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanLabelWidth',     widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_SpanLabelWidth); ImGui.SameLine(ctx); demo.HelpMarker('Reduce hit area to the text label and a bit of margin.')
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanAllColumns',    widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_SpanAllColumns); ImGui.SameLine(ctx); demo.HelpMarker('For use in Tables only.')
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_AllowOverlap',     widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_AllowOverlap);
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_Framed',           widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_Framed); ImGui.SameLine(ctx); demo.HelpMarker('Draw frame with background (e.g. for CollapsingHeader)')
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_NavLeftJumpsToParent', widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_NavLeftJumpsToParent)

    -- demo.HelpMarker('Default option for DrawLinesXXX is stored in style.TreeLinesFlags')
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_DrawLinesNone', widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_DrawLinesNone)
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_DrawLinesFull', widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_DrawLinesFull)
    rv,widgets.trees.advanced.base_flags = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_DrawLinesToNodes', widgets.trees.advanced.base_flags, ImGui.TreeNodeFlags_DrawLinesToNodes)

    rv,widgets.trees.advanced.align_label_with_current_x_position = ImGui.Checkbox(ctx, 'Align label with current X position', widgets.trees.advanced.align_label_with_current_x_position)
    rv,widgets.trees.advanced.test_drag_and_drop = ImGui.Checkbox(ctx, 'Test tree node as drag source',      widgets.trees.advanced.test_drag_and_drop)
    ImGui.Text(ctx, 'Hello!')
    if widgets.trees.advanced.align_label_with_current_x_position then
      ImGui.Unindent(ctx, ImGui.GetTreeNodeToLabelSpacing(ctx))
    end

    -- 'selection_mask' is dumb representation of what may be user-side selection state.
    --  You may retain selection state inside or outside your objects in whatever format you see fit.
    -- 'node_clicked' is temporary storage of what node we have clicked to process selection at the end
    -- of the loop. May be a pointer to your own node type, etc.
    local node_clicked = -1

    for i = 0, 5 do
      -- Disable the default "open on single-click behavior" + set Selected flag according to our selection.
      -- To alter selection we use IsItemClicked() && !IsItemToggledOpen(), so clicking on an arrow doesn't alter selection.
      local node_flags = widgets.trees.advanced.base_flags
      local is_selected = (widgets.trees.advanced.selection_mask & (1 << i)) ~= 0
      if is_selected then
        node_flags = node_flags | ImGui.TreeNodeFlags_Selected
      end
      if i < 3 then
        -- Items 0..2 are Tree Node
        local node_open = ImGui.TreeNodeEx(ctx, i, ('Selectable Node %d'):format(i), node_flags)
        if ImGui.IsItemClicked(ctx) and not ImGui.IsItemToggledOpen(ctx) then
          node_clicked = i
        end
        if widgets.trees.advanced.test_drag_and_drop and ImGui.BeginDragDropSource(ctx) then
          ImGui.SetDragDropPayload(ctx, 'TREENODE', '')
          ImGui.Text(ctx, 'This is a drag and drop source')
          ImGui.EndDragDropSource(ctx)
        end
        if i == 2 and widgets.trees.advanced.base_flags & ImGui.TreeNodeFlags_SpanLabelWidth ~= 0 then
            -- Item 2 has an additional inline button to help demonstrate SpanLabelWidth.
            ImGui.SameLine(ctx)
            if ImGui.SmallButton(ctx, 'button') then end
        end
        if node_open then
          ImGui.BulletText(ctx, 'Blah blah\nBlah Blah')
          ImGui.SameLine(ctx)
          ImGui.SmallButton(ctx, 'Button')
          ImGui.TreePop(ctx)
        end
      else
        -- Items 3..5 are Tree Leaves
        -- The only reason we use TreeNode at all is to allow selection of the leaf. Otherwise we can
        -- use BulletText() or advance the cursor by GetTreeNodeToLabelSpacing() and call Text().
        node_flags = node_flags | ImGui.TreeNodeFlags_Leaf | ImGui.TreeNodeFlags_NoTreePushOnOpen -- | ImGui.TreeNodeFlags_Bullet
        ImGui.TreeNodeEx(ctx, i, ('Selectable Leaf %d'):format(i), node_flags)
        if ImGui.IsItemClicked(ctx) and not ImGui.IsItemToggledOpen(ctx) then
          node_clicked = i
        end
        if widgets.trees.advanced.test_drag_and_drop and ImGui.BeginDragDropSource(ctx) then
          ImGui.SetDragDropPayload(ctx, 'TREENODE', '')
          ImGui.Text(ctx, 'This is a drag and drop source')
          ImGui.EndDragDropSource(ctx)
        end
      end
    end

    if node_clicked ~= -1 then
      -- Update selection state
      -- (process outside of tree loop to avoid visual inconsistencies during the clicking frame)
      if ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) then -- Ctrl+click to toggle
        widgets.trees.advanced.selection_mask = widgets.trees.advanced.selection_mask ~ (1 << node_clicked)
      elseif widgets.trees.advanced.selection_mask & (1 << node_clicked) == 0 then -- Depending on selection behavior you want, may want to preserve selection when clicking on item that is part of the selection
        widgets.trees.advanced.selection_mask = (1 << node_clicked)                -- Click to single-select
      end
    end

    if widgets.trees.advanced.align_label_with_current_x_position then
      ImGui.Indent(ctx, ImGui.GetTreeNodeToLabelSpacing(ctx))
    end

    ImGui.TreePop(ctx)
  end

  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgetsVerticalSliders()
-------------------------------------------------------------------------------

local function DemoWindowWidgetsVerticalSliders()
  local rv
  if not ImGui.TreeNode(ctx, 'Vertical Sliders') then return end

  if not widgets.vsliders then
    widgets.vsliders = {
      int_value = 0,
      values    = {0.0,  0.60, 0.35, 0.9, 0.70, 0.20, 0.0},
      values2   = {0.20, 0.80, 0.40, 0.25},
    }
  end

  local spacing = 4
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, spacing, spacing)

  rv,widgets.vsliders.int_value = ImGui.VSliderInt(ctx, '##int', 18, 160, widgets.vsliders.int_value, 0, 5)
  ImGui.SameLine(ctx)

  ImGui.PushID(ctx, 'set1')
  for i,v in ipairs(widgets.vsliders.values) do
    if i > 1 then ImGui.SameLine(ctx) end
    ImGui.PushID(ctx, i)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,        demo.HSV((i-1) / 7.0, 0.5, 0.5, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, demo.HSV((i-1) / 7.0, 0.6, 0.5, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive,  demo.HSV((i-1) / 7.0, 0.7, 0.5, 1.0))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab,     demo.HSV((i-1) / 7.0, 0.9, 0.9, 1.0))
    rv,widgets.vsliders.values[i] = ImGui.VSliderDouble(ctx, '##v', 18, 160, v, 0.0, 1.0, ' ')
    if ImGui.IsItemActive(ctx) or ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, ('%.3f'):format(v))
    end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopID(ctx)
  end
  ImGui.PopID(ctx)

  ImGui.SameLine(ctx)
  ImGui.PushID(ctx, 'set2')
  local rows = 3
  local small_slider_w, small_slider_h = 18, (160.0 - (rows - 1) * spacing) / rows
  for nx,v2 in ipairs(widgets.vsliders.values2) do
    if nx > 1 then ImGui.SameLine(ctx) end
    ImGui.BeginGroup(ctx)
    for ny = 0, rows - 1 do
      ImGui.PushID(ctx, nx * rows + ny)
      rv,v2 = ImGui.VSliderDouble(ctx, '##v', small_slider_w, small_slider_h, v2, 0.0, 1.0, ' ')
      if rv then
        widgets.vsliders.values2[nx] = v2
      end
      if ImGui.IsItemActive(ctx) or ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, ('%.3f'):format(v2))
      end
      ImGui.PopID(ctx)
    end
    ImGui.EndGroup(ctx)
  end
  ImGui.PopID(ctx)

  ImGui.SameLine(ctx)
  ImGui.PushID(ctx, 'set3')
  for i = 1, 4 do
    local v = widgets.vsliders.values[i]
    if i > 1 then ImGui.SameLine(ctx) end
    ImGui.PushID(ctx, i)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 40)
    rv,widgets.vsliders.values[i] = ImGui.VSliderDouble(ctx, '##v', 40, 160, v, 0.0, 1.0, '%.2f\nsec')
    ImGui.PopStyleVar(ctx)
    ImGui.PopID(ctx)
  end
  ImGui.PopID(ctx)
  ImGui.PopStyleVar(ctx)
  ImGui.TreePop(ctx)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowWidgets()
-------------------------------------------------------------------------------

function demo.DemoWindowWidgets()
  --ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once)
  if not ImGui.CollapsingHeader(ctx, 'Widgets') then return end

  if widgets.disable_all then ImGui.BeginDisabled(ctx) end

  DemoWindowWidgetsBasic()
  DemoWindowWidgetsBullets()
  DemoWindowWidgetsCollapsingHeaders()
  DemoWindowWidgetsComboBoxes()
  DemoWindowWidgetsColorAndPickers()
  DemoWindowWidgetsDataTypes()

  if widgets.disable_all then ImGui.EndDisabled(ctx) end
  DemoWindowWidgetsDisableBlocks()
  if widgets.disable_all then ImGui.BeginDisabled(ctx) end

  DemoWindowWidgetsDragAndDrop()
  DemoWindowWidgetsDragsAndSliders()
  -- DemoWindowWidgetsFonts()
  DemoWindowWidgetsImages()
  DemoWindowWidgetsListBoxes()
  DemoWindowWidgetsMultiComponents()
  DemoWindowWidgetsPlotting()
  DemoWindowWidgetsProgressBars()
  DemoWindowWidgetsQueryingStatuses()
  DemoWindowWidgetsSelectables()
  DemoWindowWidgetsSelectionAndMultiSelect()
  DemoWindowWidgetsTabs()
  DemoWindowWidgetsText()
  DemoWindowWidgetsTextFilter()
  DemoWindowWidgetsTextInput()
  DemoWindowWidgetsTooltips()
  DemoWindowWidgetsTreeNodes()
  DemoWindowWidgetsVerticalSliders()

  if widgets.disable_all then ImGui.EndDisabled(ctx) end
end

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Widgets', true)
  if visible then
    demo.DemoWindowWidgets()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
