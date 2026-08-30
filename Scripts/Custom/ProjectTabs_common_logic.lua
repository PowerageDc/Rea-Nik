-- ProjectTabs_common_logic.lua
-- Enumera los proyectos (tabs) abiertos en REAPER y arma el estado agregado
-- que consume el popup de selección de proyecto en nsaudio_remote_control.html.
--
-- Patrón de módulo de agregación (ver 01_CONVENCIONES.md):
--   read_aggregated_state() -> lógica pura, devuelve el string ya formateado
--   write_aggregated_state() -> llama a la anterior y escribe la ExtState
--
-- IMPORTANTE (lectura on-demand, NO forma parte del poll de fondo):
-- a diferencia de ReaPitchBus/MarkerBars, este módulo se dispara solo cuando
-- el usuario abre el popup de proyectos en el remoto (ver Nik_ProjectTabs_Read.lua
-- y PROJECTTABS_CMD_READ en el HTML) — decisión deliberada para no sumar el
-- costo de recorrer EnumProjects en cada tick del poll de 1000ms.
--
-- Formato ExtState escrito en "NikRemote/project_tabs":
--   "idx:nombre:esActivo;idx:nombre:esActivo;..."
-- - idx: índice tal cual lo devuelve EnumProjects (orden de tabs).
-- - nombre: nombre de archivo sin ruta ni extensión, o "(sin guardar)".
-- - esActivo: "1" si es el proyecto activo, "0" si no.

local M = {}

local function display_name(projfn)
    if projfn == "" then return "(sin guardar)" end
    local name = projfn:match("([^\\/]+)$") or projfn
    name = name:gsub("%.[Rr][Pp][Pp]$", "")
    return name
    end

function M.read_aggregated_state()
    local active_proj = reaper.EnumProjects(-1)
    local parts = {}
    local i = 0
    while true do
        local proj, projfn = reaper.EnumProjects(i)
        if not proj then break end
        local is_active = (proj == active_proj) and "1" or "0"
        parts[#parts + 1] = i .. ":" .. display_name(projfn) .. ":" .. is_active
        i = i + 1
        end
    return table.concat(parts, ";")
    end

function M.write_aggregated_state()
    reaper.SetExtState("NikRemote", "project_tabs", M.read_aggregated_state(), false)
    end

return M
