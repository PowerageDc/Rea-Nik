-- =============================================================
-- Extraido de ReaImGui_Demo-EDIT.lua (debug aislado)
-- Seccion raiz: Configuration
-- =============================================================

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('Demo - Configuration')
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

local show_app = {
  -- Examples Apps (accessible from the "Examples" menu)
  -- main_menu_bar      = false,
  assets_browser     = false,
  console            = false,
  custom_rendering   = false,
  -- dockspace          = false,
  documents          = false,
  log                = false,
  layout             = false,
  property_editor    = false,
  simple_overlay     = false,
  auto_resize        = false,
  constrained_resize = false,
  fullscreen         = false,
  long_text          = false,
  window_titles      = false,

  -- Dear ImGui Tools (accessible from the "Tools" menu)
  metrics       = false,
  debug_log     = false,
  id_stack_tool = false,
  style_editor  = false,
  about         = false,
}

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
-- Contenido de la seccion: Configuration
-------------------------------------------------------------------------------

local function Show_Configuration()
  local rv
  if ImGui.CollapsingHeader(ctx, 'Configuration') then
    if ImGui.TreeNode(ctx, 'Configuration##2') then
      config.flags = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)

      ImGui.SeparatorText(ctx, 'General')
      rv,config.flags = ImGui.CheckboxFlags(ctx, 'ConfigFlags_NavEnableKeyboard', config.flags, ImGui.ConfigFlags_NavEnableKeyboard)
      ImGui.SameLine(ctx); demo.HelpMarker('Enable keyboard controls.')
      -- ImGui.CheckboxFlags("io.ConfigFlags: NavEnableGamepad",     &io.ConfigFlags, ImGuiConfigFlags_NavEnableGamepad)
      -- ImGui.SameLine(ctx); demo.HelpMarker("Enable gamepad controls. Require backend to set io.BackendFlags |= ImGuiBackendFlags_HasGamepad.\n\nRead instructions in imgui.cpp for details.")
      rv,config.flags = ImGui.CheckboxFlags(ctx, 'ConfigFlags_NoMouse', config.flags, ImGui.ConfigFlags_NoMouse)
      ImGui.SameLine(ctx); demo.HelpMarker('Instruct dear imgui to disable mouse inputs and interactions.')

      -- The "NoMouse" option can get us stuck with a disabled mouse! Let's provide an alternative way to fix it:
      if (config.flags & ImGui.ConfigFlags_NoMouse) ~= 0 then
        if ImGui.GetTime(ctx) % 0.40 < 0.20 then
          ImGui.SameLine(ctx)
          ImGui.Text(ctx, '<<PRESS SPACE TO DISABLE>>')
        end
        -- Prevent both being checked
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Space) or (config.flags & ImGui.ConfigFlags_NoKeyboard) ~= 0 then
          config.flags = config.flags & ~ImGui.ConfigFlags_NoMouse
        end
      end
      rv,config.flags = ImGui.CheckboxFlags(ctx, 'ConfigFlags_NoMouseCursorChange', config.flags, ImGui.ConfigFlags_NoMouseCursorChange)
      ImGui.SameLine(ctx); demo.HelpMarker('Instruct backend to not alter mouse cursor shape and visibility.')
      rv,config.flags = ImGui.CheckboxFlags(ctx, 'ConfigFlags_NoKeyboard', config.flags, ImGui.ConfigFlags_NoKeyboard)
      ImGui.SameLine(ctx); demo.HelpMarker('Instruct dear imgui to disable keyboard inputs and interactions.')

      demo.ConfigVarCheckbox('InputTrickleEventQueue')
      ImGui.SameLine(ctx); demo.HelpMarker('Enable input queue trickling: some types of events submitted during the same frame (e.g. button down + up) will be spread over multiple frames, improving interactions with low framerates.')
      -- ImGui.Checkbox(ctx, 'io.MouseDrawCursor', &io.MouseDrawCursor)
      -- ImGui.SameLine(ctx); HelpMarker('Instruct Dear ImGui to render a mouse cursor itself. Note that a mouse cursor rendered via your application GPU rendering path will feel more laggy than hardware cursor, but will be more in sync with your other visuals.\n\nSome desktop applications may use both kinds of cursors (e.g. enable software cursor only when resizing/dragging something).')

      -- ReaImGui
      rv,config.flags = ImGui.CheckboxFlags(ctx, 'ConfigFlags_NoSavedSettings', config.flags, ImGui.ConfigFlags_NoSavedSettings)
      ImGui.SameLine(ctx); demo.HelpMarker('Globally disable loading and saving state to an .ini file')

      ImGui.SeparatorText(ctx, 'Keyboard/Gamepad Navigation')
      -- demo.ConfigVarCheckbox('NavSwapGamepadButtons')
      demo.ConfigVarCheckbox('NavMoveSetMousePos')
      ImGui.SameLine(ctx); demo.HelpMarker('Directional/tabbing navigation teleports the mouse cursor.')
      demo.ConfigVarCheckbox('NavCaptureKeyboard')
      demo.ConfigVarCheckbox('NavEscapeClearFocusItem')
      ImGui.SameLine(ctx); demo.HelpMarker('Pressing Escape clears focused item.')
      demo.ConfigVarCheckbox('NavEscapeClearFocusWindow')
      ImGui.SameLine(ctx); demo.HelpMarker('Pressing Escape clears focused window.')
      demo.ConfigVarCheckbox('NavCursorVisibleAuto')
      ImGui.SameLine(ctx); demo.HelpMarker("Using directional navigation key makes the cursor visible. Mouse click hides the cursor.");
      demo.ConfigVarCheckbox('NavCursorVisibleAlways')
      ImGui.SameLine(ctx); demo.HelpMarker("Navigation cursor is always visible.")

      ImGui.SeparatorText(ctx, 'Docking')
      rv,config.flags = ImGui.CheckboxFlags(ctx, 'ConfigFlags_DockingEnable', config.flags, ImGui.ConfigFlags_DockingEnable)
      ImGui.SameLine(ctx)
      if ImGui.GetConfigVar(ctx, ImGui.ConfigVar_DockingWithShift) then
        demo.HelpMarker('Drag from window title bar or their tab to dock/undock. Hold Shift to enable docking.\n\nDrag from window menu button (upper-left button) to undock an entire node (all windows).')
      else
          demo.HelpMarker('Drag from window title bar or their tab to dock/undock. Hold Shift to disable docking.\n\nDrag from window menu button (upper-left button) to undock an entire node (all windows).')
      end
      if config.flags & ImGui.ConfigFlags_DockingEnable ~= 0 then
        ImGui.Indent(ctx)
        demo.ConfigVarCheckbox('DockingNoSplit')
        ImGui.SameLine(ctx); demo.HelpMarker('Simplified docking mode: disable window splitting, so docking is limited to merging multiple windows together into tab-bars.')
        demo.ConfigVarCheckbox('DockingWithShift')
        ImGui.SameLine(ctx); demo.HelpMarker('Enable docking when holding Shift only (allow to drop in wider space, reduce visual noise)')
        -- ImGui.Checkbox(ctx, 'io.ConfigDockingAlwaysTabBar', &io.ConfigDockingAlwaysTabBar)
        -- ImGui.SameLine(ctx); demo.HelpMarker('Create a docking node and tab-bar on single floating windows.')
        demo.ConfigVarCheckbox('DockingTransparentPayload')
        ImGui.SameLine(ctx); demo.HelpMarker('Make window or viewport transparent when docking and only display docking boxes on the target viewport.')
        ImGui.Unindent(ctx)
      end

      ImGui.SeparatorText(ctx, 'Multi-viewports')
      -- ImGui::CheckboxFlags("io.ConfigFlags: ViewportsEnable", &io.ConfigFlags, ImGuiConfigFlags_ViewportsEnable);
      -- ImGui::SameLine(); HelpMarker("[beta] Enable beta multi-viewports support. See ImGuiPlatformIO for details.");
      -- if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
      -- {
      --     ImGui::Indent();
      --     ImGui::Checkbox("io.ConfigViewportsNoAutoMerge", &io.ConfigViewportsNoAutoMerge);
      --     ImGui::SameLine(); HelpMarker("Set to make all floating imgui windows always create their own viewport. Otherwise, they are merged into the main host viewports when overlapping it.");
      --     ImGui::Checkbox("io.ConfigViewportsNoTaskBarIcon", &io.ConfigViewportsNoTaskBarIcon);
      --     ImGui::SameLine(); HelpMarker("Toggling this at runtime is normally unsupported (most platform backends won't refresh the task bar icon state right away).");
      demo.ConfigVarCheckbox('ViewportsNoDecoration')
      --     ImGui::Checkbox("io.ConfigViewportsNoDefaultParent", &io.ConfigViewportsNoDefaultParent);
      --     ImGui::SameLine(); HelpMarker("Toggling this at runtime is normally unsupported (most platform backends won't refresh the parenting right away).");
      --     ImGui::Unindent();
      -- }

      -- ImGui.SeparatorText(ctx, 'DPI/Scaling')
      -- ImGui::Checkbox("io.ConfigDpiScaleFonts", &io.ConfigDpiScaleFonts);
      -- ImGui::SameLine(); HelpMarker("Experimental: Automatically update style.FontScaleDpi when Monitor DPI changes. This will scale fonts but NOT style sizes/padding for now.");
      -- ImGui::Checkbox("io.ConfigDpiScaleViewports", &io.ConfigDpiScaleViewports);
      -- ImGui::SameLine(); HelpMarker("Experimental: Scale Dear ImGui and Platform Windows when Monitor DPI changes.");

      ImGui.SeparatorText(ctx, 'Windows')
      demo.ConfigVarCheckbox('WindowsResizeFromEdges')
      ImGui.SameLine(ctx); demo.HelpMarker('Enable resizing of windows from their edges and from the lower-left corner.')
      demo.ConfigVarCheckbox('WindowsMoveFromTitleBarOnly')
      ImGui.SameLine(ctx); demo.HelpMarker('Does not apply to windows without a title bar.')
      -- demo.ConfigVarCheckbox('WindowsCopyContentsWithCtrlC') -- [EXPERIMENTAL]
      -- ImGui.SameLine(ctx); demo.HelpMarker('*EXPERIMENTAL* Ctrl+C copy the contents of focused window into the clipboard.');
      demo.ConfigVarCheckbox('ScrollbarScrollByPage')
      ImGui.SameLine(ctx); demo.HelpMarker('Enable scrolling page by page when clicking outside the scrollbar grab.\nWhen disabled, always scroll to clicked location.\nWhen enabled, Shift+Click scrolls to clicked location.')

      ImGui.SeparatorText(ctx, 'Widgets')
      demo.ConfigVarCheckbox('InputTextCursorBlink')
      ImGui.SameLine(ctx); demo.HelpMarker('Enable blinking cursor (optional as some users consider it to be distracting).')
      demo.ConfigVarCheckbox('InputTextEnterKeepActive')
      ImGui.SameLine(ctx); demo.HelpMarker('Pressing Enter will keep item active and select contents (single-line only).')
      demo.ConfigVarCheckbox('DragClickToInputText')
      ImGui.SameLine(ctx); demo.HelpMarker("Enable turning DragXXX widgets into text input with a simple mouse click-release (without moving).")
      demo.ConfigVarCheckbox('MacOSXBehaviors')
      ImGui.SameLine(ctx); demo.HelpMarker('Swap Cmd<>Ctrl keys, enable various MacOS style behaviors.')
      ImGui.Text(ctx, "Also see Style->Rendering for rendering options.")

      -- Also read: https://github.com/ocornut/imgui/wiki/Error-Handling
      -- ImGui.SeparatorText(ctx, 'Error Handling')
      -- demo.ConfigVarCheckbox('ErrorRecovery')
      -- ImGui.SameLine(ctx); demo.HelpMarker(
      --   'Options to configure how we handle recoverable errors.\n\z
      --   - Error recovery is not perfect nor guaranteed! It is a feature to ease development.\n\z
      --   - You not are not supposed to rely on it in the course of a normal application run.\n\z
      --   - Always ensure that on programmers seat you have at minimum Asserts or Tooltips enabled when making direct imgui API call! \z
      --     Otherwise it would severely hinder your ability to catch and correct mistakes!')
      -- demo.ConfigVarCheckbox('ErrorRecoveryEnableAssert')
      -- demo.ConfigVarCheckbox('ErrorRecoveryEnableDebugLog')
      -- demo.ConfigVarCheckbox('ErrorRecoveryEnableTooltip')
      -- if ImGui.GetConfigVar(ctx, ImGui.ConfigVar_ErrorRecoveryEnableAssert) == 0 and
      --     ImGui.GetConfigVar(ctx, ImGui.ConfigVar_ErrorRecoveryEnableDebugLog) == 0 and
      --     ImGui.GetConfigVar(ctx, ImGui.ConfigVar_ErrorRecoveryEnableTooltip) == 0 then
      --   ImGui.SetConfigVar(ctx, ImGui.ConfigVar_ErrorRecoveryEnableAssert, 1)
      --   ImGui.SetConfigVar(ctx, ImGui.ConfigVar_ErrorRecoveryEnableDebugLog, 1)
      --   ImGui.SetConfigVar(ctx, ImGui.ConfigVar_ErrorRecoveryEnableTooltip, 1)
      -- end

      -- Also read: https://github.com/ocornut/imgui/wiki/Debug-Tools
      ImGui.SeparatorText(ctx, 'Debug')
      -- demo.ConfigVarCheckbox('DebugIsDebuggerPresent')
      -- ImGui.SameLine(ctx); demo.HelpMarker('Enable various tools calling IM_DEBUG_BREAK().\n\nRequires a debugger being attached, otherwise IM_DEBUG_BREAK() options will appear to crash your application.')
      demo.ConfigVarCheckbox('DebugHighlightIdConflicts')
      ImGui.SameLine(ctx); demo.HelpMarker('Highlight and show an error message when multiple items have conflicting identifiers.')
      ImGui.BeginDisabled(ctx)
      demo.ConfigVarCheckbox('DebugBeginReturnValueOnce')
      ImGui.EndDisabled(ctx)
      ImGui.SameLine(ctx); demo.HelpMarker('First calls to Begin()/BeginChild() will return false.\n\nTHIS OPTION IS DISABLED because it needs to be set at application boot-time to make sense. Showing the disabled option is a way to make this feature easier to discover')
      demo.ConfigVarCheckbox('DebugBeginReturnValueLoop')
      ImGui.SameLine(ctx); demo.HelpMarker('Some calls to Begin()/BeginChild() will return false.\n\nWill cycle through window depths then repeat. Windows should be flickering while running.')
      -- demo.ConfigVarCheckbox('DebugIgnoreFocusLoss')
      -- ImGui.SameLine(ctx); demo.HelpMarker('Option to deactivate io.AddFocusEvent(false) handling. May facilitate interactions with a debugger when focus loss leads to clearing inputs data.')
      -- demo.ConfigVarCheckbox('DebugIniSettings')
      -- ImGui.SameLine(ctx); demo.HelpMarker('Option to save .ini data with extra comments (particularly helpful for Docking, but makes saving slower).')

      ImGui.SeparatorText(ctx, 'Tooltips')
      for n = 0, 1 do
        if ImGui.TreeNode(ctx, n == 0 and 'HoverFlagsForTooltipMouse' or 'HoverFlagsForTooltipNav') then
          local var = n == 0 and ImGui.ConfigVar_HoverFlagsForTooltipMouse or ImGui.ConfigVar_HoverFlagsForTooltipNav
          local val = ImGui.GetConfigVar(ctx, var)
          rv, val = ImGui.CheckboxFlags(ctx, 'HoveredFlags_DelayNone',     val, ImGui.HoveredFlags_DelayNone)
          rv, val = ImGui.CheckboxFlags(ctx, 'HoveredFlags_DelayShort',    val, ImGui.HoveredFlags_DelayShort)
          rv, val = ImGui.CheckboxFlags(ctx, 'HoveredFlags_DelayNormal',   val, ImGui.HoveredFlags_DelayNormal)
          rv, val = ImGui.CheckboxFlags(ctx, 'HoveredFlags_Stationary',    val, ImGui.HoveredFlags_Stationary)
          rv, val = ImGui.CheckboxFlags(ctx, 'HoveredFlags_NoSharedDelay', val, ImGui.HoveredFlags_NoSharedDelay)
          ImGui.SetConfigVar(ctx, var, val)
          ImGui.TreePop(ctx)
        end
      end

      ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags, config.flags)
      ImGui.TreePop(ctx)
      ImGui.Spacing(ctx)
    end

    -- if ImGui.TreeNode(ctx, 'Backend Flags') then
    --   demo.HelpMarker(
    --     'Those flags are set by the backends (imgui_impl_xxx files) to specify their capabilities.\n\z
    --      Here we expose then as read-only fields to avoid breaking interactions with your backend.')
    --
    --   -- Make a local copy to avoid modifying actual backend flags.
    --   -- FIXME: Maybe we need a BeginReadonly() equivalent to keep label bright?
    --   ImGui.BeginDisabled(ctx)
    --   ImGui::CheckboxFlags("io.BackendFlags: HasGamepad",             &io.BackendFlags, ImGuiBackendFlags_HasGamepad);
    --   ImGui::CheckboxFlags("io.BackendFlags: HasMouseCursors",        &io.BackendFlags, ImGuiBackendFlags_HasMouseCursors);
    --   ImGui::CheckboxFlags("io.BackendFlags: HasSetMousePos",         &io.BackendFlags, ImGuiBackendFlags_HasSetMousePos);
    --   ImGui::CheckboxFlags("io.BackendFlags: PlatformHasViewports",   &io.BackendFlags, ImGuiBackendFlags_PlatformHasViewports);
    --   ImGui::CheckboxFlags("io.BackendFlags: HasMouseHoveredViewport",&io.BackendFlags, ImGuiBackendFlags_HasMouseHoveredViewport);
    --   ImGui::CheckboxFlags("io.BackendFlags: RendererHasVtxOffset",   &io.BackendFlags, ImGuiBackendFlags_RendererHasVtxOffset);
    --   ImGui::CheckboxFlags("io.BackendFlags: RendererHasTextures",    &io.BackendFlags, ImGuiBackendFlags_RendererHasTextures);
    --   ImGui::CheckboxFlags("io.BackendFlags: RendererHasViewports",   &io.BackendFlags, ImGuiBackendFlags_RendererHasViewports);
    --   ImGui.EndDisabled(ctx)
    --   ImGui.TreePop(ctx)
    --   ImGui.Spacing(ctx)
    -- end

    if ImGui.TreeNode(ctx, 'Style, Fonts') then
      rv, show_app.style_editor = ImGui.Checkbox(ctx, 'Style Editor', show_app.style_editor);
      ImGui.SameLine(ctx)
      demo.HelpMarker("The same contents can be accessed in 'Tools->Style Editor'.")
      ImGui.TreePop(ctx)
      ImGui.Spacing(ctx)
    end

    if ImGui.TreeNode(ctx, 'Capture/Logging') then
      if not config.logging then
        config.logging = {
          auto_open_depth = 2,
        }
      end

      demo.HelpMarker(
        'The logging API redirects all text output so you can easily capture the content of \z
         a window or a block. Tree nodes can be automatically expanded.\n\z
         Try opening any of the contents below in this window and then click one of the "Log To" button.')
      ImGui.PushID(ctx, 'LogButtons')
      local log_to_tty = ImGui.Button(ctx, 'Log To TTY'); ImGui.SameLine(ctx)
      local log_to_file = ImGui.Button(ctx, 'Log To File'); ImGui.SameLine(ctx)
      local log_to_clipboard = ImGui.Button(ctx, 'Log To Clipboard'); ImGui.SameLine(ctx)
      ImGui.PushItemFlag(ctx, ImGui.ItemFlags_NoTabStop, true)
      ImGui.SetNextItemWidth(ctx, 80.0)
      rv,config.logging.auto_open_depth =
        ImGui.SliderInt(ctx, 'Open Depth', config.logging.auto_open_depth, 0, 9)
      ImGui.PopItemFlag(ctx)
      ImGui.PopID(ctx)

      -- Start logging at the end of the function so that the buttons don't appear in the log
      local depth = config.logging.auto_open_depth
      if log_to_tty       then ImGui.LogToTTY(ctx, depth)       end
      if log_to_file      then ImGui.LogToFile(ctx, depth)      end
      if log_to_clipboard then ImGui.LogToClipboard(ctx, depth) end

      demo.HelpMarker('You can also call ImGui.LogText() to output directly to the log without a visual output.')
      if ImGui.Button(ctx, 'Copy "Hello, world!" to clipboard') then
        ImGui.LogToClipboard(ctx, depth)
        ImGui.LogText(ctx, 'Hello, world!')
        ImGui.LogFinish(ctx)
      end
      ImGui.TreePop(ctx)
    end
  end

end

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------
local function loop()
  ImGui.SetNextWindowSize(ctx, 550, 680, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Configuration', true)
  if visible then
    Show_Configuration()
    ImGui.End(ctx)
  end
  if open ~= false then
    reaper.defer(loop)
  end
end
reaper.defer(loop)
