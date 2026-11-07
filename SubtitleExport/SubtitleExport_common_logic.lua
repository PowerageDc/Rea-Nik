-- Lógica pura de SubtitleExport: de eventos de acorde en segundos a entradas
-- de subtítulo y a texto SRT. No usa la API de REAPER.
--
-- Evento: { t = segundos (tiempo de proyecto), chord = string | nil }
--   chord nil (o vacío) es silencio: corta el acorde anterior y no genera subtítulo.
-- Entrada: { start = segundos, stop = segundos, text = string }, relativa a t0.

local M = {}

-- Aplica las reglas de display al acorde. Devuelve nil si es silencio.
function M.formatChord(chord, rules)
    if chord == nil then return nil end
    local s = chord:match("^%s*(.-)%s*$")
    if s == "" then return nil end
    for _, rule in ipairs(rules or {}) do
        s = (s:gsub(rule[1], rule[2]))
    end
    return s
end

-- Convierte eventos a entradas dentro de la ventana [t0, t_end).
-- opts: { rules, gap_ms, carry_in, transpose, offset_s }
-- offset_s (opcional): segundos que se suman a todos los tiempos de salida.
-- transpose (opcional): function(chord) -> chord, se aplica antes del formato de display.
function M.buildEntries(events, t0, t_end, opts)
    opts = opts or {}
    local gap = (opts.gap_ms or 0) / 1000
    local offset = opts.offset_s or 0

    -- Copia ordenada por tiempo (desempate por posición original).
    local sorted = {}
    for i, ev in ipairs(events) do
        sorted[i] = { t = ev.t, chord = ev.chord, idx = i }
    end
    table.sort(sorted, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.idx < b.idx
    end)

    -- Eventos dentro de la ventana; el último previo a t0 queda como "vigente".
    local timeline, carry = {}, nil
    for _, ev in ipairs(sorted) do
        if ev.t < t0 then
            carry = ev
        elseif ev.t < t_end then
            timeline[#timeline + 1] = ev
        end
    end
    if opts.carry_in and carry and (#timeline == 0 or timeline[1].t > t0) then
        table.insert(timeline, 1, { t = t0, chord = carry.chord })
    end

    local entries = {}
    for i, ev in ipairs(timeline) do
        local chord = ev.chord
        if chord and opts.transpose then chord = opts.transpose(chord) end
        local text = M.formatChord(chord, opts.rules)
        if text then
            local nxt = timeline[i + 1]
            local stop = nxt and (nxt.t - gap) or t_end
            local start = ev.t
            if stop > start then
                entries[#entries + 1] = {
                    start = start - t0 + offset,
                    stop = stop - t0 + offset,
                    text = text,
                }
            end
        end
    end
    return entries
end

-- Segundos a "hh:mm:ss,mmm".
function M.srtTime(seconds)
    local total_ms = math.floor(math.max(seconds, 0) * 1000 + 0.5)
    local ms = total_ms % 1000
    local total_s = math.floor(total_ms / 1000)
    local s = total_s % 60
    local m = math.floor(total_s / 60) % 60
    local h = math.floor(total_s / 3600)
    return string.format("%02d:%02d:%02d,%03d", h, m, s, ms)
end

-- Entradas a texto SRT. opts: { newline, bom }
function M.toSrt(entries, opts)
    opts = opts or {}
    local nl = opts.newline or "\r\n"
    local out = {}
    for i, e in ipairs(entries) do
        out[#out + 1] = i .. nl
            .. M.srtTime(e.start) .. " --> " .. M.srtTime(e.stop) .. nl
            .. e.text .. nl .. nl
    end
    local body = table.concat(out)
    if opts.bom then body = "\239\187\191" .. body end
    return body
end

-- Parsea harmony_data: JSON compacto { "<compás>": [ {qn_offset, chord}, ... ] }.
-- Devuelve eventos { measure, qn_offset, chord }, con chord nil para silencio (null).
function M.parseHarmony(json)
    local events = {}
    if not json or json == "" then return events end
    for measure_str, events_str in json:gmatch('"(%d+)"%s*:%s*%[(.-)%]') do
        local measure = tonumber(measure_str)
        for qn_str, chord_str in events_str:gmatch('"qn_offset"%s*:%s*([%d%.]+).-"chord"%s*:%s*"?([^",}]*)"?') do
            local chord = chord_str
            if chord == "null" or chord == "" then chord = nil end
            events[#events + 1] = {
                measure = measure,
                qn_offset = tonumber(qn_str) or 0,
                chord = chord,
            }
        end
    end
    return events
end

-- Parsea project_key. Devuelve { tonic, mode } o nil si falta alguno de los dos.
function M.parseKey(json)
    if not json or json == "" then return nil end
    local tonic = json:match('"tonic"%s*:%s*"([^"]*)"')
    local mode = json:match('"mode"%s*:%s*"([^"]*)"')
    if tonic and mode then return { tonic = tonic, mode = mode } end
    return nil
end

-- Interpreta el semitono agregado de ReaPitch: devuelve "none", "mixed",
-- "value" y el entero (la parte entera del string, truncada hacia cero), o "invalid".
function M.parseSemitones(s)
    if s == "none" then return "none" end
    if s == "mixed" then return "mixed" end
    local n = tonumber(tostring(s or ""):match("^%s*([+-]?%d+)"))
    if n then return "value", n end
    return "invalid"
end

-- "RRGGBB" a tag de color de ASS (que usa orden BGR).
local function colorTag(hex)
    local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return "" end
    return ("\\c&H%s%s%s&"):format(b:upper(), g:upper(), r:upper())
end

-- Generadores de efecto: reciben la duración de la fase (ms) y las opciones.
local EFFECTS = {
    fade = function(p)
        return ("\\fad(%d,%d)"):format(p, p)
    end,
    grow = function(p)
        return ("\\fscx0\\fscy0\\t(0,%d,\\fscx100\\fscy100)"):format(p)
    end,
    bounce = function(p)
        local half = math.floor(p / 2)
        return ("\\t(0,%d,\\fscx125\\fscy125)\\t(%d,%d,\\fscx100\\fscy100)"):format(half, half, p)
    end,
    wipe = function(p, o)
        return ("\\clip(0,0,0,%d)\\t(0,%d,\\clip(0,0,%d,%d))"):format(
            o.video_height, p, o.video_width, o.video_height)
    end,
}

-- Bloque de tags ASS para una línea, o "" si el estilo no define nada.
-- style: { an, pos = {x, y}, fn, fs, color, effect }
-- opts: { effect_ms, effect_max_ratio, short_ms, slide_px, video_width, video_height }
function M.buildTags(style, duration_s, opts)
    opts = opts or {}
    local parts = {}
    if style.an then parts[#parts + 1] = "\\an" .. style.an end

    -- Fase del efecto: acotada por la duración de la línea; 0 si la línea es corta.
    local p = 0
    local dur_ms = duration_s * 1000
    if style.effect and dur_ms >= (opts.short_ms or 0) then
        p = math.floor(math.min(opts.effect_ms or 300, dur_ms * (opts.effect_max_ratio or 0.25)))
    end

    if style.effect == "slide" and style.pos and p > 0 then
        local x, y = style.pos[1], style.pos[2]
        parts[#parts + 1] = ("\\move(%d,%d,%d,%d,0,%d)"):format(x - (opts.slide_px or 400), y, x, y, p)
    elseif style.pos then
        parts[#parts + 1] = ("\\pos(%d,%d)"):format(style.pos[1], style.pos[2])
    end

    if style.fn then parts[#parts + 1] = "\\fn" .. style.fn end
    if style.fs then parts[#parts + 1] = "\\fs" .. style.fs end
    if style.color then parts[#parts + 1] = colorTag(style.color) end

    local generator = EFFECTS[style.effect]
    if generator and p > 0 then parts[#parts + 1] = generator(p, opts) end

    if #parts == 0 then return "" end
    return "{" .. table.concat(parts) .. "}"
end

-- Antepone a cada entrada los tags de su estilo. Con opts.tags == false (o sin
-- estilo) devuelve las entradas sin tocar.
function M.styleEntries(entries, style, opts)
    opts = opts or {}
    if opts.tags == false or not style then return entries end
    local styled = {}
    for i, e in ipairs(entries) do
        styled[i] = {
            start = e.start,
            stop = e.stop,
            text = M.buildTags(style, e.stop - e.start, opts) .. e.text,
        }
    end
    return styled
end

return M