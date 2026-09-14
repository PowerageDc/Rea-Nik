-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Help
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Help')
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
-- Contenido de la seccion: Help
-------------------------------------------------------------------------------

function demo.ShowUserGuide()
  -- ImGuiIO& io = ImGui.GetIO() TODO
  ImGui.BulletText(ctx, 'Double-click on title bar to collapse window.')
  ImGui.BulletText(ctx,
    'Click and drag on lower corner to resize window\n\z
     (double-click to auto fit window to its contents).')
  ImGui.BulletText(ctx, 'Ctrl+Click on a slider or drag box to input value as text.')
  ImGui.BulletText(ctx, 'TAB/Shift+TAB to cycle through keyboard editable fields.')
  ImGui.BulletText(ctx, 'Ctrl+Tab to select a window.')
  -- if (io.FontAllowUserScaling)
  --   ImGui.BulletText(ctx, 'Ctrl+Mouse Wheel to zoom window contents.')
  ImGui.BulletText(ctx, 'While inputing text:\n')
  ImGui.Indent(ctx)
  ImGui.BulletText(ctx, 'Ctrl+Left/Right to word jump.')
  ImGui.BulletText(ctx, 'Ctrl+A or double-click to select all.')
  ImGui.BulletText(ctx, 'Ctrl+X/C/V to use clipboard cut/copy/paste.')
  ImGui.BulletText(ctx, 'Ctrl+Z to undo, Ctrl+Y/Ctrl+Shift+Z to redo.')
  ImGui.BulletText(ctx, 'Escape to revert.')
  ImGui.Unindent(ctx)
  ImGui.BulletText(ctx, 'With keyboard navigation enabled:')
  ImGui.Indent(ctx)
  ImGui.BulletText(ctx, 'Arrow keys to navigate.')
  ImGui.BulletText(ctx, 'Space to activate a widget.')
  ImGui.BulletText(ctx, 'Return to input text into a widget.')
  ImGui.BulletText(ctx, 'Escape to deactivate a widget, close popup, exit child window.')
  ImGui.BulletText(ctx, 'Alt to jump to the menu layer of a window.')
  ImGui.Unindent(ctx)
end

local function Show_Help()
  local rv
  if ImGui.CollapsingHeader(ctx, 'Help') then
    ImGui.SeparatorText(ctx, 'ABOUT THIS DEMO:')
    ImGui.BulletText(ctx, 'Sections below are demonstrating many aspects of the library.')
    ImGui.BulletText(ctx, 'The "Examples" menu above leads to more demo contents.')
    ImGui.BulletText(ctx, 'The "Tools" menu above gives access to: About Box, Style Editor,\n' ..
                            'and Metrics/Debugger (general purpose Dear ImGui debugging tool).')

    ImGui.SeparatorText(ctx, 'PROGRAMMER GUIDE:')
    ImGui.BulletText(ctx, 'See the ShowDemoWindow() code in ReaImGui_Demo.lua. <- you are here!')
    -- ImGui.BulletText(ctx, 'See comments in imgui.cpp.')
    ImGui.BulletText(ctx, 'See example scripts in the ')
    ImGui.SameLine(ctx, 0, 0)
    ImGui.TextLinkOpenURL(ctx, 'examples folder', 'https://github.com/cfillion/reaimgui/tree/master/examples')
    ImGui.BulletText(ctx, 'Read the FAQ at ')
    ImGui.SameLine(ctx, 0, 0)
    ImGui.TextLinkOpenURL(ctx, 'https://www.dearimgui.com/faq/')
    ImGui.BulletText(ctx, "Set ConfigFlags_NavEnableKeyboard for keyboard controls.")
    -- ImGui.BulletText(ctx, "Set ConfigFlags_NavEnableGamepad for gamepad controls.")

    ImGui.SeparatorText(ctx, 'USER GUIDE:')
    demo.ShowUserGuide()
  end

end

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Help', true)
  if visible then
    Show_Help()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
