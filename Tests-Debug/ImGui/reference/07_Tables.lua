-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Tables
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Tables')
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
-- Contenido de la seccion: Tables
-------------------------------------------------------------------------------

local MyItemColumnID_ID          = 4
local MyItemColumnID_Name        = 5
local MyItemColumnID_Action      = 6
local MyItemColumnID_Quantity    = 7
local MyItemColumnID_Description = 8

function demo.CompareTableItems(a, b)
  for next_id = 0, math.huge do
    local ok, col_idx, col_user_id, sort_direction = ImGui.TableGetColumnSortSpecs(ctx, next_id)
    if not ok then break end

    -- Here we identify columns using the ColumnUserID value that we ourselves passed to TableSetupColumn()
    -- We could also choose to identify columns based on their index (col_idx), which is simpler!
    local key
    if col_user_id == MyItemColumnID_ID then
      key = 'id'
    elseif col_user_id == MyItemColumnID_Name then
      key = 'name'
    elseif col_user_id == MyItemColumnID_Quantity then
      key = 'quantity'
    elseif col_user_id == MyItemColumnID_Description then
      key = 'name'
    else
      error('unknown user column ID')
    end

    local is_ascending = sort_direction == ImGui.SortDirection_Ascending
    if a[key] < b[key] then
      return is_ascending
    elseif a[key] > b[key] then
      return not is_ascending
    end
  end

  -- table.sort is unstable so always return a way to differentiate items.
  -- Your own compare function may want to avoid fallback on implicit sort specs.
  -- e.g. a Name compare if it wasn't already part of the sort specs.
  return a.id < b.id
end

-- Make the UI compact because there are so many fields
function demo.PushStyleCompact()
  local frame_padding_y = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding))
  local item_spacing_y  = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing))
  ImGui.PushStyleVarY(ctx, ImGui.StyleVar_FramePadding, math.floor(frame_padding_y * .60))
  ImGui.PushStyleVarY(ctx, ImGui.StyleVar_ItemSpacing,  math.floor(item_spacing_y  * .60))
end

function demo.PopStyleCompact()
  ImGui.PopStyleVar(ctx, 2)
end

-- Show a combo box with a choice of sizing policies
function demo.EditTableSizingFlags(flags)
  local policies = {
    {
      value   = ImGui.TableFlags_None,
      name    = 'Default',
      tooltip = 'Use default sizing policy:\n- TableFlags_SizingFixedFit if ScrollX is on or if host window has WindowFlags_AlwaysAutoResize.\n- TableFlags_SizingStretchSame otherwise.',
    },
    {
      value   = ImGui.TableFlags_SizingFixedFit,
      name    = 'TableFlags_SizingFixedFit',
      tooltip = 'Columns default to _WidthFixed (if resizable) or _WidthAuto (if not resizable), matching contents width.',
    },
    {
      value   = ImGui.TableFlags_SizingFixedSame,
      name    = 'TableFlags_SizingFixedSame',
      tooltip = 'Columns are all the same width, matching the maximum contents width.\nImplicitly disable TableFlags_Resizable and enable TableFlags_NoKeepColumnsVisible.',
    },
    {
      value   = ImGui.TableFlags_SizingStretchProp,
      name    = 'TableFlags_SizingStretchProp',
      tooltip = 'Columns default to _WidthStretch with weights proportional to their widths.',
    },
    {
      value   = ImGui.TableFlags_SizingStretchSame,
      name    = 'TableFlags_SizingStretchSame',
      tooltip = 'Columns default to _WidthStretch with same weights.',
    },
  }

  local sizing_mask = ImGui.TableFlags_SizingFixedFit    |
                      ImGui.TableFlags_SizingFixedSame   |
                      ImGui.TableFlags_SizingStretchProp |
                      ImGui.TableFlags_SizingStretchSame
  local idx = 1
  while idx < #policies do
    if policies[idx].value == (flags & sizing_mask) then
      break
    end
    idx = idx + 1
  end
  local preview_text = ''
  if idx <= #policies then
    preview_text = policies[idx].name
    if idx > 1 then
      preview_text = preview_text:sub(('TableFlags'):len() + 1)
    end
  end
  if ImGui.BeginCombo(ctx, 'Sizing Policy', preview_text) then
    for n,policy in ipairs(policies) do
      if ImGui.Selectable(ctx, policy.name, idx == n) then
        flags = (flags & ~sizing_mask) | policy.value
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '(?)')
  if ImGui.BeginItemTooltip(ctx) then
    ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 50.0)
    for m,policy in ipairs(policies) do
      ImGui.Separator(ctx)
      ImGui.Text(ctx, ('%s:'):format(policy.name))
      ImGui.Separator(ctx)
      local indent_spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_IndentSpacing)
      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + indent_spacing * 0.5)
      ImGui.Text(ctx, policy.tooltip)
    end
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndTooltip(ctx)
  end

  return flags
end

function demo.EditTableColumnsFlags(flags)
  local rv
  local width_mask = ImGui.TableColumnFlags_WidthStretch |
                     ImGui.TableColumnFlags_WidthFixed

  rv,flags = ImGui.CheckboxFlags(ctx, '_Disabled', flags, ImGui.TableColumnFlags_Disabled); ImGui.SameLine(ctx); demo.HelpMarker('Master disable flag (also hide from context menu)')
  rv,flags = ImGui.CheckboxFlags(ctx, '_DefaultHide', flags, ImGui.TableColumnFlags_DefaultHide)
  rv,flags = ImGui.CheckboxFlags(ctx, '_DefaultSort', flags, ImGui.TableColumnFlags_DefaultSort)
  rv,flags = ImGui.CheckboxFlags(ctx, '_WidthStretch', flags, ImGui.TableColumnFlags_WidthStretch)
  if rv then
    flags = flags & ~(width_mask ~ ImGui.TableColumnFlags_WidthStretch)
  end
  rv,flags = ImGui.CheckboxFlags(ctx, '_WidthFixed', flags, ImGui.TableColumnFlags_WidthFixed)
  if rv then
    flags = flags & ~(width_mask ~ ImGui.TableColumnFlags_WidthFixed)
  end
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoResize', flags, ImGui.TableColumnFlags_NoResize)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoReorder', flags, ImGui.TableColumnFlags_NoReorder)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoHide', flags, ImGui.TableColumnFlags_NoHide)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoClip', flags, ImGui.TableColumnFlags_NoClip)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoSort', flags, ImGui.TableColumnFlags_NoSort)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoSortAscending', flags, ImGui.TableColumnFlags_NoSortAscending)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoSortDescending', flags, ImGui.TableColumnFlags_NoSortDescending)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoHeaderLabel', flags, ImGui.TableColumnFlags_NoHeaderLabel)
  rv,flags = ImGui.CheckboxFlags(ctx, '_NoHeaderWidth', flags, ImGui.TableColumnFlags_NoHeaderWidth)
  rv,flags = ImGui.CheckboxFlags(ctx, '_PreferSortAscending', flags, ImGui.TableColumnFlags_PreferSortAscending)
  rv,flags = ImGui.CheckboxFlags(ctx, '_PreferSortDescending', flags, ImGui.TableColumnFlags_PreferSortDescending)
  rv,flags = ImGui.CheckboxFlags(ctx, '_IndentEnable', flags, ImGui.TableColumnFlags_IndentEnable); ImGui.SameLine(ctx); demo.HelpMarker('Default for column 0')
  rv,flags = ImGui.CheckboxFlags(ctx, '_IndentDisable', flags, ImGui.TableColumnFlags_IndentDisable); ImGui.SameLine(ctx); demo.HelpMarker('Default for column >0')
  rv,flags = ImGui.CheckboxFlags(ctx, '_AngledHeader', flags, ImGui.TableColumnFlags_AngledHeader)

  return flags
end

function demo.ShowTableColumnsStatusFlags(flags)
  ImGui.CheckboxFlags(ctx, '_IsEnabled', flags, ImGui.TableColumnFlags_IsEnabled)
  ImGui.CheckboxFlags(ctx, '_IsVisible', flags, ImGui.TableColumnFlags_IsVisible)
  ImGui.CheckboxFlags(ctx, '_IsSorted',  flags, ImGui.TableColumnFlags_IsSorted)
  ImGui.CheckboxFlags(ctx, '_IsHovered', flags, ImGui.TableColumnFlags_IsHovered)
end

-------------------------------------------------------------------------------
-- [SECTION] DemoWindowTables()
-------------------------------------------------------------------------------

function demo.DemoWindowTables()
  -- ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once)
  if not ImGui.CollapsingHeader(ctx, 'Tables') then return end

  local rv

  -- Using those as a base value to create width/height that are factor of the size of our font
  local TEXT_BASE_WIDTH  = ImGui.CalcTextSize(ctx, 'A')
  local TEXT_BASE_HEIGHT = ImGui.GetTextLineHeightWithSpacing(ctx)

  ImGui.PushID(ctx, 'Tables')

  local open_action
  if ImGui.Button(ctx, 'Expand all') then
    open_action = true
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Collapse all') then
    open_action = false
  end
  ImGui.SameLine(ctx)

  if tables.disable_indent == nil then
    tables.disable_indent = false
  end

  -- Options
  rv,tables.disable_indent = ImGui.Checkbox(ctx, 'Disable tree indentation', tables.disable_indent)
  ImGui.SameLine(ctx)
  demo.HelpMarker('Disable the indenting of tree nodes so demo tables can use the full window width.')
  ImGui.Separator(ctx)
  if tables.disable_indent then
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_IndentSpacing, 0.0)
  end

  -- About Styling of tables
  -- Most settings are configured on a per-table basis via the flags passed to BeginTable() and TableSetupColumns APIs.
  -- There are however a few settings that a shared and accessible via PushStyle{Color,Var}
  --   StyleVar_CellPadding    // Padding within each cell
  --   Col_TableHeaderBg       // Table header background
  --   Col_TableBorderStrong   // Table outer and header borders
  --   Col_TableBorderLight    // Table inner borders
  --   Col_TableRowBg          // Table row background when TableFlags_RowBg is enabled (even rows)
  --   Col_TableRowBgAlt       // Table row background when TableFlags_RowBg is enabled (odds rows)

  local function DoOpenAction()
    if open_action ~= nil then
      ImGui.SetNextItemOpen(ctx, open_action)
    end
  end

  -- Demos
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Basic') then
    -- Here we will showcase three different ways to output a table.
    -- They are very simple variations of a same thing!

    -- [Method 1] Using TableNextRow() to create a new row, and TableSetColumnIndex() to select the column.
    -- In many situations, this is the most flexible and easy to use pattern.
    demo.HelpMarker('Using TableNextRow() + calling TableSetColumnIndex() _before_ each cell, in a loop.')
    if ImGui.BeginTable(ctx, 'table1', 3) then
      for row = 0, 3 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Row %d Column %d'):format(row, column))
        end
      end
      ImGui.EndTable(ctx)
    end

    -- [Method 2] Using TableNextColumn() called multiple times, instead of using a for loop + TableSetColumnIndex().
    -- This is generally more convenient when you have code manually submitting the contents of each column.
    demo.HelpMarker('Using TableNextRow() + calling TableNextColumn() _before_ each cell, manually.')
    if ImGui.BeginTable(ctx, 'table2', 3) then
      for row = 0, 3 do
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, ('Row %d'):format(row))
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, 'Some contents')
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, '123.456')
      end
      ImGui.EndTable(ctx)
    end

    -- [Method 3] We call TableNextColumn() _before_ each cell. We never call TableNextRow(),
    -- as TableNextColumn() will automatically wrap around and create new rows as needed.
    -- This is generally more convenient when your cells all contains the same type of data.
    demo.HelpMarker(
      'Only using TableNextColumn(), which tends to be convenient for tables where every cell contains \z
       the same type of contents.\nThis is also more similar to the old NextColumn() function of the \z
       Columns API, and provided to facilitate the Columns->Tables API transition.')
    if ImGui.BeginTable(ctx, 'table3', 3) then
      for item = 0, 13 do
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, ('Item %d'):format(item))
      end
      ImGui.EndTable(ctx)
    end

    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Borders, background') then
    if not tables.borders_bg then
      tables.borders_bg = {
        flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg,
        display_headers = false,
        contents_type = 0,
      }
    end
    -- Expose a few Borders related flags interactively

    demo.PushStyleCompact()
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_RowBg', tables.borders_bg.flags, ImGui.TableFlags_RowBg)
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Borders', tables.borders_bg.flags, ImGui.TableFlags_Borders)
    ImGui.SameLine(ctx); demo.HelpMarker('TableFlags_Borders\n = TableFlags_BordersInnerV\n | TableFlags_BordersOuterV\n | TableFlags_BordersInnerH\n | TableFlags_BordersOuterH')
    ImGui.Indent(ctx)

    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersH', tables.borders_bg.flags, ImGui.TableFlags_BordersH)
    ImGui.Indent(ctx)
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuterH', tables.borders_bg.flags, ImGui.TableFlags_BordersOuterH)
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInnerH', tables.borders_bg.flags, ImGui.TableFlags_BordersInnerH)
    ImGui.Unindent(ctx)

    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersV', tables.borders_bg.flags, ImGui.TableFlags_BordersV)
    ImGui.Indent(ctx)
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuterV', tables.borders_bg.flags, ImGui.TableFlags_BordersOuterV)
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInnerV', tables.borders_bg.flags, ImGui.TableFlags_BordersInnerV)
    ImGui.Unindent(ctx)

    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuter', tables.borders_bg.flags, ImGui.TableFlags_BordersOuter)
    rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInner', tables.borders_bg.flags, ImGui.TableFlags_BordersInner)
    ImGui.Unindent(ctx)

    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, 'Cell contents:')
    ImGui.SameLine(ctx); rv,tables.borders_bg.contents_type = ImGui.RadioButtonEx(ctx, 'Text', tables.borders_bg.contents_type, 0)
    ImGui.SameLine(ctx); rv,tables.borders_bg.contents_type = ImGui.RadioButtonEx(ctx, 'FillButton', tables.borders_bg.contents_type, 1)
    rv,tables.borders_bg.display_headers = ImGui.Checkbox(ctx, 'Display headers', tables.borders_bg.display_headers)
    -- rv,tables.borders_bg.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoBordersInBody', tables.borders_bg.flags, ImGui.TableFlags_NoBordersInBody()); ImGui.SameLine(ctx); demo.HelpMarker('Disable vertical borders in columns Body (borders will always appear in Headers')
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table1', 3, tables.borders_bg.flags) then
      -- Display headers so we can inspect their interaction with borders
      -- (Headers are not the main purpose of this section of the demo, so we are not elaborating on them now. See other sections for details)
      if tables.borders_bg.display_headers then
        ImGui.TableSetupColumn(ctx, 'One')
        ImGui.TableSetupColumn(ctx, 'Two')
        ImGui.TableSetupColumn(ctx, 'Three')
        ImGui.TableHeadersRow(ctx)
      end

      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          local buf = ('Hello %d,%d'):format(column, row)
          if tables.borders_bg.contents_type == 0 then
            ImGui.Text(ctx, buf)
          elseif tables.borders_bg.contents_type == 1 then
            ImGui.Button(ctx, buf, -FLT_MIN, 0.0)
          end
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Resizable, stretch') then
    if not tables.resz_stretch then
      tables.resz_stretch = {
        flags = ImGui.TableFlags_SizingStretchSame |
                ImGui.TableFlags_Resizable |
                ImGui.TableFlags_BordersOuter |
                ImGui.TableFlags_BordersV |
                ImGui.TableFlags_ContextMenuInBody,
      }
    end

    -- By default, if we don't enable ScrollX the sizing policy for each column is "Stretch"
    -- All columns maintain a sizing weight, and they will occupy all available width.
    demo.PushStyleCompact()
    rv,tables.resz_stretch.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.resz_stretch.flags, ImGui.TableFlags_Resizable)
    rv,tables.resz_stretch.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersV',  tables.resz_stretch.flags, ImGui.TableFlags_BordersV)
    ImGui.SameLine(ctx); demo.HelpMarker(
      'Using the _Resizable flag automatically enables the _BordersInnerV flag as well, \z
       this is why the resize borders are still showing when unchecking this.')
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table1', 3, tables.resz_stretch.flags) then
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Hello %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Resizable, fixed') then
    if not tables.resz_fixed then
      tables.resz_fixed = {
        flags = ImGui.TableFlags_SizingFixedFit |
                ImGui.TableFlags_Resizable |
                ImGui.TableFlags_BordersOuter |
                ImGui.TableFlags_BordersV |
                ImGui.TableFlags_ContextMenuInBody,
      }
    end

    -- Here we use TableFlags_SizingFixedFit (even though _ScrollX is not set)
    -- So columns will adopt the "Fixed" policy and will maintain a fixed width regardless of the whole available width (unless table is small)
    -- If there is not enough available width to fit all columns, they will however be resized down.
    -- FIXME-TABLE: Providing a stretch-on-init would make sense especially for tables which don't have saved settings
    demo.HelpMarker(
      'Using _Resizable + _SizingFixedFit flags.\n\z
       Fixed-width columns generally makes more sense if you want to use horizontal scrolling.\n\n\z
       Double-click a column border to auto-fit the column to its contents.')
    demo.PushStyleCompact()
    rv,tables.resz_fixed.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoHostExtendX', tables.resz_fixed.flags, ImGui.TableFlags_NoHostExtendX)
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table1', 3, tables.resz_fixed.flags) then
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Hello %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, "Resizable, mixed") then
    if not tables.resz_mixed then
      tables.resz_mixed = {
        flags = ImGui.TableFlags_SizingFixedFit |
                ImGui.TableFlags_RowBg | ImGui.TableFlags_Borders |
                ImGui.TableFlags_Resizable |
                ImGui.TableFlags_Reorderable | ImGui.TableFlags_Hideable
      }
    end
    demo.HelpMarker(
      'Using TableSetupColumn() to alter resizing policy on a per-column basis.\n\n\z
       When combining Fixed and Stretch columns, generally you only want one, maybe two trailing columns to use _WidthStretch.')

    if ImGui.BeginTable(ctx, 'table1', 3, tables.resz_mixed.flags) then
      ImGui.TableSetupColumn(ctx, 'AAA', ImGui.TableColumnFlags_WidthFixed)
      ImGui.TableSetupColumn(ctx, 'BBB', ImGui.TableColumnFlags_WidthFixed)
      ImGui.TableSetupColumn(ctx, 'CCC', ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableHeadersRow(ctx)
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('%s %d,%d'):format(column == 2 and 'Stretch' or 'Fixed', column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    if ImGui.BeginTable(ctx, 'table2', 6, tables.resz_mixed.flags) then
      ImGui.TableSetupColumn(ctx, 'AAA', ImGui.TableColumnFlags_WidthFixed)
      ImGui.TableSetupColumn(ctx, 'BBB', ImGui.TableColumnFlags_WidthFixed)
      ImGui.TableSetupColumn(ctx, 'CCC', ImGui.TableColumnFlags_WidthFixed | ImGui.TableColumnFlags_DefaultHide)
      ImGui.TableSetupColumn(ctx, 'DDD', ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, 'EEE', ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, 'FFF', ImGui.TableColumnFlags_WidthStretch | ImGui.TableColumnFlags_DefaultHide)
      ImGui.TableHeadersRow(ctx)
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 5 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('%s %d,%d'):format(column >= 3 and 'Stretch' or 'Fixed', column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Reorderable, hideable, with headers') then
    if not tables.reorder then
      tables.reorder = {
        flags = ImGui.TableFlags_Resizable |
                ImGui.TableFlags_Reorderable |
                ImGui.TableFlags_Hideable |
                ImGui.TableFlags_BordersOuter |
                ImGui.TableFlags_BordersV
      }
    end

    demo.HelpMarker(
      'Click and drag column headers to reorder columns.\n\n\z
       Right-click on a header to open a context menu.')
    demo.PushStyleCompact()
    rv,tables.reorder.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.reorder.flags, ImGui.TableFlags_Resizable)
    rv,tables.reorder.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Reorderable', tables.reorder.flags, ImGui.TableFlags_Reorderable)
    rv,tables.reorder.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Hideable', tables.reorder.flags, ImGui.TableFlags_Hideable)
    -- rv,tables.reorder.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoBordersInBody', tables.reorder.flags, ImGui.TableFlags_NoBordersInBody())
    -- rv,tables.reorder.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoBordersInBodyUntilResize', tables.reorder.flags, ImGui.TableFlags_NoBordersInBodyUntilResize()); ImGui.SameLine(ctx); demo.HelpMarker('Disable vertical borders in columns Body until hovered for resize (borders will always appear in Headers)')
    rv,tables.reorder.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_HighlightHoveredColumn', tables.reorder.flags, ImGui.TableFlags_HighlightHoveredColumn)
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table1', 3, tables.reorder.flags) then
      -- Submit column names with TableSetupColumn() and call TableHeadersRow() to create a row with a header in each column.
      -- (Later we will show how TableSetupColumn() has other uses, optional flags, sizing weight etc.)
      ImGui.TableSetupColumn(ctx, 'One')
      ImGui.TableSetupColumn(ctx, 'Two')
      ImGui.TableSetupColumn(ctx, 'Three')
      ImGui.TableHeadersRow(ctx)
      for row = 0, 5 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Hello %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end

    -- Use outer_size.x == 0.0 instead of default to make the table as tight as possible
    -- (only valid when no scrolling and no stretch column)
    if ImGui.BeginTable(ctx, 'table2', 3, tables.reorder.flags | ImGui.TableFlags_SizingFixedFit, 0.0, 0.0) then
      ImGui.TableSetupColumn(ctx, 'One')
      ImGui.TableSetupColumn(ctx, 'Two')
      ImGui.TableSetupColumn(ctx, 'Three')
      ImGui.TableHeadersRow(ctx)
      for row = 0, 5 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Fixed %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Padding') then
    if not tables.padding then
      tables.padding = {
        flags1 = ImGui.TableFlags_BordersV,
        show_headers = false,

        flags2 = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg,
        cell_padding = {0.0, 0.0},
        show_widget_frame_bg = true,
        text_bufs = {}, -- Mini text storage for 3x5 cells
      }

      for i = 1, 3*5 do
        tables.padding.text_bufs[i] = 'edit me'
      end
    end

    -- First example: showcase use of padding flags and effect of BorderOuterV/BorderInnerV on X padding.
    -- We don't expose BorderOuterH/BorderInnerH here because they have no effect on X padding.
    demo.HelpMarker(
      "We often want outer padding activated when any using features which makes the edges of a column visible:\n\z
       e.g.:\n\z
       - BorderOuterV\n\z
       - any form of row selection\n\z
       Because of this, activating BorderOuterV sets the default to PadOuterX. \z
       Using PadOuterX or NoPadOuterX you can override the default.\n\n\z
       Actual padding values are using style.CellPadding.\n\n\z
       In this demo we don't show horizontal borders to emphasize how they don't affect default horizontal padding.")

    demo.PushStyleCompact()
    rv,tables.padding.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_PadOuterX', tables.padding.flags1, ImGui.TableFlags_PadOuterX)
    ImGui.SameLine(ctx); demo.HelpMarker('Enable outer-most padding (default if TableFlags_BordersOuterV is set)')
    rv,tables.padding.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_NoPadOuterX', tables.padding.flags1, ImGui.TableFlags_NoPadOuterX)
    ImGui.SameLine(ctx); demo.HelpMarker('Disable outer-most padding (default if TableFlags_BordersOuterV is not set)')
    rv,tables.padding.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_NoPadInnerX', tables.padding.flags1, ImGui.TableFlags_NoPadInnerX)
    ImGui.SameLine(ctx); demo.HelpMarker('Disable inner padding between columns (double inner padding if BordersOuterV is on, single inner padding if BordersOuterV is off)')
    rv,tables.padding.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuterV', tables.padding.flags1, ImGui.TableFlags_BordersOuterV)
    rv,tables.padding.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInnerV', tables.padding.flags1, ImGui.TableFlags_BordersInnerV)
    rv,tables.padding.show_headers = ImGui.Checkbox(ctx, 'show_headers', tables.padding.show_headers)
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table_padding', 3, tables.padding.flags1) then
      if tables.padding.show_headers then
        ImGui.TableSetupColumn(ctx, 'One')
        ImGui.TableSetupColumn(ctx, 'Two')
        ImGui.TableSetupColumn(ctx, 'Three')
        ImGui.TableHeadersRow(ctx)
      end

      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          if row == 0 then
            ImGui.Text(ctx, ('Avail %.2f'):format(ImGui.GetContentRegionAvail(ctx)))
          else
            local buf = ('Hello %d,%d'):format(column, row)
            ImGui.Button(ctx, buf, -FLT_MIN, 0.0)
          end
          --if (ImGui.TableGetColumnFlags() & TableColumnFlags_IsHovered)
          --  ImGui.TableSetBgColor(TableBgTarget_CellBg, IM_COL32(0, 100, 0, 255))
        end
      end
      ImGui.EndTable(ctx)
    end

    -- Second example: set style.CellPadding to (0.0) or a custom value.
    -- FIXME-TABLE: Vertical border effectively not displayed the same way as horizontal one...
    demo.HelpMarker('Setting style.CellPadding to (0,0) or a custom value.')

    demo.PushStyleCompact()
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_Borders', tables.padding.flags2, ImGui.TableFlags_Borders)
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersH', tables.padding.flags2, ImGui.TableFlags_BordersH)
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersV', tables.padding.flags2, ImGui.TableFlags_BordersV)
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInner', tables.padding.flags2, ImGui.TableFlags_BordersInner)
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuter', tables.padding.flags2, ImGui.TableFlags_BordersOuter)
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_RowBg', tables.padding.flags2, ImGui.TableFlags_RowBg)
    rv,tables.padding.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.padding.flags2, ImGui.TableFlags_Resizable)
    rv,tables.padding.show_widget_frame_bg = ImGui.Checkbox(ctx, 'show_widget_frame_bg', tables.padding.show_widget_frame_bg)
    rv,tables.padding.cell_padding[1],tables.padding.cell_padding[2] =
      ImGui.SliderDouble2(ctx, 'CellPadding', tables.padding.cell_padding[1],
      tables.padding.cell_padding[2], 0.0, 10.0, '%.0f')
    demo.PopStyleCompact()

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_CellPadding, table.unpack(tables.padding.cell_padding))
    if ImGui.BeginTable(ctx, 'table_padding_2', 3, tables.padding.flags2) then
      if not tables.padding.show_widget_frame_bg then
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0)
      end
      for cell = 1, 3 * 5 do
        ImGui.TableNextColumn(ctx)
        ImGui.SetNextItemWidth(ctx, -FLT_MIN)
        ImGui.PushID(ctx, cell)
        rv,tables.padding.text_bufs[cell] = ImGui.InputText(ctx, '##cell', tables.padding.text_bufs[cell])
        ImGui.PopID(ctx)
      end
      if not tables.padding.show_widget_frame_bg then
        ImGui.PopStyleColor(ctx)
      end
      ImGui.EndTable(ctx)
    end
    ImGui.PopStyleVar(ctx)

    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Sizing policies') then
    if not tables.sz_policies then
      tables.sz_policies = {
        flags1 = ImGui.TableFlags_BordersV      |
                 ImGui.TableFlags_BordersOuterH |
                 ImGui.TableFlags_RowBg         |
                 ImGui.TableFlags_ContextMenuInBody,
        sizing_policy_flags = {
          ImGui.TableFlags_SizingFixedFit,
          ImGui.TableFlags_SizingFixedSame,
          ImGui.TableFlags_SizingStretchProp,
          ImGui.TableFlags_SizingStretchSame,
        },

        flags2 = ImGui.TableFlags_ScrollY |
                 ImGui.TableFlags_Borders |
                 ImGui.TableFlags_RowBg   |
                 ImGui.TableFlags_Resizable,
        contents_type = 0,
        column_count  = 3,
        text_buf      = '',
      }
    end

    demo.PushStyleCompact()
    rv,tables.sz_policies.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.sz_policies.flags1, ImGui.TableFlags_Resizable)
    rv,tables.sz_policies.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_NoHostExtendX', tables.sz_policies.flags1, ImGui.TableFlags_NoHostExtendX)
    demo.PopStyleCompact()

    for table_n,sizing_flags in ipairs(tables.sz_policies.sizing_policy_flags) do
      ImGui.PushID(ctx, table_n)
      ImGui.SetNextItemWidth(ctx, TEXT_BASE_WIDTH * 30)
      sizing_flags = demo.EditTableSizingFlags(sizing_flags)
      tables.sz_policies.sizing_policy_flags[table_n] = sizing_flags

      -- To make it easier to understand the different sizing policy,
      -- For each policy: we display one table where the columns have equal contents width,
      -- and one where the columns have different contents width.
      if ImGui.BeginTable(ctx, 'table1', 3, sizing_flags | tables.sz_policies.flags1) then
        for row = 0, 2 do
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Oh dear')
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Oh dear')
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Oh dear')
        end
        ImGui.EndTable(ctx)
      end
      if ImGui.BeginTable(ctx, 'table2', 3, sizing_flags | tables.sz_policies.flags1) then
        for row = 0, 2 do
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'AAAA')
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'BBBBBBBB')
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'CCCCCCCCCCCC')
        end
        ImGui.EndTable(ctx)
      end
      ImGui.PopID(ctx)
    end

    ImGui.Spacing(ctx)
    ImGui.Text(ctx, 'Advanced')
    ImGui.SameLine(ctx)
    demo.HelpMarker(
      'This section allows you to interact and see the effect of various sizing policies \z
       depending on whether Scroll is enabled and the contents of your columns.')

    demo.PushStyleCompact()
    ImGui.PushID(ctx, 'Advanced')
    ImGui.PushItemWidth(ctx, TEXT_BASE_WIDTH * 30)
    tables.sz_policies.flags2 = demo.EditTableSizingFlags(tables.sz_policies.flags2)
    rv,tables.sz_policies.contents_type = ImGui.Combo(ctx, 'Contents', tables.sz_policies.contents_type, 'Show width\0Short Text\0Long Text\0Button\0Fill Button\0InputText\0')
    if tables.sz_policies.contents_type == 4 then -- fill button
      ImGui.SameLine(ctx)
      demo.HelpMarker(
        'Be mindful that using right-alignment (e.g. size.x = -FLT_MIN) creates a feedback loop \z
         where contents width can feed into auto-column width can feed into contents width.')
    end
    rv,tables.sz_policies.column_count = ImGui.DragInt(ctx, 'Columns', tables.sz_policies.column_count, 0.1, 1, 64, '%d', ImGui.SliderFlags_AlwaysClamp)
    rv,tables.sz_policies.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.sz_policies.flags2, ImGui.TableFlags_Resizable)
    rv,tables.sz_policies.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_PreciseWidths', tables.sz_policies.flags2, ImGui.TableFlags_PreciseWidths)
    ImGui.SameLine(ctx); demo.HelpMarker('Disable distributing remainder width to stretched columns (width allocation on a 100-wide table with 3 columns: Without this flag: 33,33,34. With this flag: 33,33,33). With larger number of columns, resizing will appear to be less smooth.')
    rv,tables.sz_policies.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollX', tables.sz_policies.flags2, ImGui.TableFlags_ScrollX)
    rv,tables.sz_policies.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollY', tables.sz_policies.flags2, ImGui.TableFlags_ScrollY)
    rv,tables.sz_policies.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_NoClip', tables.sz_policies.flags2, ImGui.TableFlags_NoClip)
    ImGui.PopItemWidth(ctx)
    ImGui.PopID(ctx)
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table2', tables.sz_policies.column_count, tables.sz_policies.flags2, 0.0, TEXT_BASE_HEIGHT * 7) then
      for cell = 1, 10 * tables.sz_policies.column_count do
        ImGui.TableNextColumn(ctx)
        local column = ImGui.TableGetColumnIndex(ctx)
        local row = ImGui.TableGetRowIndex(ctx)

        ImGui.PushID(ctx, cell)
        local label = ('Hello %d,%d'):format(column, row)
        local contents_type = tables.sz_policies.contents_type
        if contents_type == 1 then -- short text
          ImGui.Text(ctx, label)
        elseif contents_type == 2 then -- long text
          ImGui.Text(ctx, ('Some %s text %d,%d\nOver two lines..'):format(column == 0 and 'long' or 'longeeer', column, row))
        elseif contents_type == 0 then -- show width
          ImGui.Text(ctx, ('W: %.1f'):format(ImGui.GetContentRegionAvail(ctx)))
        elseif contents_type == 3 then -- button
          ImGui.Button(ctx, label)
        elseif contents_type == 4 then -- fill button
          ImGui.Button(ctx, label, -FLT_MIN, 0.0)
        elseif contents_type == 5 then -- input text
          ImGui.SetNextItemWidth(ctx, -FLT_MIN)
          rv,tables.sz_policies.text_buf = ImGui.InputText(ctx, '##', tables.sz_policies.text_buf)
        end
        ImGui.PopID(ctx)
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Vertical scrolling, with clipping') then
    if not tables.vertical then
      tables.vertical = {
        flags = ImGui.TableFlags_ScrollY      |
                ImGui.TableFlags_RowBg        |
                ImGui.TableFlags_BordersOuter |
                ImGui.TableFlags_BordersV     |
                ImGui.TableFlags_Resizable    |
                ImGui.TableFlags_Reorderable  |
                ImGui.TableFlags_Hideable,
      }
    end

    demo.HelpMarker(
      'Here we activate ScrollY, which will create a child window container to allow hosting scrollable contents.\n\n\z
       We also demonstrate using ListClipper to virtualize the submission of many items.')

    demo.PushStyleCompact()
    rv,tables.vertical.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollY', tables.vertical.flags, ImGui.TableFlags_ScrollY)
    demo.PopStyleCompact()

    -- When using ScrollX or ScrollY we need to specify a size for our table container!
    -- Otherwise by default the table will fit all available space, like a BeginChild() call.
    local clipper = {}
    local outer_size_w, outer_size_h = 0.0, TEXT_BASE_HEIGHT * 8
    if ImGui.BeginTable(ctx, 'table_scrolly', 3, tables.vertical.flags, outer_size_w, outer_size_h) then
      ImGui.TableSetupScrollFreeze(ctx, 0, 1); -- Make top row always visible
      ImGui.TableSetupColumn(ctx, 'One', ImGui.TableColumnFlags_None)
      ImGui.TableSetupColumn(ctx, 'Two', ImGui.TableColumnFlags_None)
      ImGui.TableSetupColumn(ctx, 'Three', ImGui.TableColumnFlags_None)
      ImGui.TableHeadersRow(ctx)

      -- Demonstrate using clipper for large vertical lists
      ImGui.ListClipper_Begin(clipper, 1000)
      while ImGui.ListClipper_Step(clipper) do
        local display_start, display_end = ImGui.ListClipper_GetDisplayRange(clipper)
        for row = display_start, display_end - 1 do
          ImGui.TableNextRow(ctx)
          for column = 0, 2 do
            ImGui.TableSetColumnIndex(ctx, column)
            ImGui.Text(ctx, ('Hello %d,%d'):format(column, row))
          end
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Horizontal scrolling') then
    if not tables.horizontal then
      tables.horizontal = {
        flags1 = ImGui.TableFlags_ScrollX      |
                 ImGui.TableFlags_ScrollY      |
                 ImGui.TableFlags_RowBg        |
                 ImGui.TableFlags_BordersOuter |
                 ImGui.TableFlags_BordersV     |
                 ImGui.TableFlags_Resizable    |
                 ImGui.TableFlags_Reorderable  |
                 ImGui.TableFlags_Hideable,
        freeze_cols = 1,
        freeze_rows = 1,

        flags2 = ImGui.TableFlags_SizingStretchSame |
                 ImGui.TableFlags_ScrollX           |
                 ImGui.TableFlags_ScrollY           |
                 ImGui.TableFlags_BordersOuter      |
                 ImGui.TableFlags_RowBg             |
                 ImGui.TableFlags_ContextMenuInBody,
        inner_width = 1000.0,
      }
    end

    demo.HelpMarker(
      "When ScrollX is enabled, the default sizing policy becomes TableFlags_SizingFixedFit, \z
       as automatically stretching columns doesn't make much sense with horizontal scrolling.\n\n\z
       Also note that as of the current version, you will almost always want to enable ScrollY along with ScrollX, \z
       because the container window won't automatically extend vertically to fix contents \z
       (this may be improved in future versions).")

    demo.PushStyleCompact()
    rv,tables.horizontal.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.horizontal.flags1, ImGui.TableFlags_Resizable)
    rv,tables.horizontal.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollX', tables.horizontal.flags1, ImGui.TableFlags_ScrollX)
    rv,tables.horizontal.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollY', tables.horizontal.flags1, ImGui.TableFlags_ScrollY)
    ImGui.SetNextItemWidth(ctx, ImGui.GetFrameHeight(ctx))
    rv,tables.horizontal.freeze_cols = ImGui.DragInt(ctx, 'freeze_cols', tables.horizontal.freeze_cols, 0.2, 0, 9, nil, ImGui.SliderFlags_NoInput)
    ImGui.SetNextItemWidth(ctx, ImGui.GetFrameHeight(ctx))
    rv,tables.horizontal.freeze_rows = ImGui.DragInt(ctx, 'freeze_rows', tables.horizontal.freeze_rows, 0.2, 0, 9, nil, ImGui.SliderFlags_NoInput)
    demo.PopStyleCompact()

    -- When using ScrollX or ScrollY we need to specify a size for our table container!
    -- Otherwise by default the table will fit all available space, like a BeginChild() call.
    local outer_size_w, outer_size_h = 0.0, TEXT_BASE_HEIGHT * 8
    if ImGui.BeginTable(ctx, 'table_scrollx', 7, tables.horizontal.flags1, outer_size_w, outer_size_h) then
      ImGui.TableSetupScrollFreeze(ctx, tables.horizontal.freeze_cols, tables.horizontal.freeze_rows)
      ImGui.TableSetupColumn(ctx, 'Line #', ImGui.TableColumnFlags_NoHide) -- Make the first column not hideable to match our use of TableSetupScrollFreeze()
      ImGui.TableSetupColumn(ctx, 'One')
      ImGui.TableSetupColumn(ctx, 'Two')
      ImGui.TableSetupColumn(ctx, 'Three')
      ImGui.TableSetupColumn(ctx, 'Four')
      ImGui.TableSetupColumn(ctx, 'Five')
      ImGui.TableSetupColumn(ctx, 'Six')
      ImGui.TableHeadersRow(ctx)
      for row = 0, 19 do
        ImGui.TableNextRow(ctx)
        for column = 0, 6 do
          -- Both TableNextColumn() and TableSetColumnIndex() return true when a column is visible or performing width measurement.
          -- Because here we know that:
          -- - A) all our columns are contributing the same to row height
          -- - B) column 0 is always visible,
          -- We only always submit this one column and can skip others.
          -- More advanced per-column clipping behaviors may benefit from polling the status flags via TableGetColumnFlags().
          if ImGui.TableSetColumnIndex(ctx, column) or column == 0 then
            if column == 0 then
              ImGui.Text(ctx, ('Line %d'):format(row))
            else
              ImGui.Text(ctx, ('Hello world %d,%d'):format(column, row))
            end
          end
        end
      end
      ImGui.EndTable(ctx)
    end

    ImGui.Spacing(ctx)
    ImGui.Text(ctx, 'Stretch + ScrollX')
    ImGui.SameLine(ctx)
    demo.HelpMarker(
      "Showcase using Stretch columns + ScrollX together: \z
       this is rather unusual and only makes sense when specifying an 'inner_width' for the table!\n\z
       Without an explicit value, inner_width is == outer_size_w and therefore using Stretch columns \z
       along with ScrollX doesn't make sense.")
    demo.PushStyleCompact()
    ImGui.PushID(ctx, 'flags3')
    ImGui.PushItemWidth(ctx, TEXT_BASE_WIDTH * 30)
    rv,tables.horizontal.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollX', tables.horizontal.flags2, ImGui.TableFlags_ScrollX)
    rv,tables.horizontal.inner_width = ImGui.DragDouble(ctx, 'inner_width', tables.horizontal.inner_width, 1.0, 0.0, FLT_MAX, '%.1f')
    ImGui.PopItemWidth(ctx)
    ImGui.PopID(ctx)
    demo.PopStyleCompact()
    if ImGui.BeginTable(ctx, 'table2', 7, tables.horizontal.flags2, outer_size_w, outer_size_h, tables.horizontal.inner_width) then
      for cell = 1, 20 * 7 do
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, ('Hello world %d,%d'):format(ImGui.TableGetColumnIndex(ctx), ImGui.TableGetRowIndex(ctx)))
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Columns flags') then
    if not tables.col_flags then
      tables.col_flags = {
        columns = {
          {name='One',   flags=ImGui.TableColumnFlags_DefaultSort, flags_out=0},
          {name='Two',   flags=ImGui.TableColumnFlags_None,        flags_out=0},
          {name='Three', flags=ImGui.TableColumnFlags_DefaultHide, flags_out=0},
        },
      }
    end

    -- Create a first table just to show all the options/flags we want to make visible in our example!
    if ImGui.BeginTable(ctx, 'table_columns_flags_checkboxes', #tables.col_flags.columns, ImGui.TableFlags_None) then
      demo.PushStyleCompact()
      for i,column in ipairs(tables.col_flags.columns) do
        ImGui.TableNextColumn(ctx)
        ImGui.PushID(ctx, i)
        ImGui.AlignTextToFramePadding(ctx) -- FIXME-TABLE: Workaround for wrong text baseline propagation across columns
        ImGui.Text(ctx, ("'%s'"):format(column.name))
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Input flags:')
        column.flags = demo.EditTableColumnsFlags(column.flags)
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Output flags:')
        ImGui.BeginDisabled(ctx)
        demo.ShowTableColumnsStatusFlags(column.flags_out)
        ImGui.EndDisabled(ctx)
        ImGui.PopID(ctx)
      end
      demo.PopStyleCompact()
      ImGui.EndTable(ctx)
    end

    -- Create the real table we care about for the example!
    -- We use a scrolling table to be able to showcase the difference between the _IsEnabled and _IsVisible flags above,
    -- otherwise in a non-scrolling table columns are always visible (unless using TableFlags_NoKeepColumnsVisible
    -- + resizing the parent window down).
    local flags = ImGui.TableFlags_SizingFixedFit |
                  ImGui.TableFlags_ScrollX        |
                  ImGui.TableFlags_ScrollY        |
                  ImGui.TableFlags_RowBg          |
                  ImGui.TableFlags_BordersOuter   |
                  ImGui.TableFlags_BordersV       |
                  ImGui.TableFlags_Resizable      |
                  ImGui.TableFlags_Reorderable    |
                  ImGui.TableFlags_Hideable       |
                  ImGui.TableFlags_Sortable
    local outer_size_w, outer_size_h = 0.0, TEXT_BASE_HEIGHT * 9
    if ImGui.BeginTable(ctx, 'table_columns_flags', #tables.col_flags.columns, flags, outer_size_w, outer_size_h) then
      local has_angled_header = false
      for i,column in ipairs(tables.col_flags.columns) do
        if (column.flags & ImGui.TableColumnFlags_AngledHeader) ~= 0 then has_angled_header = true end
        ImGui.TableSetupColumn(ctx, column.name, column.flags)
      end
      if has_angled_header then
        ImGui.TableAngledHeadersRow(ctx)
      end
      ImGui.TableHeadersRow(ctx)
      for i,column in ipairs(tables.col_flags.columns) do
        column.flags_out = ImGui.TableGetColumnFlags(ctx, i - 1)
      end
      local indent_step = TEXT_BASE_WIDTH / 2
      for row = 0, 7 do
        -- Add some indentation to demonstrate usage of per-column IndentEnable/IndentDisable flags.
        ImGui.Indent(ctx, indent_step)
        ImGui.TableNextRow(ctx)
        for column = 0, #tables.col_flags.columns - 1 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('%s %s'):format(column == 0 and 'Indented' or 'Hello', ImGui.TableGetColumnName(ctx, column)))
        end
      end
      ImGui.Unindent(ctx, indent_step * 8.0)

      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Columns widths') then
    if not tables.col_widths then
      tables.col_widths = {
        flags1 = ImGui.TableFlags_Borders, --|
                 -- ImGui.TableFlags_NoBordersInBodyUntilResize(),
        flags2 = ImGui.TableFlags_None,
      }
    end
    demo.HelpMarker('Using TableSetupColumn() to setup default width.')

    demo.PushStyleCompact()
    rv,tables.col_widths.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.col_widths.flags1, ImGui.TableFlags_Resizable)
    -- rv,tables.col_widths.flags1 = ImGui.CheckboxFlags(ctx, TableFlags_NoBordersInBodyUntilResize', tables.col_widths.flags1, ImGui.TableFlags_NoBordersInBodyUntilResize())
    demo.PopStyleCompact()
    if ImGui.BeginTable(ctx, 'table1', 3, tables.col_widths.flags1) then
      -- We could also set TableFlags_SizingFixedFit on the table and then all columns
      -- will default to TableColumnFlags_WidthFixed.
      ImGui.TableSetupColumn(ctx, 'one', ImGui.TableColumnFlags_WidthFixed, 100.0) -- Default to 100.0
      ImGui.TableSetupColumn(ctx, 'two', ImGui.TableColumnFlags_WidthFixed, 200.0) -- Default to 200.0
      ImGui.TableSetupColumn(ctx, 'three', ImGui.TableColumnFlags_WidthFixed);     -- Default to auto
      ImGui.TableHeadersRow(ctx)
      for row = 0, 3 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableSetColumnIndex(ctx, column)
          if row == 0 then
            ImGui.Text(ctx, ('(w: %5.1f)'):format(ImGui.GetContentRegionAvail(ctx)))
          else
            ImGui.Text(ctx, ('Hello %d,%d'):format(column, row))
          end
        end
      end
      ImGui.EndTable(ctx)
    end

    demo.HelpMarker("Using TableSetupColumn() to setup explicit width.\n\nUnless _NoKeepColumnsVisible is set, fixed columns with set width may still be shrunk down if there's not enough space in the host.")

    demo.PushStyleCompact()
    rv,tables.col_widths.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_NoKeepColumnsVisible', tables.col_widths.flags2, ImGui.TableFlags_NoKeepColumnsVisible)
    rv,tables.col_widths.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInnerV', tables.col_widths.flags2, ImGui.TableFlags_BordersInnerV)
    rv,tables.col_widths.flags2 = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuterV', tables.col_widths.flags2, ImGui.TableFlags_BordersOuterV)
    demo.PopStyleCompact()
    if ImGui.BeginTable(ctx, 'table2', 4, tables.col_widths.flags2) then
      -- We could also set TableFlags_SizingFixedFit on the table and all columns will default to TableColumnFlags_WidthFixed.
      ImGui.TableSetupColumn(ctx, '', ImGui.TableColumnFlags_WidthFixed, 100.0)
      ImGui.TableSetupColumn(ctx, '', ImGui.TableColumnFlags_WidthFixed, TEXT_BASE_WIDTH * 15.0)
      ImGui.TableSetupColumn(ctx, '', ImGui.TableColumnFlags_WidthFixed, TEXT_BASE_WIDTH * 30.0)
      ImGui.TableSetupColumn(ctx, '', ImGui.TableColumnFlags_WidthFixed, TEXT_BASE_WIDTH * 15.0)
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 3 do
          ImGui.TableSetColumnIndex(ctx, column)
          if row == 0 then
            ImGui.Text(ctx, ('(w: %5.1f)'):format(ImGui.GetContentRegionAvail(ctx)))
          else
            ImGui.Text(ctx, ('Hello %d,%d'):format(column, row))
          end
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Nested tables') then
    demo.HelpMarker('This demonstrates embedding a table into another table cell.')

    local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_Resizable | ImGui.TableFlags_Reorderable | ImGui.TableFlags_Hideable
    if ImGui.BeginTable(ctx, 'table_nested1', 2, flags) then
      ImGui.TableSetupColumn(ctx, 'A0')
      ImGui.TableSetupColumn(ctx, 'A1')
      ImGui.TableHeadersRow(ctx)

      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, 'A0 Row 0')

      local rows_height = TEXT_BASE_HEIGHT * 2
      if ImGui.BeginTable(ctx, 'table_nested2', 2, flags) then
        ImGui.TableSetupColumn(ctx, 'B0')
        ImGui.TableSetupColumn(ctx, 'B1')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx, ImGui.TableRowFlags_None, rows_height)
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, 'B0 Row 0')
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, 'B0 Row 1')
        ImGui.TableNextRow(ctx, ImGui.TableRowFlags_None, rows_height)
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, 'B1 Row 0')
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, 'B1 Row 1')

        ImGui.EndTable(ctx)
      end

      ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'A0 Row 1')
      ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'A1 Row 0')
      ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'A1 Row 1')
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Row height') then
    demo.HelpMarker(
      "You can pass a 'min_row_height' to TableNextRow().\n\nRows are padded with StyleVar_CellPadding.y on top and bottom, \z
       so effectively the minimum row height will always be >= StyleVar_CellPadding.y * 2.0.\n\n\z
       We cannot honor a _maximum_ row height as that would require a unique clipping rectangle per row.")
    if ImGui.BeginTable(ctx, 'table_row_height', 1, ImGui.TableFlags_Borders) then
      for row = 0, 7 do
        local min_row_height = TEXT_BASE_HEIGHT * 0.30 * row // 1
        ImGui.TableNextRow(ctx, ImGui.TableRowFlags_None, min_row_height)
        ImGui.TableNextColumn(ctx)
        ImGui.Text(ctx, ('min_row_height = %.2f'):format(min_row_height))
      end
      ImGui.EndTable(ctx)
    end

    demo.HelpMarker(
      'Showcase using SameLine(0,0) to share Current Line Height between cells.\n\n\z
       Please note that Tables Row Height is not the same thing as Current Line Height, \z
       as a table cell may contains multiple lines.')
    if ImGui.BeginTable(ctx, 'table_share_lineheight', 2, ImGui.TableFlags_Borders) then
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.ColorButton(ctx, '##1', 0x214266FF, ImGui.ColorEditFlags_None, 40, 40)
      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, 'Line 1')
      ImGui.Text(ctx, 'Line 2')

      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.ColorButton(ctx, '##2', 0x214266FF, ImGui.ColorEditFlags_None, 40, 40)
      ImGui.TableNextColumn(ctx)
      ImGui.SameLine(ctx, 0.0, 0.0) -- Reuse line height from previous column
      ImGui.Text(ctx, 'Line 1, with SameLine(0,0)')
      ImGui.Text(ctx, 'Line 2')

      ImGui.EndTable(ctx)
    end

    demo.HelpMarker('Showcase altering CellPadding.y between rows. Note that CellPadding.x is locked for the entire table.')
    if ImGui.BeginTable(ctx, 'table_changing_cellpadding_y', 1, ImGui.TableFlags_Borders) then
      for row = 0, 7 do
        if (row % 3) == 2 then
          ImGui.PushStyleVarY(ctx, ImGui.StyleVar_CellPadding, 20)
        end
        ImGui.TableNextRow(ctx, ImGui.TableRowFlags_None)
        ImGui.TableNextColumn(ctx)
        local cell_padding_y = select(2, ImGui.GetStyleVar(ctx, ImGui.StyleVar_CellPadding))
        ImGui.Text(ctx, ('CellPadding.y = %.2f'):format(cell_padding_y))
        if (row % 3) == 2 then
          ImGui.PopStyleVar(ctx)
        end
      end
      ImGui.EndTable(ctx)
    end

    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Outer size') then
    if not tables.outer_sz then
      tables.outer_sz = {
        flags = ImGui.TableFlags_Borders |
                ImGui.TableFlags_Resizable |
                ImGui.TableFlags_ContextMenuInBody |
                ImGui.TableFlags_RowBg |
                ImGui.TableFlags_SizingFixedFit |
                ImGui.TableFlags_NoHostExtendX,
      }
    end

    -- Showcasing use of TableFlags_NoHostExtendX and TableFlags_NoHostExtendY
    -- Important to that note how the two flags have slightly different behaviors!
    ImGui.Text(ctx, 'Using NoHostExtendX and NoHostExtendY:')
    demo.PushStyleCompact()
    rv,tables.outer_sz.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoHostExtendX', tables.outer_sz.flags, ImGui.TableFlags_NoHostExtendX)
    ImGui.SameLine(ctx); demo.HelpMarker('Make outer width auto-fit to columns, overriding outer_size_w value.\n\nOnly available when ScrollX/ScrollY are disabled and Stretch columns are not used.')
    rv,tables.outer_sz.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoHostExtendY', tables.outer_sz.flags, ImGui.TableFlags_NoHostExtendY)
    ImGui.SameLine(ctx); demo.HelpMarker('Make outer height stop exactly at outer_size_h (prevent auto-extending table past the limit).\n\nOnly available when ScrollX/ScrollY are disabled. Data below the limit will be clipped and not visible.')
    demo.PopStyleCompact()

    local outer_size_w, outer_size_h = 0.0, TEXT_BASE_HEIGHT * 5.5
    if ImGui.BeginTable(ctx, 'table1', 3, tables.outer_sz.flags, outer_size_w, outer_size_h) then
      for row = 0, 9 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('Cell %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, 'Hello!')

    ImGui.Spacing(ctx)

    local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg
    ImGui.Text(ctx, 'Using explicit size:')
    if ImGui.BeginTable(ctx, 'table2', 3, flags, TEXT_BASE_WIDTH * 30, 0.0) then
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('Cell %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.BeginTable(ctx, 'table3', 3, flags, TEXT_BASE_WIDTH * 30, 0.0) then
      for row = 0, 2 do
        ImGui.TableNextRow(ctx, 0, TEXT_BASE_HEIGHT * 1.5)
        for column = 0, 2 do
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('Cell %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end

    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Background color') then
    if not tables.bg_col then
      tables.bg_col = {
        flags         = ImGui.TableFlags_RowBg,
        row_bg_type   = 1,
        row_bg_target = 1,
        cell_bg_type  = 1,
      }
    end

    demo.PushStyleCompact()
    rv,tables.bg_col.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Borders', tables.bg_col.flags, ImGui.TableFlags_Borders)
    rv,tables.bg_col.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_RowBg', tables.bg_col.flags, ImGui.TableFlags_RowBg)
    ImGui.SameLine(ctx); demo.HelpMarker('TableFlags_RowBg automatically sets RowBg0 to alternative colors pulled from the Style.')
    rv,tables.bg_col.row_bg_type = ImGui.Combo(ctx, 'row bg type', tables.bg_col.row_bg_type, "None\0Red\0Gradient\0")
    rv,tables.bg_col.row_bg_target = ImGui.Combo(ctx, 'row bg target', tables.bg_col.row_bg_target, "RowBg0\0RowBg1\0"); ImGui.SameLine(ctx); demo.HelpMarker('Target RowBg0 to override the alternating odd/even colors,\nTarget RowBg1 to blend with them.')
    rv,tables.bg_col.cell_bg_type = ImGui.Combo(ctx, 'cell bg type', tables.bg_col.cell_bg_type, 'None\0Blue\0'); ImGui.SameLine(ctx); demo.HelpMarker('We are colorizing cells to B1->C2 here.')
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table1', 5, tables.bg_col.flags) then
      for row = 0, 5 do
        ImGui.TableNextRow(ctx)

        -- Demonstrate setting a row background color with 'TableSetBgColor(TableBgTarget_RowBgX, ...)'
        -- We use a transparent color so we can see the one behind in case our target is RowBg1 and RowBg0 was already targeted by the TableFlags_RowBg flag.
        if tables.bg_col.row_bg_type ~= 0 then
          local row_bg_color
          if tables.bg_col.row_bg_type == 1 then -- flat
            row_bg_color = 0xb34d4da6
          else -- gradient
            row_bg_color = 0x333333a6
            row_bg_color = row_bg_color + (demo.round((row * 0.1) * 0xFF) << 24)
          end
          ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0 + tables.bg_col.row_bg_target, row_bg_color)
        end

        -- Fill cells
        for column = 0, 4 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('%c%c'):format(string.byte('A') + row, string.byte('0') + column))

          -- Change background of Cells B1->C2
          -- Demonstrate setting a cell background color with 'TableSetBgColor(TableBgTarget_CellBg, ...)'
          -- (the CellBg color will be blended over the RowBg and ColumnBg colors)
          -- We can also pass a column number as a third parameter to TableSetBgColor() and do this outside the column loop.
          if row >= 1 and row <= 2 and column >= 1 and column <= 2 and tables.bg_col.cell_bg_type == 1 then
            ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_CellBg, 0x4d4db3a6)
          end
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Tree view') then
    if not tables.tree_view then
      tables.tree_view = {
        tree_node_flags_base = ImGui.TreeNodeFlags_SpanAllColumns |
                               ImGui.TreeNodeFlags_DefaultOpen |
                               ImGui.TreeNodeFlags_DrawLinesFull,
      }
    end

    local table_flags =
      ImGui.TableFlags_BordersV      |
      ImGui.TableFlags_BordersOuterH |
      ImGui.TableFlags_Resizable     |
      ImGui.TableFlags_RowBg --      |
      -- ImGui.TableFlags_NoBordersInBody

    rv,tables.tree_view.tree_node_flags_base = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanFullWidth',  tables.tree_view.tree_node_flags_base, ImGui.TreeNodeFlags_SpanFullWidth)
    rv,tables.tree_view.tree_node_flags_base = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanLabelWidth',  tables.tree_view.tree_node_flags_base, ImGui.TreeNodeFlags_SpanLabelWidth)
    rv,tables.tree_view.tree_node_flags_base = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_SpanAllColumns', tables.tree_view.tree_node_flags_base, ImGui.TreeNodeFlags_SpanAllColumns)
    rv,tables.tree_view.tree_node_flags_base = ImGui.CheckboxFlags(ctx, 'TreeNodeFlags_LabelSpanAllColumns', tables.tree_view.tree_node_flags_base, ImGui.TreeNodeFlags_LabelSpanAllColumns)
    ImGui.SameLine(ctx); demo.HelpMarker("Useful if you know that you aren't displaying contents in other columns")

    demo.HelpMarker('See "Columns flags" section to configure how indentation is applied to individual columns.')
    if ImGui.BeginTable(ctx, '3ways', 3, table_flags) then
      -- The first column will use the default _WidthStretch when ScrollX is Off and _WidthFixed when ScrollX is On
      ImGui.TableSetupColumn(ctx, 'Name', ImGui.TableColumnFlags_NoHide)
      ImGui.TableSetupColumn(ctx, 'Size', ImGui.TableColumnFlags_WidthFixed, TEXT_BASE_WIDTH * 12.0)
      ImGui.TableSetupColumn(ctx, 'Type', ImGui.TableColumnFlags_WidthFixed, TEXT_BASE_WIDTH * 18.0)
      ImGui.TableHeadersRow(ctx)

      -- Simple storage to output a dummy file-system.
      local nodes = {
        {name='Root with Long Name',           type='Folder',      size=-1,     child_idx= 1,  child_count= 3}, -- 0
        {name='Music',                         type='Folder',      size=-1,     child_idx= 4,  child_count= 2}, -- 1
        {name='Textures',                      type='Folder',      size=-1,     child_idx= 6,  child_count= 3}, -- 2
        {name='desktop.ini',                   type='System file', size= 1024,   child_idx=-1, child_count=-1}, -- 3
        {name='File1_a.wav',                   type='Audio file',  size= 123000, child_idx=-1, child_count=-1}, -- 4
        {name='File1_b.wav',                   type='Audio file',  size= 456000, child_idx=-1, child_count=-1}, -- 5
        {name='Image001.png',                  type='Image file',  size= 203128, child_idx=-1, child_count=-1}, -- 6
        {name='Copy of Image001.png',          type='Image file',  size= 203256, child_idx=-1, child_count=-1}, -- 7
        {name='Copy of Image001 (Final2).png', type='Image file',  size= 203512, child_idx=-1, child_count=-1}, -- 8
      }

      local function DisplayNode(node)
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx)
        local is_folder = node.child_count > 0

        local node_flags = tables.tree_view.tree_node_flags_base
        if node ~= nodes[1] then
          node_flags = node_flags & ~ImGui.TreeNodeFlags_LabelSpanAllColumns -- Only demonstrate this on the root node.
        end

        if is_folder then
          local open = ImGui.TreeNode(ctx, node.name, node_flags)
          if node_flags & ImGui.TreeNodeFlags_LabelSpanAllColumns == 0 then
            ImGui.TableNextColumn(ctx)
            ImGui.TextDisabled(ctx, '--')
            ImGui.TableNextColumn(ctx)
            ImGui.Text(ctx, node.type)
          end
          if open then
            for child_n = 1, node.child_count do
              DisplayNode(nodes[node.child_idx + child_n])
            end
            ImGui.TreePop(ctx)
          end
        else
          ImGui.TreeNode(ctx, node.name, node_flags | ImGui.TreeNodeFlags_Leaf | ImGui.TreeNodeFlags_Bullet | ImGui.TreeNodeFlags_NoTreePushOnOpen)
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('%d'):format(node.size))
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, node.type)
        end
      end

      DisplayNode(nodes[1])

      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Item width') then
    if not tables.item_width then
      tables.item_width = {
        dummy_d = 0.0,
      }
    end

    demo.HelpMarker(
      "Showcase using PushItemWidth() and how it is preserved on a per-column basis.\n\n\z
       Note that on auto-resizing non-resizable fixed columns, querying the content width for \z
       e.g. right-alignment doesn't make sense.")
    if ImGui.BeginTable(ctx, 'table_item_width', 3, ImGui.TableFlags_Borders) then
      ImGui.TableSetupColumn(ctx, 'small')
      ImGui.TableSetupColumn(ctx, 'half')
      ImGui.TableSetupColumn(ctx, 'right-align')
      ImGui.TableHeadersRow(ctx)

      for row = 0, 2 do
        ImGui.TableNextRow(ctx)
        if row == 0 then
          -- Setup ItemWidth once (instead of setting up every time, which is also possible but less efficient)
          ImGui.TableSetColumnIndex(ctx, 0)
          ImGui.PushItemWidth(ctx, TEXT_BASE_WIDTH * 3.0) -- Small
          ImGui.TableSetColumnIndex(ctx, 1)
          ImGui.PushItemWidth(ctx, 0 - ImGui.GetContentRegionAvail(ctx) * 0.5)
          ImGui.TableSetColumnIndex(ctx, 2)
          ImGui.PushItemWidth(ctx, -FLT_MIN) -- Right-aligned
        end

        -- Draw our contents
        ImGui.PushID(ctx, row)
        ImGui.TableSetColumnIndex(ctx, 0)
        rv,tables.item_width.dummy_d = ImGui.SliderDouble(ctx, 'double0', tables.item_width.dummy_d, 0.0, 1.0)
        ImGui.TableSetColumnIndex(ctx, 1)
        rv,tables.item_width.dummy_d = ImGui.SliderDouble(ctx, 'double1', tables.item_width.dummy_d, 0.0, 1.0)
        ImGui.TableSetColumnIndex(ctx, 2)
        rv,tables.item_width.dummy_d = ImGui.SliderDouble(ctx, '##double2', tables.item_width.dummy_d, 0.0, 1.0) -- No visible label since right-aligned
        ImGui.PopID(ctx)
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  -- Demonstrate using TableHeader() calls instead of TableHeadersRow()
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Custom headers') then
    if not tables.headers then
      tables.headers = {
        column_selected = {false, false, false},
      }
    end

    local COLUMNS_COUNT = 3
    if ImGui.BeginTable(ctx, 'table_custom_headers', COLUMNS_COUNT, ImGui.TableFlags_Borders | ImGui.TableFlags_Reorderable | ImGui.TableFlags_Hideable) then
      ImGui.TableSetupColumn(ctx, 'Apricot')
      ImGui.TableSetupColumn(ctx, 'Banana')
      ImGui.TableSetupColumn(ctx, 'Cherry')

      -- Instead of calling TableHeadersRow() we'll submit custom headers ourselves.
      -- (A different approach is also possible:
      --   - Specify ImGuiTableColumnFlags_NoHeaderLabel in some TableSetupColumn() call.
      --   - Call TableHeadersRow() normally. This will submit TableHeader() with no name.
      --   - Then call TableSetColumnIndex() to position yourself in the column and submit your stuff e.g. Checkbox().)
      ImGui.TableNextRow(ctx, ImGui.TableRowFlags_Headers)
      for column = 0, COLUMNS_COUNT - 1 do
        ImGui.TableSetColumnIndex(ctx, column)
        local column_name = ImGui.TableGetColumnName(ctx, column) -- Retrieve name passed to TableSetupColumn()
        ImGui.PushID(ctx, column)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
        rv,tables.headers.column_selected[column + 1] =
          ImGui.Checkbox(ctx, '##checkall', tables.headers.column_selected[column + 1])
        ImGui.PopStyleVar(ctx)
        ImGui.SameLine(ctx, 0.0, (ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)))
        ImGui.TableHeader(ctx, column_name)
        ImGui.PopID(ctx)
      end

      -- Submit table contents
      for row = 0, 4 do
        ImGui.TableNextRow(ctx)
        for column = 0, 2 do
          local buf = ('Cell %d,%d'):format(column, row)
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Selectable(ctx, buf, tables.headers.column_selected[column + 1])
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  -- Demonstrate using TableColumnFlags_AngledHeader flag to create angled headers
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Angled headers') then
    if not tables.angled then
      tables.angled = {
        table_flags = ImGui.TableFlags_SizingFixedFit |
                      ImGui.TableFlags_ScrollX        |
                      ImGui.TableFlags_ScrollY        |
                      ImGui.TableFlags_BordersOuter   |
                      ImGui.TableFlags_BordersInnerH  |
                      ImGui.TableFlags_Hideable       |
                      ImGui.TableFlags_Resizable      |
                      ImGui.TableFlags_Reorderable    |
                      ImGui.TableFlags_HighlightHoveredColumn,
        column_flags = ImGui.TableColumnFlags_AngledHeader | ImGui.TableColumnFlags_WidthFixed,
        bools = {}, -- Dummy storage selection storage
        frozen_cols = 1,
        frozen_rows = 2,
        angle = ImGui.GetStyleVar(ctx, ImGui.StyleVar_TableAngledHeadersAngle),
        text_align = {ImGui.GetStyleVar(ctx, ImGui.StyleVar_TableAngledHeadersTextAlign)},
      }
    end

    local column_names = {'Track', 'cabasa', 'ride', 'smash', 'tom-hi', 'tom-mid', 'tom-low', 'hihat-o', 'hihat-c', 'snare-s', 'snare-c', 'clap', 'rim', 'kick'}
    local columns_count = #column_names
    local rows_count = 12

    rv,tables.angled.table_flags = ImGui.CheckboxFlags(ctx, '_ScrollX',   tables.angled.table_flags, ImGui.TableFlags_ScrollX)
    rv,tables.angled.table_flags = ImGui.CheckboxFlags(ctx, '_ScrollY',   tables.angled.table_flags, ImGui.TableFlags_ScrollY)
    rv,tables.angled.table_flags = ImGui.CheckboxFlags(ctx, '_Resizable', tables.angled.table_flags, ImGui.TableFlags_Resizable)
    rv,tables.angled.table_flags = ImGui.CheckboxFlags(ctx, '_Sortable',  tables.angled.table_flags, ImGui.TableFlags_Sortable)
    -- rv,tables.angled.table_flags = ImGui.CheckboxFlags(ctx, '_NoBordersInBody', tables.angled.table_flags, ImGui.TableFlags_NoBordersInBody)
    rv,tables.angled.table_flags = ImGui.CheckboxFlags(ctx, '_HighlightHoveredColumn', tables.angled.table_flags, ImGui.TableFlags_HighlightHoveredColumn)
    ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
    rv,tables.angled.frozen_cols = ImGui.SliderInt(ctx, 'Frozen columns', tables.angled.frozen_cols, 0, 2)
    ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
    rv,tables.angled.frozen_rows = ImGui.SliderInt(ctx, 'Frozen rows', tables.angled.frozen_rows, 0, 2)
    rv,tables.angled.column_flags = ImGui.CheckboxFlags(ctx, 'Disable header contributing to column width', tables.angled.column_flags, ImGui.TableColumnFlags_NoHeaderWidth)

    if ImGui.TreeNode(ctx, 'Style settings') then
      ImGui.SameLine(ctx)
      demo.HelpMarker('Giving access to some ImGuiStyle value in this demo for convenience.')
      ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
      rv,tables.angled.angle = ImGui.SliderAngle(ctx, 'StyleVar_TableAngledHeadersAngle', tables.angled.angle, -50.0, 50.0)
      ImGui.SetNextItemWidth(ctx, ImGui.GetFontSize(ctx) * 8)
      rv,tables.angled.text_align[1],tables.angled.text_align[2] =
        ImGui.SliderDouble2(ctx, 'StyleVar_TableAngledHeadersTextAlign', tables.angled.text_align[1], tables.angled.text_align[2], 0.0, 1.0, "%.2f")
      ImGui.TreePop(ctx)
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_TableAngledHeadersAngle, tables.angled.angle)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_TableAngledHeadersTextAlign, table.unpack(tables.angled.text_align))

    if ImGui.BeginTable(ctx, 'table_angled_headers', columns_count, tables.angled.table_flags, 0.0, TEXT_BASE_HEIGHT * 12) then
      ImGui.TableSetupColumn(ctx, column_names[1], ImGui.TableColumnFlags_NoHide | ImGui.TableColumnFlags_NoReorder)
      for n = 2, columns_count do
        ImGui.TableSetupColumn(ctx, column_names[n], tables.angled.column_flags)
      end
      ImGui.TableSetupScrollFreeze(ctx, tables.angled.frozen_cols, tables.angled.frozen_rows)

      ImGui.TableAngledHeadersRow(ctx) -- Draw angled headers for all columns with the TableColumnFlags_AngledHeader flag.
      ImGui.TableHeadersRow(ctx)       -- Draw remaining headers and allow access to context-menu and other functions.
      for row = 0, rows_count - 1 do
        ImGui.PushID(ctx, row)
        ImGui.TableNextRow(ctx)
        ImGui.TableSetColumnIndex(ctx, 0)
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.Text(ctx, ('Track %d'):format(row))
        for column = 1, columns_count - 1 do
          if ImGui.TableSetColumnIndex(ctx, column) then
            ImGui.PushID(ctx, column)
            local bool_idx = row * columns_count + column
            rv,tables.angled.bools[bool_idx] = ImGui.Checkbox(ctx, '', tables.angled.bools[bool_idx])
            ImGui.PopID(ctx)
          end
        end
        ImGui.PopID(ctx)
      end
      ImGui.EndTable(ctx)
    end

    ImGui.PopStyleVar(ctx, 2)
    ImGui.TreePop(ctx)
  end

  -- Demonstrate creating custom context menus inside columns,
  -- while playing it nice with context menus provided by TableHeadersRow()/TableHeader()
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Context menus') then
    if not tables.ctx_menus then
      tables.ctx_menus = {
        flags1 = ImGui.TableFlags_Resizable   |
                 ImGui.TableFlags_Reorderable |
                 ImGui.TableFlags_Hideable    |
                 ImGui.TableFlags_Borders     |
                 ImGui.TableFlags_ContextMenuInBody
      }
    end
    demo.HelpMarker(
      'By default, right-clicking over a TableHeadersRow()/TableHeader() line will open the default context-menu.\n\z
       Using TableFlags_ContextMenuInBody we also allow right-clicking over columns body.')

    demo.PushStyleCompact()
    rv,tables.ctx_menus.flags1 = ImGui.CheckboxFlags(ctx, 'TableFlags_ContextMenuInBody', tables.ctx_menus.flags1, ImGui.TableFlags_ContextMenuInBody)
    demo.PopStyleCompact()

    -- Context Menus: first example
    -- [1.1] Right-click on the TableHeadersRow() line to open the default table context menu.
    -- [1.2] Right-click in columns also open the default table context menu (if TableFlags_ContextMenuInBody is set)
    local COLUMNS_COUNT = 3
    if ImGui.BeginTable(ctx, 'table_context_menu', COLUMNS_COUNT, tables.ctx_menus.flags1) then
      ImGui.TableSetupColumn(ctx, 'One')
      ImGui.TableSetupColumn(ctx, 'Two')
      ImGui.TableSetupColumn(ctx, 'Three')

      -- [1.1]] Right-click on the TableHeadersRow() line to open the default table context menu.
      ImGui.TableHeadersRow(ctx)

      -- Submit dummy contents
      for row = 0, 3 do
        ImGui.TableNextRow(ctx)
        for column = 0, COLUMNS_COUNT - 1 do
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Cell %d,%d'):format(column, row))
        end
      end
      ImGui.EndTable(ctx)
    end

    -- Context Menus: second example
    -- [2.1] Right-click on the TableHeadersRow() line to open the default table context menu.
    -- [2.2] Right-click on the ".." to open a custom popup
    -- [2.3] Right-click in columns to open another custom popup
    demo.HelpMarker(
      'Demonstrate mixing table context menu (over header), item context button (over button) \z
       and custom per-column context menu (over column body).')
    local flags2 = ImGui.TableFlags_Resizable      |
                   ImGui.TableFlags_SizingFixedFit |
                   ImGui.TableFlags_Reorderable    |
                   ImGui.TableFlags_Hideable       |
                   ImGui.TableFlags_Borders
    if ImGui.BeginTable(ctx, 'table_context_menu_2', COLUMNS_COUNT, flags2) then
      ImGui.TableSetupColumn(ctx, 'One')
      ImGui.TableSetupColumn(ctx, 'Two')
      ImGui.TableSetupColumn(ctx, 'Three')

      -- [2.1] Right-click on the TableHeadersRow() line to open the default table context menu.
      ImGui.TableHeadersRow(ctx)
      for row = 0, 3 do
        ImGui.TableNextRow(ctx)
        for column = 0, COLUMNS_COUNT - 1 do
          -- Submit dummy contents
          ImGui.TableSetColumnIndex(ctx, column)
          ImGui.Text(ctx, ('Cell %d,%d'):format(column, row))
          ImGui.SameLine(ctx)

          -- [2.2] Right-click on the ".." to open a custom popup
          ImGui.PushID(ctx, row * COLUMNS_COUNT + column)
          ImGui.SmallButton(ctx, "..")
          if ImGui.BeginPopupContextItem(ctx) then
            ImGui.Text(ctx, ('This is the popup for Button("..") in Cell %d,%d'):format(column, row))
            if ImGui.Button(ctx, 'Close') then
              ImGui.CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
          end
          ImGui.PopID(ctx)
        end
      end

      -- [2.3] Right-click anywhere in columns to open another custom popup
      -- (instead of testing for !IsAnyItemHovered() we could also call OpenPopup() with PopupFlags_NoOpenOverExistingPopup
      -- to manage popup priority as the popups triggers, here "are we hovering a column" are overlapping)
      local hovered_column = -1
      for column = 0, COLUMNS_COUNT do
        ImGui.PushID(ctx, column)
        if (ImGui.TableGetColumnFlags(ctx, column) & ImGui.TableColumnFlags_IsHovered) ~= 0 then
          hovered_column = column
        end
        if hovered_column == column and not ImGui.IsAnyItemHovered(ctx) and ImGui.IsMouseReleased(ctx, 1) then
          ImGui.OpenPopup(ctx, 'MyPopup')
        end
        if ImGui.BeginPopup(ctx, 'MyPopup') then
          if column == COLUMNS_COUNT then
            ImGui.Text(ctx, 'This is a custom popup for unused space after the last column.')
          else
            ImGui.Text(ctx, ('This is a custom popup for Column %d'):format(column))
          end
          if ImGui.Button(ctx, 'Close') then
            ImGui.CloseCurrentPopup(ctx)
          end
          ImGui.EndPopup(ctx)
        end
        ImGui.PopID(ctx)
      end

      ImGui.EndTable(ctx)
      ImGui.Text(ctx, ('Hovered column: %d'):format(hovered_column))
    end
    ImGui.TreePop(ctx)
  end

  -- Demonstrate creating multiple tables with the same ID
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Synced instances') then
    if not tables.synced then
      tables.synced = {
        flags = ImGui.TableFlags_Resizable      |
                ImGui.TableFlags_Reorderable    |
                ImGui.TableFlags_Hideable       |
                ImGui.TableFlags_Borders        |
                ImGui.TableFlags_SizingFixedFit |
                ImGui.TableFlags_NoSavedSettings,
      }
    end
    demo.HelpMarker('Multiple tables with the same identifier will share their settings, width, visibility, order etc.')
    rv,tables.synced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.synced.flags, ImGui.TableFlags_Resizable)
    rv,tables.synced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollY', tables.synced.flags, ImGui.TableFlags_ScrollY)
    rv,tables.synced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_SizingFixedFit', tables.synced.flags, ImGui.TableFlags_SizingFixedFit)
    rv,tables.synced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_HighlightHoveredColumn', tables.synced.flags, ImGui.TableFlags_HighlightHoveredColumn)
    for n = 0, 2 do
      local buf = ('Synced Table %d'):format(n)
      local open = ImGui.CollapsingHeader(ctx, buf, nil, ImGui.TreeNodeFlags_DefaultOpen)
      if open and ImGui.BeginTable(ctx, 'Table', 3, tables.synced.flags, 0, ImGui.GetTextLineHeightWithSpacing(ctx) * 5) then
        ImGui.TableSetupColumn(ctx, 'One')
        ImGui.TableSetupColumn(ctx, 'Two')
        ImGui.TableSetupColumn(ctx, 'Three')
        ImGui.TableHeadersRow(ctx)
        local cell_count = n == 1 and 27 or 9 -- Make second table have a scrollbar to verify that additional decoration is not affecting column positions.
        for cell = 0, cell_count do
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('this cell %d'):format(cell))
        end
        ImGui.EndTable(ctx)
      end
    end
    ImGui.TreePop(ctx)
  end

  -- Demonstrate using Sorting facilities
  -- This is a simplified version of the "Advanced" example, where we mostly focus on the code necessary to handle sorting.
  -- Note that the "Advanced" example also showcase manually triggering a sort (e.g. if item quantities have been modified)
  local template_items_names = {
    'Banana', 'Apple', 'Cherry', 'Watermelon', 'Grapefruit', 'Strawberry', 'Mango',
    'Kiwi', 'Orange', 'Pineapple', 'Blueberry', 'Plum', 'Coconut', 'Pear', 'Apricot'
  }
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Sorting') then
    if not tables.sorting then
      tables.sorting = {
        flags = ImGui.TableFlags_Resizable       |
                ImGui.TableFlags_Reorderable     |
                ImGui.TableFlags_Hideable        |
                ImGui.TableFlags_Sortable        |
                ImGui.TableFlags_SortMulti       |
                ImGui.TableFlags_RowBg           |
                ImGui.TableFlags_BordersOuter    |
                ImGui.TableFlags_BordersV        |
                -- ImGui.TableFlags_NoBordersInBody() |
                ImGui.TableFlags_ScrollY,
        items = {},
      }

      -- Create item list
      for n = 0, 49 do
        local template_n = n % #template_items_names
        local item = {
          id = n,
          name = template_items_names[template_n + 1],
          quantity = (n * n - n) % 20, -- Assign default quantities
        }
        table.insert(tables.sorting.items, item)
      end
    end

    -- Options
    demo.PushStyleCompact()
    rv,tables.sorting.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_SortMulti', tables.sorting.flags, ImGui.TableFlags_SortMulti)
    ImGui.SameLine(ctx); demo.HelpMarker('When sorting is enabled: hold shift when clicking headers to sort on multiple column. TableGetColumnSortSpecs() may return specs where (SpecsCount > 1).')
    rv,tables.sorting.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_SortTristate', tables.sorting.flags, ImGui.TableFlags_SortTristate)
    ImGui.SameLine(ctx); demo.HelpMarker('When sorting is enabled: allow no sorting, disable default sorting. TableGetColumnSortSpecs() may return specs where (SpecsCount == 0).')
    demo.PopStyleCompact()

    if ImGui.BeginTable(ctx, 'table_sorting', 4, tables.sorting.flags, 0.0, TEXT_BASE_HEIGHT * 15, 0.0) then
      -- Declare columns
      -- We use the "user_id" parameter of TableSetupColumn() to specify a user id that will be stored in the sort specifications.
      -- This is so our sort function can identify a column given our own identifier. We could also identify them based on their index!
      -- Demonstrate using a mixture of flags among available sort-related flags:
      -- - TableColumnFlags_DefaultSort
      -- - TableColumnFlags_NoSort / TableColumnFlags_NoSortAscending / TableColumnFlags_NoSortDescending
      -- - TableColumnFlags_PreferSortAscending / TableColumnFlags_PreferSortDescending
      ImGui.TableSetupColumn(ctx, 'ID',       ImGui.TableColumnFlags_DefaultSort          | ImGui.TableColumnFlags_WidthFixed,   0.0, MyItemColumnID_ID)
      ImGui.TableSetupColumn(ctx, 'Name',                                                       ImGui.TableColumnFlags_WidthFixed,   0.0, MyItemColumnID_Name)
      ImGui.TableSetupColumn(ctx, 'Action',   ImGui.TableColumnFlags_NoSort               | ImGui.TableColumnFlags_WidthFixed,   0.0, MyItemColumnID_Action)
      ImGui.TableSetupColumn(ctx, 'Quantity', ImGui.TableColumnFlags_PreferSortDescending | ImGui.TableColumnFlags_WidthStretch, 0.0, MyItemColumnID_Quantity)
      ImGui.TableSetupScrollFreeze(ctx, 0, 1) -- Make row always visible
      ImGui.TableHeadersRow(ctx)

      -- Sort our data if sort specs have been changed!
      if ImGui.TableNeedSort(ctx) then
        table.sort(tables.sorting.items, demo.CompareTableItems)
      end

      -- Demonstrate using clipper for large vertical lists
      local clipper = ImGui.ListClipper() -- initialize clipper state
      ImGui.ListClipper_Begin(clipper, #tables.sorting.items)
      while ImGui.ListClipper_Step(clipper) do
        local display_start, display_end = ImGui.ListClipper_GetDisplayRange(clipper)
        for row_n = display_start, display_end - 1 do
          -- Display a data item
          local item = tables.sorting.items[row_n + 1]
          ImGui.PushID(ctx, item.id)
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('%04d'):format(item.id))
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, item.name)
          ImGui.TableNextColumn(ctx)
          ImGui.SmallButton(ctx, 'None')
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx, ('%d'):format(item.quantity))
          ImGui.PopID(ctx)
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.TreePop(ctx)
  end

  -- In this example we'll expose most table flags and settings.
  -- For specific flags and settings refer to the corresponding section for more detailed explanation.
  -- This section is mostly useful to experiment with combining certain flags or settings with each others.
  -- ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once) -- [DEBUG]
  DoOpenAction()
  if ImGui.TreeNode(ctx, 'Advanced') then
    local CT_Text, CT_Button, CT_SmallButton, CT_FillButton, CT_Selectable, CT_SelectableSpanRow = 0, 1, 2, 3, 4, 5
    if not tables.advanced then
      tables.advanced = {
        items = {},
        flags = ImGui.TableFlags_Resizable       |
                ImGui.TableFlags_Reorderable     |
                ImGui.TableFlags_Hideable        |
                ImGui.TableFlags_Sortable        |
                ImGui.TableFlags_SortMulti       |
                ImGui.TableFlags_RowBg           |
                ImGui.TableFlags_Borders         |
                -- ImGui.TableFlags_NoBordersInBody() |
                ImGui.TableFlags_ScrollX         |
                ImGui.TableFlags_ScrollY         |
                ImGui.TableFlags_SizingFixedFit,
        columns_base_flags       = ImGui.TableColumnFlags_None,
        contents_type           = CT_SelectableSpanRow,
        freeze_cols             = 1,
        freeze_rows             = 1,
        items_count             = #template_items_names * 2,
        outer_size_value_w      = 0.0,
        outer_size_value_h      = TEXT_BASE_HEIGHT * 12,
        row_min_height          = 0.0, -- Auto
        inner_width_with_scroll = 0.0, -- Auto-extend
        outer_size_enabled      = true,
        show_headers            = true,
        show_wrapped_text       = false,
        items_need_sort         = false,
      }
    end

    -- //static ImGuiTextFilter filter;
    -- ImGui.SetNextItemOpen(ctx, true, ImGui.Cond_Once) -- FIXME-TABLE: Enabling this results in initial clipped first pass on table which tend to affect column sizing
    if ImGui.TreeNode(ctx, 'Options') then
      -- Make the UI compact because there are so many fields
      demo.PushStyleCompact()
      ImGui.PushItemWidth(ctx, TEXT_BASE_WIDTH * 28.0)

      if ImGui.TreeNode(ctx, 'Features:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Resizable', tables.advanced.flags, ImGui.TableFlags_Resizable)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Reorderable', tables.advanced.flags, ImGui.TableFlags_Reorderable)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Hideable', tables.advanced.flags, ImGui.TableFlags_Hideable)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_Sortable', tables.advanced.flags, ImGui.TableFlags_Sortable)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoSavedSettings', tables.advanced.flags, ImGui.TableFlags_NoSavedSettings)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_ContextMenuInBody', tables.advanced.flags, ImGui.TableFlags_ContextMenuInBody)
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Decorations:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_RowBg', tables.advanced.flags, ImGui.TableFlags_RowBg)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersV', tables.advanced.flags, ImGui.TableFlags_BordersV)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuterV', tables.advanced.flags, ImGui.TableFlags_BordersOuterV)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInnerV', tables.advanced.flags, ImGui.TableFlags_BordersInnerV)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersH', tables.advanced.flags, ImGui.TableFlags_BordersH)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersOuterH', tables.advanced.flags, ImGui.TableFlags_BordersOuterH)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_BordersInnerH', tables.advanced.flags, ImGui.TableFlags_BordersInnerH)
        -- rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoBordersInBody', tables.advanced.flags, ImGui.TableFlags_NoBordersInBody()) ImGui.SameLine(ctx); demo.HelpMarker('Disable vertical borders in columns Body (borders will always appear in Headers')
        -- rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoBordersInBodyUntilResize', tables.advanced.flags, ImGui.TableFlags_NoBordersInBodyUntilResize()) ImGui.SameLine(ctx); demo.HelpMarker('Disable vertical borders in columns Body until hovered for resize (borders will always appear in Headers)')
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Sizing:', ImGui.TreeNodeFlags_DefaultOpen) then
        tables.advanced.flags = demo.EditTableSizingFlags(tables.advanced.flags)
        ImGui.SameLine(ctx); demo.HelpMarker('In the Advanced demo we override the policy of each column so those table-wide settings have less effect that typical.')
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoHostExtendX', tables.advanced.flags, ImGui.TableFlags_NoHostExtendX)
        ImGui.SameLine(ctx); demo.HelpMarker('Make outer width auto-fit to columns, overriding outer_size_w value.\n\nOnly available when ScrollX/ScrollY are disabled and Stretch columns are not used.')
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoHostExtendY', tables.advanced.flags, ImGui.TableFlags_NoHostExtendY)
        ImGui.SameLine(ctx); demo.HelpMarker('Make outer height stop exactly at outer_size_h (prevent auto-extending table past the limit).\n\nOnly available when ScrollX/ScrollY are disabled. Data below the limit will be clipped and not visible.')
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoKeepColumnsVisible', tables.advanced.flags, ImGui.TableFlags_NoKeepColumnsVisible)
        ImGui.SameLine(ctx); demo.HelpMarker('Only available if ScrollX is disabled.')
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_PreciseWidths', tables.advanced.flags, ImGui.TableFlags_PreciseWidths)
        ImGui.SameLine(ctx); demo.HelpMarker('Disable distributing remainder width to stretched columns (width allocation on a 100-wide table with 3 columns: Without this flag: 33,33,34. With this flag: 33,33,33). With larger number of columns, resizing will appear to be less smooth.')
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoClip', tables.advanced.flags, ImGui.TableFlags_NoClip)
        ImGui.SameLine(ctx); demo.HelpMarker('Disable clipping rectangle for every individual columns (reduce draw command count, items will be able to overflow into other columns). Generally incompatible with ScrollFreeze options.')
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Padding:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_PadOuterX',   tables.advanced.flags, ImGui.TableFlags_PadOuterX)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoPadOuterX', tables.advanced.flags, ImGui.TableFlags_NoPadOuterX)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_NoPadInnerX', tables.advanced.flags, ImGui.TableFlags_NoPadInnerX)
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Scrolling:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollX', tables.advanced.flags, ImGui.TableFlags_ScrollX)
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, ImGui.GetFrameHeight(ctx))
        rv,tables.advanced.freeze_cols = ImGui.DragInt(ctx, 'freeze_cols', tables.advanced.freeze_cols, 0.2, 0, 9, nil, ImGui.SliderFlags_NoInput)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_ScrollY', tables.advanced.flags, ImGui.TableFlags_ScrollY)
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, ImGui.GetFrameHeight(ctx))
        rv,tables.advanced.freeze_rows = ImGui.DragInt(ctx, 'freeze_rows', tables.advanced.freeze_rows, 0.2, 0, 9, nil, ImGui.SliderFlags_NoInput)
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Sorting:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_SortMulti', tables.advanced.flags, ImGui.TableFlags_SortMulti)
        ImGui.SameLine(ctx); demo.HelpMarker('When sorting is enabled: hold shift when clicking headers to sort on multiple column. TableGetColumnSortSpecs() may return specs where (SpecsCount > 1).')
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_SortTristate', tables.advanced.flags, ImGui.TableFlags_SortTristate)
        ImGui.SameLine(ctx); demo.HelpMarker('When sorting is enabled: allow no sorting, disable default sorting. TableGetColumnSortSpecs() may return specs where (SpecsCount == 0).')
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Headers:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.show_headers = ImGui.Checkbox(ctx, 'show_headers', tables.advanced.show_headers)
        rv,tables.advanced.flags = ImGui.CheckboxFlags(ctx, 'TableFlags_HighlightHoveredColumn', tables.advanced.flags, ImGui.TableFlags_HighlightHoveredColumn)
        rv,tables.advanced.columns_base_flags = ImGui.CheckboxFlags(ctx, 'TableColumnFlags_AngledHeader', tables.advanced.columns_base_flags, ImGui.TableColumnFlags_AngledHeader)
        ImGui.SameLine(ctx); demo.HelpMarker('Enable AngledHeader on all columns. Best enabled on selected narrow columns (see "Angled headers" section of the demo).')
        ImGui.TreePop(ctx)
      end

      if ImGui.TreeNode(ctx, 'Other:', ImGui.TreeNodeFlags_DefaultOpen) then
        rv,tables.advanced.show_wrapped_text = ImGui.Checkbox(ctx, 'show_wrapped_text', tables.advanced.show_wrapped_text)

        rv,tables.advanced.outer_size_value_w,tables.advanced.outer_size_value_h =
          ImGui.DragDouble2(ctx, '##OuterSize', tables.advanced.outer_size_value_w, tables.advanced.outer_size_value_h)
        ImGui.SameLine(ctx, 0.0, (ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)))
        rv,tables.advanced.outer_size_enabled = ImGui.Checkbox(ctx, 'outer_size', tables.advanced.outer_size_enabled)
        ImGui.SameLine(ctx)
        demo.HelpMarker(
          'If scrolling is disabled (ScrollX and ScrollY not set):\n\z
           - The table is output directly in the parent window.\n\z
           - OuterSize_w < 0.0 will right-align the table.\n\z
           - OuterSize_w = 0.0 will narrow fit the table unless there are any Stretch columns.\n\z
           - OuterSize_h then becomes the minimum size for the table, which will extend vertically if there are more rows (unless NoHostExtendY is set).')

        -- From a user point of view we will tend to use 'inner_width' differently depending on whether our table is embedding scrolling.
        -- To facilitate toying with this demo we will actually pass 0.0 to the BeginTable() when ScrollX is disabled.
        rv,tables.advanced.inner_width_with_scroll = ImGui.DragDouble(ctx, 'inner_width (when ScrollX active)', tables.advanced.inner_width_with_scroll, 1.0, 0.0, FLT_MAX)

        rv,tables.advanced.row_min_height = ImGui.DragDouble(ctx, 'row_min_height', tables.advanced.row_min_height, 1.0, 0.0, FLT_MAX)
        ImGui.SameLine(ctx); demo.HelpMarker('Specify height of the Selectable item.')

        rv,tables.advanced.items_count = ImGui.DragInt(ctx, 'items_count', tables.advanced.items_count, 0.1, 0, 9999)
        rv,tables.advanced.contents_type = ImGui.Combo(ctx, 'items_type (first column)', tables.advanced.contents_type,
          'Text\0Button\0SmallButton\0FillButton\0Selectable\0Selectable (span row)\0')
        -- //filter.Draw('filter');
        ImGui.TreePop(ctx)
      end

      ImGui.PopItemWidth(ctx)
      demo.PopStyleCompact()
      ImGui.Spacing(ctx)
      ImGui.TreePop(ctx)
    end

    -- Update item list if we changed the number of items
    if #tables.advanced.items ~= tables.advanced.items_count then
      tables.advanced.items = {}
      for n = 0, tables.advanced.items_count - 1 do
        local template_n = n % #template_items_names
        local item = {
          id = n,
          name = template_items_names[template_n + 1],
          quantity = template_n == 3 and 10 or (template_n == 4 and 20 or 0), -- Assign default quantities
        }
        table.insert(tables.advanced.items, item)
      end
    end

    -- const ImDrawList* parent_draw_list = ImGui.GetWindowDrawList();
    -- const int parent_draw_list_draw_cmd_count = parent_draw_list->CmdBuffer.Size;
    -- local table_scroll_cur, table_scroll_max, table_draw_list -- For debug display

    -- Submit table
    local inner_width_to_use = (tables.advanced.flags & ImGui.TableFlags_ScrollX) ~= 0 and tables.advanced.inner_width_with_scroll or 0.0
    local w, h = 0, 0
    if tables.advanced.outer_size_enabled then
      w, h = tables.advanced.outer_size_value_w, tables.advanced.outer_size_value_h
    end
    if ImGui.BeginTable(ctx, 'table_advanced', 6, tables.advanced.flags, w, h, inner_width_to_use) then
      -- Declare columns
      -- We use the "user_id" parameter of TableSetupColumn() to specify a user id that will be stored in the sort specifications.
      -- This is so our sort function can identify a column given our own identifier. We could also identify them based on their index!
      ImGui.TableSetupColumn(ctx, 'ID',           tables.advanced.columns_base_flags | ImGui.TableColumnFlags_DefaultSort | ImGui.TableColumnFlags_WidthFixed | ImGui.TableColumnFlags_NoHide, 0.0, MyItemColumnID_ID)
      ImGui.TableSetupColumn(ctx, 'Name',         tables.advanced.columns_base_flags | ImGui.TableColumnFlags_WidthFixed, 0.0, MyItemColumnID_Name)
      ImGui.TableSetupColumn(ctx, 'Action',       tables.advanced.columns_base_flags | ImGui.TableColumnFlags_NoSort | ImGui.TableColumnFlags_WidthFixed, 0.0, MyItemColumnID_Action)
      ImGui.TableSetupColumn(ctx, 'Quantity',     tables.advanced.columns_base_flags | ImGui.TableColumnFlags_PreferSortDescending, 0.0, MyItemColumnID_Quantity)
      ImGui.TableSetupColumn(ctx, 'Description',  tables.advanced.columns_base_flags | ((tables.advanced.flags & ImGui.TableFlags_NoHostExtendX) ~= 0 and 0 or ImGui.TableColumnFlags_WidthStretch), 0.0, MyItemColumnID_Description)
      ImGui.TableSetupColumn(ctx, 'Hidden',       tables.advanced.columns_base_flags | ImGui.TableColumnFlags_DefaultHide | ImGui.TableColumnFlags_NoSort)
      ImGui.TableSetupScrollFreeze(ctx, tables.advanced.freeze_cols, tables.advanced.freeze_rows)

      -- Sort our data if sort specs have been changed!
      local specs_dirty, has_specs = ImGui.TableNeedSort(ctx)
      if has_specs and (specs_dirty or tables.advanced.items_need_sort) then
        table.sort(tables.advanced.items, demo.CompareTableItems)
        tables.advanced.items_need_sort = false
      end

      -- Take note of whether we are currently sorting based on the Quantity field,
      -- we will use this to trigger sorting when we know the data of this column has been modified.
      local sorts_specs_using_quantity = (ImGui.TableGetColumnFlags(ctx, 3) & ImGui.TableColumnFlags_IsSorted) ~= 0

      -- Show headers
      if tables.advanced.show_headers then
        if (tables.advanced.columns_base_flags & ImGui.TableColumnFlags_AngledHeader) ~= 0 then
          ImGui.TableAngledHeadersRow(ctx)
        end
        ImGui.TableHeadersRow(ctx)
      end

      -- Show data
      -- Demonstrate using clipper for large vertical lists
      local clipper = ImGui.ListClipper() -- initialize clipper state
      ImGui.ListClipper_Begin(clipper, #tables.advanced.items)
      while ImGui.ListClipper_Step(clipper) do
        local display_start, display_end = ImGui.ListClipper_GetDisplayRange(clipper)
        for row_n = display_start, display_end - 1 do
          local item = tables.advanced.items[row_n + 1]
          -- //if (!filter.PassFilter(item->Name))
          -- //    continue;

          ImGui.PushID(ctx, item.id)
          ImGui.TableNextRow(ctx, ImGui.TableRowFlags_None, tables.advanced.row_min_height)

          -- For the demo purpose we can select among different type of items submitted in the first column
          ImGui.TableSetColumnIndex(ctx, 0)
          local label = ('%04d'):format(item.id)
          local contents_type = tables.advanced.contents_type
          if contents_type == CT_Text then
              ImGui.Text(ctx, label)
          elseif contents_type == CT_Button then
              ImGui.Button(ctx, label)
          elseif contents_type == CT_SmallButton then
              ImGui.SmallButton(ctx, label)
          elseif contents_type == CT_FillButton then
              ImGui.Button(ctx, label, -FLT_MIN, 0.0)
          elseif contents_type == CT_Selectable or contents_type == CT_SelectableSpanRow then
            local selectable_flags = contents_type == CT_SelectableSpanRow and ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_AllowOverlap or ImGui.SelectableFlags_None
            if ImGui.Selectable(ctx, label, item.is_selected, selectable_flags, 0, tables.advanced.row_min_height) then
              if ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl) then
                item.is_selected = not item.is_selected
              else
                for _,it in ipairs(tables.advanced.items) do
                  it.is_selected = it == item
                end
              end
            end
          end

          if ImGui.TableSetColumnIndex(ctx, 1) then
            ImGui.Text(ctx, item.name)
          end

          -- Here we demonstrate marking our data set as needing to be sorted again if we modified a quantity,
          -- and we are currently sorting on the column showing the Quantity.
          -- To avoid triggering a sort while holding the button, we only trigger it when the button has been released.
          -- You will probably need some extra logic if you want to automatically sort when a specific entry changes.
          if ImGui.TableSetColumnIndex(ctx, 2) then
            if ImGui.SmallButton(ctx, 'Chop') then item.quantity = item.quantity + 1 end
            if sorts_specs_using_quantity and ImGui.IsItemDeactivated(ctx) then tables.advanced.items_need_sort = true end
            ImGui.SameLine(ctx)
            if ImGui.SmallButton(ctx, 'Eat')  then item.quantity = item.quantity - 1 end
            if sorts_specs_using_quantity and ImGui.IsItemDeactivated(ctx) then tables.advanced.items_need_sort = true end
          end

          if ImGui.TableSetColumnIndex(ctx, 3) then
            ImGui.Text(ctx, ('%d'):format(item.quantity))
          end

          ImGui.TableSetColumnIndex(ctx, 4)
          if tables.advanced.show_wrapped_text then
            ImGui.TextWrapped(ctx, 'Lorem ipsum dolor sit amet')
          else
            ImGui.Text(ctx, 'Lorem ipsum dolor sit amet')
          end

          if ImGui.TableSetColumnIndex(ctx, 5) then
            ImGui.Text(ctx, '1234')
          end

          ImGui.PopID(ctx)
        end
      end

      -- Store some info to display debug details below
      -- table_scroll_cur_x, table_scroll_cur_y = ImGui.GetScrollX(ctx), ImGui.GetScrollY(ctx)
      -- table_scroll_max_x, table_scroll_max_y = ImGui.GetScrollMaxX(ctx), ImGui.GetScrollMaxY(ctx)
      -- table_draw_list  = ImGui.GetWindowDrawList(ctx)
      ImGui.EndTable(ctx)
    end
    -- static bool show_debug_details = false;
    -- ImGui.Checkbox("Debug details", &show_debug_details);
    -- if (show_debug_details && table_draw_list)
    -- {
    --     ImGui.SameLine(0.0, 0.0);
    --     const int table_draw_list_draw_cmd_count = table_draw_list->CmdBuffer.Size;
    --     if (table_draw_list == parent_draw_list)
    --         ImGui.Text(": DrawCmd: +%d (in same window)",
    --             table_draw_list_draw_cmd_count - parent_draw_list_draw_cmd_count);
    --     else
    --         ImGui.Text(": DrawCmd: +%d (in child window), Scroll: (%.f/%.f) (%.f/%.f)",
    --             table_draw_list_draw_cmd_count - 1, table_scroll_cur_x, table_scroll_max_x, table_scroll_cur_y, table_scroll_max_y);
    -- }
    ImGui.TreePop(ctx)
  end

  ImGui.PopID(ctx)

  -- demo.DemoWindowColumns()

  if tables.disable_indent then
    ImGui.PopStyleVar(ctx)
  end
end

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Tables', true)
  if visible then
    demo.DemoWindowTables()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
