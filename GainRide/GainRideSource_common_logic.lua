local M = {}

local function selected_tracks_or_item_tracks()
    local set, list = {}, {}
    local function add(tr)
        if tr and not set[tr] then
            set[tr] = true
            list[#list + 1] = tr
        end
    end
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        add(reaper.GetSelectedTrack(0, i))
    end
    if #list == 0 then
        for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
            add(reaper.GetMediaItemTrack(reaper.GetSelectedMediaItem(0, i)))
        end
    end
    return list
end

local function make_part(item, lo, hi)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local fin = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local t0 = lo and math.max(pos, lo) or pos
    local t1 = hi and math.min(fin, hi) or fin
    if t1 <= t0 then return nil end
    return { item = item, pos = pos, t0 = t0, t1 = t1 }
end

local function collect(mode)
    local by_track, order = {}, {}

    local function push(item, lo, hi)
        local part = make_part(item, lo, hi)
        if not part then return end
        local tr = reaper.GetMediaItemTrack(item)
        if not by_track[tr] then
            by_track[tr] = {}
            order[#order + 1] = tr
        end
        local list = by_track[tr]
        list[#list + 1] = part
    end

    if mode == "selected" then
        for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
            push(reaper.GetSelectedMediaItem(0, i), nil, nil)
        end
    elseif mode == "all" or mode == "timesel" then
        local lo, hi
        if mode == "timesel" then
            lo, hi = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
            if hi <= lo then return nil, "No hay time selection." end
        end
        for _, tr in ipairs(selected_tracks_or_item_tracks()) do
            for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
                push(reaper.GetTrackMediaItem(tr, i), lo, hi)
            end
        end
    else
        return nil, "Modo de fuente desconocido: " .. tostring(mode)
    end
    return { by_track = by_track, order = order }
end

function M.track_name(tr)
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    return name
end

-- Devuelve tramos {track, t0, t1, parts} en tiempo de proyecto. Las partes que
-- se tocan (o se solapan) dentro de la tolerancia se fusionan en un solo tramo,
-- para que el corte de un split no cuente como límite.
function M.resolve(mode, merge_tol_s)
    local found, err = collect(mode)
    if not found then return nil, err end
    local by_track, order = found.by_track, found.order

    local segments = {}
    for _, tr in ipairs(order) do
        local parts = by_track[tr]
        table.sort(parts, function(a, b) return a.t0 < b.t0 end)
        local cur
        for _, p in ipairs(parts) do
            if cur and p.t0 <= cur.t1 + merge_tol_s then
                cur.t1 = math.max(cur.t1, p.t1)
                cur.parts[#cur.parts + 1] = p
            else
                cur = { track = tr, t0 = p.t0, t1 = p.t1, parts = { p } }
                segments[#segments + 1] = cur
            end
        end
    end

    if #segments == 0 then return nil, "La fuente no produjo ningún tramo." end
    return segments
end

return M