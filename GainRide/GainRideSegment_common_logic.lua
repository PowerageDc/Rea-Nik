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

local function classify(row, p)
    if row.hf >= p.sib_hf_min and row.zc_hz >= p.sib_hz_min then return "sib" end
    return "voz"
end

-- Separa una corrida por clase (sibilante o voz) según los rasgos de cada
-- ventana. Las ráfagas más cortas que class_rows se absorben en la vecina para
-- que una sola ventana ruidosa no parta la pieza.
local function split_by_class(rows, run, p)
    if not p.classify then
        return { { i0 = run.i0, i1 = run.i1, class = "voz" } }
    end

    local raw = {}
    for i = run.i0, run.i1 do
        local c = classify(rows[i], p)
        local last = raw[#raw]
        if last and last.class == c then
            last.i1 = i
        else
            raw[#raw + 1] = { i0 = i, i1 = i, class = c }
        end
    end

    local merged = {}
    for _, pc in ipairs(raw) do
        local prev = merged[#merged]
        if prev and (prev.class == pc.class or (pc.i1 - pc.i0 + 1) < p.class_rows) then
            prev.i1 = pc.i1
        else
            merged[#merged + 1] = pc
        end
    end
    if #merged > 1 and (merged[1].i1 - merged[1].i0 + 1) < p.class_rows then
        merged[2].i0 = merged[1].i0
        table.remove(merged, 1)
    end
    return merged
end

-- Un plosivo empieza en una ventana con mucha energía grave, una subida brusca
-- respecto de la anterior y una ventana previa de nivel bajo (la oclusión).
local function is_onset(rows, i, p)
    if i < 2 then return false end
    local r, prev = rows[i], rows[i - 1]
    return r.lf >= p.plo_lf_min
        and r.rms_db - prev.rms_db >= p.plo_rise_db
        and prev.rms_db <= p.plo_pre_db
end

-- Recorta de cada pieza las ventanas del plosivo (plo_rows desde el ataque).
-- Si lo que sobra después es más corto que class_rows, se suma al plosivo.
local function carve_plosives(rows, pieces, p)
    if not p.plosive then return pieces end
    local out = {}
    for _, pc in ipairs(pieces) do
        local cur, i = pc.i0, pc.i0
        while i <= pc.i1 do
            if is_onset(rows, i, p) then
                if i > cur then
                    out[#out + 1] = { i0 = cur, i1 = i - 1, class = pc.class }
                end
                local last = math.min(pc.i1, i + p.plo_rows - 1)
                if pc.i1 - last < p.class_rows then last = pc.i1 end
                out[#out + 1] = { i0 = i, i1 = last, class = "plo" }
                cur, i = last + 1, last + 1
            else
                i = i + 1
            end
        end
        if cur <= pc.i1 then
            out[#out + 1] = { i0 = cur, i1 = pc.i1, class = pc.class }
        end
    end
    return out
end

local function describe(rows, pc, win)
    local vals, peak, hf, zc, lf = {}, -math.huge, 0, 0, 0
    for i = pc.i0, pc.i1 do
        local r = rows[i]
        vals[#vals + 1] = r.rms_db
        if r.peak_db > peak then peak = r.peak_db end
        hf = hf + r.hf
        zc = zc + r.zc_hz
        lf = lf + r.lf
    end
    table.sort(vals)
    local n = pc.i1 - pc.i0 + 1
    return {
        t0 = rows[pc.i0].t,
        t1 = rows[pc.i1].t + win,
        level_db = vals[math.ceil(#vals / 2)],
        peak_db = peak,
        class = pc.class,
        hf = hf / n,
        zc_hz = zc / n,
        lf = lf / n,
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
        classify = seg_cfg.classify,
        sib_hf_min = seg_cfg.sib_hf_min,
        sib_hz_min = seg_cfg.sib_hz_min,
        class_rows = rows_for(seg_cfg.class_min_ms, window_ms),
        plosive = seg_cfg.plosive,
        plo_lf_min = seg_cfg.plo_lf_min,
        plo_rise_db = seg_cfg.plo_rise_db,
        plo_pre_db = seg_cfg.plo_pre_db,
        plo_rows = rows_for(seg_cfg.plo_ms, window_ms),
    }

    local s = smooth(rows, smooth_rows)
    local out = {}
    for _, run in ipairs(voiced_runs(rows, p)) do
        for _, cp in ipairs(carve_plosives(rows, split_by_class(rows, run, p), p)) do
            local pieces = p.step_db and split_by_level(s, cp, p) or { cp }
            for _, pc in ipairs(pieces) do
                pc.class = cp.class
                out[#out + 1] = describe(rows, pc, window_ms / 1000)
            end
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

local CLASS_COLORS = {
    sib = { 255, 140, 0 },
    voz = { 70, 130, 220 },
    plo = { 200, 60, 200 },
}

function M.add_regions(prefix, pieces, first_index)
    for i, pc in ipairs(pieces) do
        local name = string.format("%s%03d %s %.1f", prefix, first_index + i, pc.class, pc.level_db)
        local c = CLASS_COLORS[pc.class] or CLASS_COLORS.voz
        reaper.AddProjectMarker2(0, true, pc.t0, pc.t1, name, -1,
            reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000)
    end
end

return M