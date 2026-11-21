local M = {}

local function rows_for(ms, window_ms)
    return math.max(1, math.floor(ms / window_ms + 0.5))
end

-- Promedio móvil del nivel en dB: quita el ruido de ventana a ventana
-- sin correr los bordes de la curva.
local function smooth(rows, n)
    local out, half = {}, math.floor(n / 2)
    for i = 1, #rows do
        local a, b = math.max(1, i - half), math.min(#rows, i + half)
        local sum = 0
        for k = a, b do sum = sum + rows[k].rms_db end
        out[i] = sum / (b - a + 1)
    end
    return out
end

-- Puerta con histéresis: abre sobre open_db, se mantiene sobre close_db y
-- solo corta cuando el silencio dura al menos gap_rows ventanas.
local function voiced_runs(rows, p)
    local runs = {}
    local open, first, last = false, 0, 0

    local function close_run()
        if last - first + 1 >= p.min_rows then
            runs[#runs + 1] = { i0 = first, i1 = last }
        end
        open = false
    end

    for i = 1, #rows do
        local db = rows[i].rms_db
        if open then
            if db >= p.close_db then
                last = i
            elseif i - last >= p.gap_rows then
                close_run()
            end
        elseif db >= p.open_db then
            open, first, last = true, i, i
        end
    end
    if open then close_run() end
    return runs
end

-- Corta una corrida cuando el nivel suavizado se aparta más de step_db del
-- promedio de la pieza en curso durante hold_rows ventanas seguidas; el corte
-- cae donde empezó la desviación.
local function split_by_level(s, run, p)
    local pieces = {}
    local start = run.i0
    local sum, count = 0, 0
    local dev_from, dev_count = nil, 0

    for i = run.i0, run.i1 do
        local ref = count > 0 and sum / count or s[i]
        if math.abs(s[i] - ref) > p.step_db then
            dev_from = dev_from or i
            dev_count = dev_count + 1
            if dev_count >= p.hold_rows then
                pieces[#pieces + 1] = { i0 = start, i1 = dev_from - 1 }
                start = dev_from
                sum, count = 0, 0
                for k = dev_from, i do
                    sum = sum + s[k]
                    count = count + 1
                end
                dev_from, dev_count = nil, 0
            end
        else
            dev_from, dev_count = nil, 0
            sum = sum + s[i]
            count = count + 1
        end
    end
    pieces[#pieces + 1] = { i0 = start, i1 = run.i1 }

    local merged = {}
    for _, pc in ipairs(pieces) do
        local prev = merged[#merged]
        if prev and (pc.i1 - pc.i0 + 1) < p.min_rows then
            prev.i1 = pc.i1
        else
            merged[#merged + 1] = pc
        end
    end
    if #merged > 1 and (merged[1].i1 - merged[1].i0 + 1) < p.min_rows then
        merged[2].i0 = merged[1].i0
        table.remove(merged, 1)
    end
    return merged
end

local function describe(rows, pc, win)
    local vals, peak = {}, -math.huge
    for i = pc.i0, pc.i1 do
        vals[#vals + 1] = rows[i].rms_db
        if rows[i].peak_db > peak then peak = rows[i].peak_db end
    end
    table.sort(vals)
    return {
        t0 = rows[pc.i0].t,
        t1 = rows[pc.i1].t + win,
        level_db = vals[math.ceil(#vals / 2)],
        peak_db = peak,
    }
end

-- Devuelve piezas {t0, t1, level_db (mediana del rms), peak_db} en tiempo de proyecto.
function M.split(rows, seg_cfg, window_ms)
    local smooth_rows = rows_for(seg_cfg.smooth_ms, window_ms)
    if smooth_rows % 2 == 0 then smooth_rows = smooth_rows + 1 end

    local p = {
        open_db = seg_cfg.open_db,
        close_db = seg_cfg.close_db,
        gap_rows = rows_for(seg_cfg.min_gap_ms, window_ms),
        min_rows = rows_for(seg_cfg.min_len_ms, window_ms),
        step_db = seg_cfg.level_split and seg_cfg.level_step_db or nil,
        hold_rows = rows_for(seg_cfg.level_hold_ms, window_ms),
    }

    local s = smooth(rows, smooth_rows)
    local out = {}
    for _, run in ipairs(voiced_runs(rows, p)) do
        local pieces = p.step_db and split_by_level(s, run, p) or { run }
        for _, pc in ipairs(pieces) do
            out[#out + 1] = describe(rows, pc, window_ms / 1000)
        end
    end
    return out
end

-- Vista previa: una región por pieza, con el prefijo en el nombre para poder
-- borrarlas sin tocar las regiones propias.
function M.clear_regions(prefix)
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, _, _, _, name = reaper.EnumProjectMarkers(i)
        if name:sub(1, #prefix) == prefix then
            reaper.DeleteProjectMarkerByIndex(0, i)
        end
    end
end

function M.add_regions(prefix, pieces, first_index)
    for i, pc in ipairs(pieces) do
        local name = string.format("%s%03d %.1f", prefix, first_index + i, pc.level_db)
        reaper.AddProjectMarker2(0, true, pc.t0, pc.t1, name, -1, 0)
    end
end

return M