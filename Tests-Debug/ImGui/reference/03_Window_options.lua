-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Window options
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Window options')
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
-- Contenido de la seccion: Window options
-------------------------------------------------------------------------------

local function Show_WindowOptions()
  local rv
  if ImGui.CollapsingHeader(ctx, 'Window options') then
    if ImGui.BeginTable(ctx, 'split', 3) then
      ImGui.TableNextColumn(ctx); rv,demo.topmost           = ImGui.Checkbox(ctx, 'Always on top', demo.topmost)
      ImGui.TableNextColumn(ctx); rv,demo.no_titlebar       = ImGui.Checkbox(ctx, 'No titlebar', demo.no_titlebar)
      ImGui.TableNextColumn(ctx); rv,demo.no_scrollbar      = ImGui.Checkbox(ctx, 'No scrollbar', demo.no_scrollbar)
      ImGui.TableNextColumn(ctx); rv,demo.no_menu           = ImGui.Checkbox(ctx, 'No menu', demo.no_menu)
      ImGui.TableNextColumn(ctx); rv,demo.no_move           = ImGui.Checkbox(ctx, 'No move', demo.no_move)
      ImGui.TableNextColumn(ctx); rv,demo.no_resize         = ImGui.Checkbox(ctx, 'No resize', demo.no_resize)
      ImGui.TableNextColumn(ctx); rv,demo.no_collapse       = ImGui.Checkbox(ctx, 'No collapse', demo.no_collapse)
      ImGui.TableNextColumn(ctx); rv,demo.no_close          = ImGui.Checkbox(ctx, 'No close', demo.no_close)
      ImGui.TableNextColumn(ctx); rv,demo.no_nav            = ImGui.Checkbox(ctx, 'No nav', demo.no_nav)
      ImGui.TableNextColumn(ctx); rv,demo.no_background     = ImGui.Checkbox(ctx, 'No background', demo.no_background)
      -- ImGui.TableNextColumn(ctx); rv,demo.no_bring_to_front = ImGui.Checkbox(ctx, 'No bring to front', demo.no_bring_to_front)
      ImGui.TableNextColumn(ctx); rv,demo.no_docking        = ImGui.Checkbox(ctx, 'No docking', demo.no_docking)
      ImGui.TableNextColumn(ctx); rv,demo.unsaved_document  = ImGui.Checkbox(ctx, 'Unsaved document', demo.unsaved_document)
      ImGui.EndTable(ctx)
    end

    local flags = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)
    local docking_disabled = demo.no_docking or (flags & ImGui.ConfigFlags_DockingEnable) == 0

    ImGui.Spacing(ctx)
    if docking_disabled then
      ImGui.BeginDisabled(ctx)
    end

    local dock_id = ImGui.GetWindowDockID(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, 'Dock in docker:')
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 222)
    if ImGui.BeginCombo(ctx, '##docker', demo.DockName(dock_id)) then
      if ImGui.Selectable(ctx, 'Floating', dock_id == 0) then
        demo.set_dock_id = 0
      end
      for id = -1, -16, -1 do
        if ImGui.Selectable(ctx, demo.DockName(id), dock_id == id) then
          demo.set_dock_id = id
        end
      end
      ImGui.EndCombo(ctx)
    end

    if docking_disabled then
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, ('Disabled via %s'):format(demo.no_docking and 'WindowFlags' or 'ConfigFlags'))
      ImGui.EndDisabled(ctx)
    end
  end

end

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Window options', true)
  if visible then
    Show_WindowOptions()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
