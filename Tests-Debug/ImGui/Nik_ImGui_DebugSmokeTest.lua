-- Nik_ImGui_DebugSmokeTest.lua
-- Smoke test minimo: confirma que Harness_common_logic.lua + Debug_common_logic.lua
-- levantan una ventana ImGui, corren el loop, y que Debug.Msg / el traceback
-- de pcallLoop funcionan como se espera.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Harness = dofile(script_dir .. "Harness_common_logic.lua")

Harness.Run({
  title = 'Mi Test',
  body = function(ImGui, ctx)
    ImGui.Text(ctx, 'Smoke test OK')

    -- Descomentar para forzar un error y confirmar que el traceback aparece
    -- completo en la consola (ver Debug_common_logic.lua / Harness.Run):
    -- local x = nil
    -- x.rompeme()
  end,
})
