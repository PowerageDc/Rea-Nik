-- @description Nik ProjectFolder - Abrir carpetas del proyecto (raiz, Media, Render)
-- @version 1.0
-- @author Nik
-- @metapackage
-- @provides
--   [main] .
--   [main] Nik_ProjectFolder_OpenMedia.lua
--   [main] Nik_ProjectFolder_OpenRender.lua
--   ProjectFolder_common_logic.lua
--   ProjectFolder_config.lua
-- @about
--   Scripts de Action List para abrir en el explorador la carpeta raiz,
--   Media o Render del proyecto activo. Usa CF_ShellExecute (SWS) cuando
--   esta disponible.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
dofile(script_dir .. "ProjectFolder_common_logic.lua").run("root")