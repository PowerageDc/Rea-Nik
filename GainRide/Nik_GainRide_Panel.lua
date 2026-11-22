local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "GainRideSource_common_logic.lua")
local Segment = dofile(script_dir .. "GainRideSegment_common_logic.lua")
local Apply = dofile(script_dir .. "GainRideApply_common_logic.lua")
local Run = dofile(script_dir .. "GainRideRun_common_logic.lua")
local cfg = dofile(script_dir .. "GainRide_config.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")
local Tips = dofile(script_dir .. "GainRideTips_common_logic.lua")

local TITLE = "GainRide"

local MODES = {
    { id = "selected", label = "Items sel." },
    { id = "all", label = "Tracks sel." },
    { id = "timesel", label = "Time selection" },
}

local SHAPE_NAMES = { "Lineal", "Cuadrada", "Inicio y fin lentos", "Inicio rápido", "Final rápido", "Bézier" }

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep_copy(x) end
    return out
end

-- Parámetros editables: parten de la config y el panel los modifica en memoria.
local P = { mode = cfg.apply.mode }

local function load_defaults()
    P.read = {
        window_ms = cfg.window_ms,
        sample_rate = cfg.sample_rate,
        floor_db = cfg.floor_db,
        lf_hz = cfg.lf_hz,
    }
    P.seg = deep_copy(cfg.seg)
    P.apply = deep_copy(cfg.apply)
    for _, cc in pairs(P.apply.classes) do
        cc.offset_db = cc.offset_db or 0
    end
    for _, c in ipairs({ "sib", "plo" }) do
        local cc = P.apply.classes[c]
        cc.ramp_down_ms = cc.ramp_down_ms or P.apply.ramp_down_ms
        cc.ramp_up_ms = cc.ramp_up_ms or P.apply.ramp_up_ms
    end
end
load_defaults()

-- reads: filas de nivel por tramo (resultado de la lectura de audio).
-- analyze: 0 sin pedido, 2 pedido hecho, 1 se lee al final de este frame.
local S = {
    reads = nil,
    read_cfg = nil,
    msg = "Sin analizar.",
    analyze = 0,
    dirty = false,
    last_refresh = 0,
    preview = false,
    lanes = {},
    sel = 1,
    follow = false,
}

local ctx = reaper.ImGui_CreateContext(TITLE)
local focus_tick = EditorFocus.new(ctx, reaper.GetMainHwnd)
local WIN_FLAGS = reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoNav()

local function reads_valid(reads)
    for _, rd in ipairs(reads) do
        if not reaper.ValidatePtr2(0, rd.seg.track, "MediaTrack*") then return false end
        for _, part in ipairs(rd.seg.parts) do
            if not reaper.ValidatePtr2(0, part.item, "MediaItem*") then return false end
        end
    end
    return true
end

local function analyze()
    local segments, err = Source.resolve(P.mode, cfg.merge_tolerance_ms / 1000)
    if not segments then
        S.reads, S.msg, S.lanes = nil, err, {}
        return
    end
    local t0 = reaper.time_precise()
    S.read_cfg = deep_copy(P.read)
    S.reads = Run.read(segments, S.read_cfg)
    local dur = 0
    for _, seg in ipairs(segments) do dur = dur + (seg.t1 - seg.t0) end
    S.msg = string.format("Analizado: %d tramos, %.1f s de audio, lectura %.1f s",
        #segments, dur, reaper.time_precise() - t0)
    S.dirty = true
end

local function apply()
    if not S.reads then return end
    if not reads_valid(S.reads) then
        S.reads, S.msg = nil, "Los items cambiaron: analizá de nuevo."
        return
    end

    local by_track, order = Run.build(S.reads, P.seg, S.read_cfg.window_ms, P.apply)

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    local results, missing = Run.write(order, by_track, P.apply)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("GainRide: puntos de ganancia en el envelope", -1)

    local tracks, pieces, points = 0, 0, 0
    for _, r in ipairs(results) do
        if not r.empty then
            tracks = tracks + 1
            pieces = pieces + r.pieces
            points = points + r.points
        end
    end
    S.msg = string.format("Aplicado: %d tracks, %d piezas, %d puntos", tracks, pieces, points)
    if #missing > 0 then
        S.msg = S.msg .. " | Sin el envelope '" .. P.apply.envelope .. "' visible en: "
            .. table.concat(missing, ", ")
    end
end

local function clear_preview()
    reaper.Undo_BeginBlock()
    Segment.clear_regions(cfg.preview_prefix)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("GainRide: borrar piezas de vista previa", -1)
end

local function read_stale()
    if not S.reads then return false end
    for k, v in pairs(S.read_cfg) do
        if P.read[k] ~= v then return true end
    end
    return false
end

-- Segmenta y planifica sobre las filas en memoria. Con la vista previa
-- activa, rehace también las regiones.
local function refresh()
    S.dirty = false
    S.lanes = {}
    if not S.reads then return end
    if not reads_valid(S.reads) then
        S.reads, S.msg = nil, "Los items cambiaron: analizá de nuevo."
        return
    end

    reaper.PreventUIRefresh(1)
    local by_track, order = Run.build(S.reads, P.seg, S.read_cfg.window_ms, P.apply)
    if S.preview then Segment.clear_regions(cfg.preview_prefix) end

    local first = 0
    for _, tr in ipairs(order) do
        local pieces = by_track[tr].pieces
        local n = { voz = 0, sib = 0, plo = 0 }
        for _, pc in ipairs(pieces) do
            n[pc.class] = (n[pc.class] or 0) + 1
        end
        local lane = {
            tr = tr,
            name = Source.track_name(tr),
            pieces = pieces,
            line1 = string.format("piezas %d (voz %d, sib %d, plo %d)", #pieces, n.voz, n.sib, n.plo),
            line2 = "sin piezas en este track",
        }
        if #pieces > 0 then
            local pts, info = Apply.plan(pieces, P.apply)
            lane.pts = pts
            lane.line1 = lane.line1 .. string.format(" | topes bajar %d, subir %d",
                info.capped_down, info.capped_up)
            lane.line2 = string.format("objetivo %s dB | ganancia [%.1f, %+.1f] dB",
                info.target_text, info.g_min, info.g_max)
            if S.preview then
                Segment.add_regions(cfg.preview_prefix, pieces, first)
                first = first + #pieces
            end
        end
        S.lanes[#S.lanes + 1] = lane
    end
    if S.sel > #S.lanes then S.sel = math.max(1, #S.lanes) end
    reaper.PreventUIRefresh(-1)
    if S.preview then reaper.UpdateArrange() end
end

local function hover_flag(name)
    local f = reaper["ImGui_HoveredFlags_" .. name]
    return f and f() or 0
end
local HOVER = hover_flag("AllowWhenDisabled") | hover_flag("DelayShort")
local TIP_WIDTH = 60
local tip_text = {}

-- SetTooltip no corta líneas: se envuelve el texto a mano y se guarda.
local function wrap(text)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        if #line > 0 and #line + #word + 1 > TIP_WIDTH then
            lines[#lines + 1] = line
            line = word
        else
            line = #line > 0 and (line .. " " .. word) or word
        end
    end
    lines[#lines + 1] = line
    return table.concat(lines, "\n")
end

-- Tooltip del último item dibujado. No aparece mientras se arrastra.
local function tip(id)
    local text = Tips[id]
    if not text then return end
    if reaper.ImGui_IsItemActive(ctx) or not reaper.ImGui_IsItemHovered(ctx, HOVER) then return end
    if not tip_text[id] then tip_text[id] = wrap(text) end
    reaper.ImGui_SetTooltip(ctx, tip_text[id])
end

local CLAMP = reaper.ImGui_SliderFlags_AlwaysClamp()
local LABEL_W = 190

local function sl_int(id, text, tbl, key, lo, hi, fmt)
    reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
    local ch, v = reaper.ImGui_SliderInt(ctx, text .. "##" .. id,
        math.floor(tbl[key] + 0.5), lo, hi, fmt or "%d", CLAMP)
    tip(id)
    if ch then
        tbl[key] = v
        S.dirty = true
    end
    return ch
end

local function sl_dbl(id, text, tbl, key, lo, hi, fmt)
    reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
    local ch, v = reaper.ImGui_SliderDouble(ctx, text .. "##" .. id, tbl[key], lo, hi, fmt or "%.2f", CLAMP)
    tip(id)
    if ch then
        tbl[key] = v
        S.dirty = true
    end
    return ch
end

local function check(id, text, tbl, key)
    local ch, v = reaper.ImGui_Checkbox(ctx, text .. "##" .. id, tbl[key])
    tip(id)
    if ch then
        tbl[key] = v
        S.dirty = true
    end
end

local function tab_pieces()
    local sg = P.seg
    local ch_o = sl_dbl("open", "Abre (dB)", sg, "open_db", -80, -10, "%.1f dB")
    local ch_c = sl_dbl("close", "Cierra (dB)", sg, "close_db", -80, -10, "%.1f dB")
    if sg.close_db > sg.open_db then
        if ch_o then sg.close_db = sg.open_db else sg.open_db = sg.close_db end
    end
    sl_int("gap", "Silencio mínimo para cortar", sg, "min_gap_ms", 20, 1000, "%d ms")
    sl_int("len", "Duración mínima", sg, "min_len_ms", 20, 500, "%d ms")
    sl_int("smooth", "Suavizado del nivel", sg, "smooth_ms", 20, 300, "%d ms")
    reaper.ImGui_Separator(ctx)
    check("lsplit", "Cortar por cambios de nivel", sg, "level_split")
    reaper.ImGui_BeginDisabled(ctx, not sg.level_split)
    sl_dbl("lstep", "Desvío para cortar", sg, "level_step_db", 1, 12, "%.1f dB")
    sl_int("lhold", "Debe durar", sg, "level_hold_ms", 20, 300, "%d ms")
    reaper.ImGui_EndDisabled(ctx)
end

local function tab_classes()
    local sg = P.seg
    check("classify", "Detectar sibilantes", sg, "classify")
    reaper.ImGui_BeginDisabled(ctx, not sg.classify)
    sl_dbl("hf", "Agudos mínimos (hf)", sg, "sib_hf_min", 0, 1, "%.2f")
    sl_int("hz", "Frecuencia mínima (zc)", sg, "sib_hz_min", 1000, 8000, "%d Hz")
    reaper.ImGui_EndDisabled(ctx)
    sl_int("cmin", "Duración mínima de clase", sg, "class_min_ms", 20, 300, "%d ms")
    reaper.ImGui_Separator(ctx)
    check("plosive", "Detectar plosivos", sg, "plosive")
    reaper.ImGui_BeginDisabled(ctx, not sg.plosive)
    sl_dbl("plf", "Graves mínimos (lf)", sg, "plo_lf_min", 0, 1, "%.2f")
    sl_dbl("prise", "Subida mínima", sg, "plo_rise_db", 3, 30, "%.1f dB")
    sl_dbl("ppre", "Nivel previo máximo", sg, "plo_pre_db", -70, -20, "%.1f dB")
    sl_int("pms", "Duración del plosivo", sg, "plo_ms", 10, 120, "%d ms")
    reaper.ImGui_EndDisabled(ctx)
end

local function tab_gain()
    local ap = P.apply
    sl_dbl("strength", "Fuerza", ap, "strength", 0, 1, "%.2f")
    sl_dbl("down", "Tope al bajar", ap, "max_down_db", 0, 24, "%.1f dB")
    sl_dbl("up", "Tope al subir", ap, "max_up_db", 0, 12, "%.1f dB")
    sl_int("rdown", "Rampa al bajar", ap, "ramp_down_ms", 0, 500, "%d ms")
    sl_int("rup", "Rampa al subir", ap, "ramp_up_ms", 0, 1000, "%d ms")
    reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
    local shape_open = reaper.ImGui_BeginCombo(ctx, "Forma de rampa##shape", SHAPE_NAMES[ap.shape + 1])
    tip("shape")
    if shape_open then
        for i, name in ipairs(SHAPE_NAMES) do
            if reaper.ImGui_Selectable(ctx, name .. "###shape" .. i, ap.shape == i - 1) then
                ap.shape = i - 1
                S.dirty = true
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_BeginDisabled(ctx, ap.shape ~= 5)
    sl_dbl("tension", "Tensión (Bézier)", ap, "tension", -1, 1, "%.2f")
    reaper.ImGui_EndDisabled(ctx)
    check("keep", "Conservar puntos existentes", ap, "keep_existing")
end

local function tab_by_class()
    local ap = P.apply
    reaper.ImGui_Text(ctx, "Voz")
    sl_dbl("voz_off", "Offset", ap.classes.voz, "offset_db", -12, 6, "%.1f dB")
    reaper.ImGui_Text(ctx, "Sibilante")
    sl_dbl("sib_off", "Offset", ap.classes.sib, "offset_db", -12, 6, "%.1f dB")
    sl_int("sib_rd", "Rampa al bajar", ap.classes.sib, "ramp_down_ms", 0, 500, "%d ms")
    sl_int("sib_ru", "Rampa al subir", ap.classes.sib, "ramp_up_ms", 0, 1000, "%d ms")
    reaper.ImGui_Text(ctx, "Plosivo")
    sl_dbl("plo_off", "Offset", ap.classes.plo, "offset_db", -12, 6, "%.1f dB")
    sl_int("plo_rd", "Rampa al bajar", ap.classes.plo, "ramp_down_ms", 0, 500, "%d ms")
    sl_int("plo_ru", "Rampa al subir", ap.classes.plo, "ramp_up_ms", 0, 1000, "%d ms")
end

local function tab_read()
    reaper.ImGui_TextWrapped(ctx, "Estos valores obligan a analizar de nuevo.")
    sl_int("win", "Ventana", P.read, "window_ms", 5, 100, "%d ms")
    sl_int("lf", "Corte de graves (lf)", P.read, "lf_hz", 50, 500, "%d Hz")
end

local LEVEL_H, GAIN_H, GAP = 76, 46, 4
local LV_LO, LV_HI = -80, 0
local VIEW_PAD_S = 0.5

-- Fracción del cambio de una rampa en 11 puntos equiespaciados (0 a 1), medida
-- en un envelope real con 12 dB de recorrido. La forma 0 es lineal y la 1 no
-- tiene tabla: se dibuja aparte.
local SHAPE_TABLES = {
    [2] = { 0, .03, .09, .20, .33, .47, .62, .76, .88, .97, 1 },
    [3] = { 0, .25, .46, .63, .76, .86, .93, .97, .99, 1, 1 },
    [4] = { 0, 0, .01, .02, .06, .11, .20, .32, .48, .70, 1 },
}
local BEZIER_TABLES = {
    neg = { 0, .83, .92, .96, .98, .99, 1, 1, 1, 1, 1 },
    zero = { 0, .06, .15, .25, .36, .47, .59, .70, .82, .92, 1 },
    pos = { 0, 0, 0, 0, 0, .01, .02, .03, .06, .14, 1 },
}

-- Tabla de una forma con su tensión; nil si la forma es lineal. En Bézier se
-- mezcla entre las tablas de tensión -1, 0 y +1.
local function shape_table(shape, tension)
    if shape == 5 then
        local a, b, f
        if tension < 0 then
            a, b, f = BEZIER_TABLES.neg, BEZIER_TABLES.zero, tension + 1
        else
            a, b, f = BEZIER_TABLES.zero, BEZIER_TABLES.pos, tension
        end
        local out = {}
        for i = 1, #a do out[i] = a[i] + (b[i] - a[i]) * f end
        return out
    end
    return SHAPE_TABLES[shape]
end
local CLASS_COL = { voz = 0x4682DC00, sib = 0xFF8C0000, plo = 0xC83CC800 }

-- Rango de tiempo de la curva: lo visible en el arrange, o el de los tramos
-- del track con el margen de las rampas.
local function view_span(lane)
    if S.follow then
        local ok, a, b = pcall(reaper.GetSet_ArrangeView2, 0, false, 0, 0, 0, 0)
        if ok and a and b and b > a then return a, b end
    end
    local lo, hi = math.huge, -math.huge
    for _, rd in ipairs(S.reads) do
        if rd.seg.track == lane.tr then
            lo = math.min(lo, rd.seg.t0)
            hi = math.max(hi, rd.seg.t1)
        end
    end
    if hi <= lo then return 0, 1 end
    return lo - VIEW_PAD_S, hi + VIEW_PAD_S
end

-- Rango del carril de ganancia según fuerza, topes y offsets: no depende de
-- los datos, así que no se mueve mientras se ajusta otro parámetro.
local function gain_bounds()
    local ap = P.apply
    local lo, hi = 0, 0
    for _, cc in pairs(ap.classes) do
        local off = cc.offset_db or 0
        lo = math.min(lo, -ap.max_down_db * ap.strength + off)
        hi = math.max(hi, ap.max_up_db * ap.strength + off)
    end
    lo, hi = lo - 1, hi + 1
    if hi - lo < 6 then
        local mid = (hi + lo) / 2
        lo, hi = mid - 3, mid + 3
    end
    return lo, hi
end

local function draw_curve_controls()
    reaper.ImGui_BeginDisabled(ctx, #S.lanes < 2)
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local cur = S.lanes[S.sel]
    local lane_open = reaper.ImGui_BeginCombo(ctx, "##lane", cur and cur.name or "Sin track")
    tip("lane")
    if lane_open then
        for i, ln in ipairs(S.lanes) do
            if reaper.ImGui_Selectable(ctx, ln.name .. "###lane" .. i, i == S.sel) then
                S.sel = i
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_SameLine(ctx)
    local ch, v = reaper.ImGui_Checkbox(ctx, "Seguir el arrange##follow", S.follow)
    tip("follow")
    if ch then S.follow = v end
end

-- Carril de nivel (RMS, piezas y umbrales de la puerta) y carril de ganancia
-- planificada, sobre el mismo eje de tiempo. Los puntos son los de Apply.plan,
-- los mismos que escribe Aplicar.
local function draw_curve()
    local AddLine = reaper.ImGui_DrawList_AddLine
    local AddRect = reaper.ImGui_DrawList_AddRectFilled

    local w = reaper.ImGui_GetContentRegionAvail(ctx)
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    reaper.ImGui_Dummy(ctx, w, LEVEL_H + GAP + GAIN_H)
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    local gy0 = y + LEVEL_H + GAP
    AddRect(dl, x, y, x + w, y + LEVEL_H, 0x00000066, 4)
    AddRect(dl, x, gy0, x + w, gy0 + GAIN_H, 0x00000066, 4)

    local lane = S.reads and S.lanes[S.sel]
    if not lane then return end

    local t0, t1 = view_span(lane)
    local span = math.max(t1 - t0, 1e-6)
    local g_lo, g_hi = gain_bounds()
    local function tx(t)
        local c = math.max(t0, math.min(t1, t))
        return x + w * (c - t0) / span
    end
    local function ly(db)
        local c = math.max(LV_LO, math.min(LV_HI, db))
        return y + LEVEL_H - 1 - (LEVEL_H - 2) * (c - LV_LO) / (LV_HI - LV_LO)
    end
    local function gy(db)
        local c = math.max(g_lo, math.min(g_hi, db))
        return gy0 + GAIN_H - 1 - (GAIN_H - 2) * (c - g_lo) / (g_hi - g_lo)
    end

    for _, pc in ipairs(lane.pieces) do
        if pc.t1 > t0 and pc.t0 < t1 then
            local xa = tx(pc.t0)
            local xb = math.max(tx(pc.t1), xa + 2)
            local col = CLASS_COL[pc.class] or CLASS_COL.voz
            local yl = ly(pc.level_db)
            AddRect(dl, xa, yl, xb, y + LEVEL_H - 1, col | 0x40, 0)
            AddLine(dl, xa, yl, xb, yl, col | 0xFF, 2)
        end
    end

    AddLine(dl, x, ly(P.seg.open_db), x + w, ly(P.seg.open_db), 0xFFFFFF55, 1)
    AddLine(dl, x, ly(P.seg.close_db), x + w, ly(P.seg.close_db), 0xFFFFFF26, 1)

    local win = S.read_cfg.window_ms / 1000
    local step = math.max(1, math.floor(span / win / w))
    for _, rd in ipairs(S.reads) do
        if rd.seg.track == lane.tr then
            local rows, n = rd.rows, #rd.rows
            local qx, qy
            local i = 1
            while i <= n do
                local r = rows[i]
                if r.t > t1 then break end
                if r.t + win >= t0 then
                    local m = r.rms_db
                    for k = i + 1, math.min(i + step - 1, n) do
                        if rows[k].rms_db > m then m = rows[k].rms_db end
                    end
                    local cx, cy = tx(r.t + win / 2), ly(m)
                    if qx then AddLine(dl, qx, qy, cx, cy, 0xE0E0E0FF, 1) end
                    qx, qy = cx, cy
                end
                i = i + step
            end
        end
    end

    AddLine(dl, x, gy(0), x + w, gy(0), 0xFFFFFF40, 1)
    local gcol = 0xB8FF6DFF

    -- Recorta el tramo al rango visible interpolando en el tiempo, para que
    -- una rampa que sale del encuadre no se deforme contra el borde.
    local function seg_line(ta, ya, tb, yb)
        if tb < t0 or ta > t1 then return end
        if tb > ta then
            if ta < t0 then
                ya = ya + (yb - ya) * (t0 - ta) / (tb - ta)
                ta = t0
            end
            if tb > t1 then
                yb = ya + (yb - ya) * (t1 - ta) / (tb - ta)
                tb = t1
            end
        end
        AddLine(dl, tx(ta), gy(ya), tx(tb), gy(yb), gcol, 1.5)
    end

    local pts = lane.pts
    if pts then
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            if a.shape == 1 then
                seg_line(a.t, a.db, b.t, a.db)
                seg_line(b.t, a.db, b.t, b.db)
            else
                local tab = a.db ~= b.db and shape_table(a.shape, a.tension) or nil
                local steps = tab and #tab - 1 or 1
                local qt, qy = a.t, a.db
                for k = 1, steps do
                    local u = k / steps
                    local nt = a.t + (b.t - a.t) * u
                    local ny = a.db + (b.db - a.db) * (tab and tab[k + 1] or u)
                    seg_line(qt, qy, nt, ny)
                    qt, qy = nt, ny
                end
            end
        end
    end

    local cpos = reaper.GetCursorPosition()
    if cpos >= t0 and cpos <= t1 then
        local cx = tx(cpos)
        AddLine(dl, cx, y, cx, gy0 + GAIN_H, 0xFFFFFF80, 1)
    end

    reaper.ImGui_DrawList_AddText(dl, x + 4, y + 2, 0xFFFFFFA0, "nivel (dB)")
    reaper.ImGui_DrawList_AddText(dl, x + 4, gy0 + 2, 0xFFFFFFA0,
        string.format("ganancia (%+.0f a %+.0f dB)", g_hi, g_lo))
end

local function draw()
    reaper.ImGui_Text(ctx, "Fuente")
    for _, m in ipairs(MODES) do
        reaper.ImGui_SameLine(ctx)
        local clicked = reaper.ImGui_RadioButton(ctx, m.label, P.mode == m.id)
        tip("mode_" .. m.id)
        if clicked and P.mode ~= m.id then
            P.mode = m.id
            S.reads, S.msg, S.lanes = nil, "Sin analizar.", {}
        end
    end

    if ButtonStyle.button(ctx, "Analizar##analyze", "neutral", { pad = 14 }) then
        S.analyze = 2
        S.msg = "Analizando..."
    end
    tip("analyze")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_BeginDisabled(ctx, S.reads == nil or S.analyze > 0 or read_stale())
    if ButtonStyle.button(ctx, "Aplicar##apply", "primary", { pad = 14 }) then
        apply()
    end
    tip("apply")
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_SameLine(ctx)
    if ButtonStyle.button(ctx, "Borrar vista previa##clear", "neutral", { pad = 14 }) then
        clear_preview()
    end
    tip("clear")

    reaper.ImGui_Separator(ctx)

    local ch, v = reaper.ImGui_Checkbox(ctx, "Vista previa (regiones)##preview", S.preview)
    tip("preview")
    if ch then
        S.preview = v
        if v then
            S.dirty = true
        else
            clear_preview()
        end
    end
    reaper.ImGui_SameLine(ctx)
    if ButtonStyle.button(ctx, "Restaurar valores de la config##defaults", "subtle", { pad = 14 }) then
        load_defaults()
        S.dirty = true
    end
    tip("defaults")

    draw_curve_controls()
    draw_curve()
    local lane = S.reads and S.lanes[S.sel]
    reaper.ImGui_Text(ctx, lane and lane.line1 or " ")
    reaper.ImGui_Text(ctx, lane and lane.line2 or " ")

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, S.msg)
    if read_stale() then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFB347FF)
        reaper.ImGui_Text(ctx, "Cambió la lectura: analizá de nuevo para aplicar.")
        reaper.ImGui_PopStyleColor(ctx, 1)
    else
        reaper.ImGui_Text(ctx, " ")
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_BeginTabBar(ctx, "gr_tabs") then
        if reaper.ImGui_BeginTabItem(ctx, "Piezas###t_pieces") then
            tab_pieces()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Detección###t_classes") then
            tab_classes()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Ganancia###t_gain") then
            tab_gain()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Por clase###t_byclass") then
            tab_by_class()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Lectura###t_read") then
            tab_read()
            reaper.ImGui_EndTabItem(ctx)
        end
        reaper.ImGui_EndTabBar(ctx)
    end
end

local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 520, 640, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, WIN_FLAGS)
    if visible then
        draw()
        focus_tick()
        reaper.ImGui_End(ctx)
    end

    -- La lectura bloquea: se hace un frame después del clic para que se vea
    -- el aviso "Analizando...".
    if S.analyze == 1 then
        S.analyze = 0
        analyze()
    elseif S.analyze == 2 then
        S.analyze = 1
    end

    if S.dirty and reaper.time_precise() - S.last_refresh >= 0.12 then
        S.last_refresh = reaper.time_precise()
        refresh()
    end

    if open then reaper.defer(loop) end
end

reaper.defer(loop)