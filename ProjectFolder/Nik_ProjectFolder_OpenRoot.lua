-- @description Nik ProjectFolder - Abrir carpetas del proyecto (raiz, Media, Render)
-- @version 1.2
-- @changelog
--   Modificado: las rutas del proyecto (raíz, Media, Render) pasan a un módulo compartido, sin cambios visibles
-- @author Nik
-- @metapackage
-- @provides
--   [main] .
--   [main] Nik_ProjectFolder_OpenMedia.lua
--   [main] Nik_ProjectFolder_OpenRender.lua
--   ProjectFolder_common_logic.lua
--   ProjectFolder_config.lua
--   ../_Shared/ProjectPaths_common_logic.lua
-- @about
--   Scripts de Action List para abrir en el explorador la carpeta raiz,
--   Media o Render del proyecto activo. Usa CF_ShellExecute (SWS) cuando
--   esta disponible.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
dofile(script_dir .. "ProjectFolder_common_logic.lua").run("root")