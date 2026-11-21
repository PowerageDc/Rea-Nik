local M = {}

local EPS = 0.001

local function median(values)
    local s = {}
    for i, v in ipairs(values) do s[i] = v end
    table.sort(s)
    return s[math.ceil(#s / 2)]
end

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- Duración de la rampa según el sentido del cambio de ganancia.
local function ramp_s(ap, from_db, to_db, class)
    local cc = ap.classes[class] or ap.classes.voz
    local ms
    if to_db < from_db then
        ms = cc.ramp_down_ms or ap.ramp_down_ms
    else
        ms = cc.ramp_up_ms or ap.ramp_up_ms
    end
    return ms / 1000
end

-- Calcula los puntos del envelope para una secuencia de piezas ordenadas.
-- La ganancia de cada pieza es fuerza * clamp(objetivo - nivel) + offset, con
-- objetivo y offset de su clase. El cambio entre dos piezas termina justo donde 
-- empieza la siguiente; si están pegadas se centra en el límite y se acota a un 
-- cuarto de la pieza más corta.
function M.plan(pieces, ap)
    local n = #pieces

    local by_class = {}
    for _, pc in ipairs(pieces) do
        local list = by_class[pc.class]
        if not list then
            list = {}
            by_class[pc.class] = list
        end
        list[#list + 1] = pc.level_db
    end

    local tg = {}
    for c, list in pairs(by_class) do
        local cc = ap.classes[c] or ap.classes.voz
        tg[c] = cc.target_db == "median" and median(list) or cc.target_db
    end

    local gains, g_min, g_max = {}, math.huge, -math.huge
    local capped_down, capped_up = 0, 0
    for i, pc in ipairs(pieces) do
        local cc = ap.classes[pc.class] or ap.classes.voz
        local raw = tg[pc.class] - pc.level_db
        if raw < -ap.max_down_db then capped_down = capped_down + 1 end
        if raw > ap.max_up_db then capped_up = capped_up + 1 end
        local g = ap.strength * clamp(raw, -ap.max_down_db, ap.max_up_db) + (cc.offset_db or 0)
        gains[i] = g
        if g < g_min then g_min = g end
        if g > g_max then g_max = g end
    end

    local ins, outs = {}, {}
    for i, pc in ipairs(pieces) do
        ins[i], outs[i] = pc.t0, pc.t1
    end

    for i = 1, n - 1 do
        local a, b = pieces[i], pieces[i + 1]
        local r = ramp_s(ap, gains[i], gains[i + 1], b.class)
        local gap = b.t0 - a.t1
        if gap >= r then
            outs[i] = b.t0 - r
        elseif gap <= EPS then
            local half = math.min(r / 2, (a.t1 - a.t0) / 4, (b.t1 - b.t0) / 4)
            outs[i] = b.t0 - half
            ins[i + 1] = b.t0 + half
        end
    end

    local pts = {}
    local r_in = ramp_s(ap, 0, gains[1], pieces[1].class)
    pts[#pts + 1] = { t = ins[1] - r_in, db = 0, shape = ap.shape, tension = ap.tension }
    for i = 1, n do
        pts[#pts + 1] = { t = ins[i], db = gains[i], shape = 0, tension = 0 }
        pts[#pts + 1] = { t = outs[i], db = gains[i], shape = ap.shape, tension = ap.tension }
    end
    local r_out = ramp_s(ap, gains[n], 0, pieces[n].class)
    pts[#pts + 1] = { t = outs[n] + r_out, db = 0, shape = 0, tension = 0 }

    local parts = {}
    for _, c in ipairs({ "voz", "sib" }) do
        if tg[c] then parts[#parts + 1] = string.format("%s %.1f", c, tg[c]) end
    end

    return pts, {
        target_text = table.concat(parts, ", "),
        g_min = g_min,
        g_max = g_max,
        capped_down = capped_down,
        capped_up = capped_up,
    }
end

-- Escribe los puntos en el envelope. Los rangos son tiempos de proyecto donde
-- se borran los puntos existentes antes de insertar.
function M.write(env, pts, ranges, ap)
    local scaling = reaper.GetEnvelopeScalingMode(env)

    if not ap.keep_existing then
        for _, rg in ipairs(ranges) do
            reaper.DeleteEnvelopePointRangeEx(env, -1, rg.t0, rg.t1)
        end
    end

    for _, pt in ipairs(pts) do
        local value = reaper.ScaleToEnvelopeMode(scaling, 10 ^ (pt.db / 20))
        reaper.InsertEnvelopePointEx(env, -1, pt.t, value, pt.shape, pt.tension, false, true)
    end
    reaper.Envelope_SortPointsEx(env, -1)
end

return M