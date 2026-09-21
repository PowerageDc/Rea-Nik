-- MusicStateBridge_common_logic.lua
-- Puente ProjExtState -> ExtState global para la feature MusicState.
-- ProjExtState no es legible directo desde el Web Control (confirmado,
-- ver IMPL_MusicState.md seccion 2) -- este modulo centraliza el copiado,
-- consumido por Nik_MusicState_PublishAll.lua y por el Helper UI.

local M = {}

M.NAMESPACE = "NSAUDIOMUSIC"
M.BRIDGE_NAMESPACE = "NikMusicState"
M.KEYS = { "harmony_data", "project_key", "project_roles", "cues_data", "publish_version" }

-- Copia una key de ProjExtState a ExtState global.
-- Retorna: ok (bool), value_or_nil (string)
function M.bridgeKey(proj, key)
    local retval, value = reaper.GetProjExtState(proj, M.NAMESPACE, key)
    if retval > 0 and value ~= "" then
        reaper.SetExtState(M.BRIDGE_NAMESPACE, key, value, false)
        return true, value
    end
    -- Sin dato para este proyecto: limpiar el puente en vez de dejar
    -- pegado el valor del proyecto anterior (bug real, confirmado con
    -- caso "tab unsaved hereda project_key de sesion de prueba previa").
    reaper.DeleteExtState(M.BRIDGE_NAMESPACE, key, false)
    return false, nil
end

-- Copia las 4 keys conocidas de la feature.
-- Retorna: ok_count (number), failed_keys (array de strings)
function M.bridgeAll(proj)
    local ok_count = 0
    local failed = {}
    for _, key in ipairs(M.KEYS) do
        local ok = M.bridgeKey(proj, key)
        if ok then
            ok_count = ok_count + 1
        else
            table.insert(failed, key)
        end
    end
    return ok_count, failed
end

return M