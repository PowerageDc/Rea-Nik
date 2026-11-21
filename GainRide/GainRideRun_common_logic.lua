local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "GainRideSource_common_logic.lua")
local Analysis = dofile(script_dir .. "GainRideAnalysis_common_logic.lua")
local Segment = dofile(script_dir .. "GainRideSegment_common_logic.lua")
local Apply = dofile(script_dir .. "GainRideApply_common_logic.lua")

local M = {}

function M.analysis_opts(cfg)
    return {
        window_s = cfg.window_ms / 1000,
        sample_rate = cfg.sample_rate,
        floor_db = cfg.floor_db,
        lf_hz = cfg.lf_hz,
    }
end

-- Margen (en segundos) alrededor de un tramo donde se borran los puntos
-- existentes: la rampa más larga entre las generales y las de cada clase.
function M.margin_s(ap)
    local margin = math.max(ap.ramp_down_ms, ap.ramp_up_ms)
    for _, cc in pairs(ap.classes) do
        margin = math.max(margin, cc.ramp_down_ms or 0, cc.ramp_up_ms or 0)
    end
    return margin / 1000
end

-- Lee el audio de cada tramo. Es la parte lenta: devuelve las filas de nivel
-- para poder segmentar y planificar varias veces sin volver a leer.
function M.read(segments, cfg)
    local opts = M.analysis_opts(cfg)
    local reads = {}
    for _, seg in ipairs(segments) do
        reads[#reads + 1] = { seg = seg, rows = Analysis.segment_levels(seg, opts) }
    end
    return reads
end

-- Segmenta las filas leídas y agrupa por track. Las piezas de todos los
-- tramos de un mismo track forman una sola secuencia, para que las rampas
-- entre tramos vecinos no se pisen. Devuelve by_track[track] = { pieces,
-- ranges } y order, la lista de tracks en orden de aparición.
function M.build(reads, seg_cfg, window_ms, ap)
    local margin = M.margin_s(ap)
    local by_track, order = {}, {}
    for _, rd in ipairs(reads) do
        local seg = rd.seg
        local pieces = Segment.split(rd.rows, seg_cfg, window_ms)
        local entry = by_track[seg.track]
        if not entry then
            entry = { pieces = {}, ranges = {} }
            by_track[seg.track] = entry
            order[#order + 1] = seg.track
        end
        for _, pc in ipairs(pieces) do
            entry.pieces[#entry.pieces + 1] = pc
        end
        entry.ranges[#entry.ranges + 1] = { t0 = seg.t0 - margin, t1 = seg.t1 + margin }
    end
    return by_track, order
end

-- Planifica y escribe en el envelope de cada track. No abre bloque de undo.
-- Devuelve results (un item por track con piezas: name, pieces, points, info;
-- o name y empty si no hubo piezas) y missing, los nombres de los tracks sin
-- el envelope visible.
function M.write(order, by_track, ap)
    local results, missing = {}, {}
    for _, tr in ipairs(order) do
        local entry = by_track[tr]
        local name = Source.track_name(tr)
        if #entry.pieces == 0 then
            results[#results + 1] = { name = name, empty = true }
        else
            local env = reaper.GetTrackEnvelopeByName(tr, ap.envelope)
            if env then
                local pts, info = Apply.plan(entry.pieces, ap)
                Apply.write(env, pts, entry.ranges, ap)
                results[#results + 1] = {
                    name = name, pieces = #entry.pieces, points = #pts, info = info,
                }
            else
                missing[#missing + 1] = name
            end
        end
    end
    return results, missing
end

return M