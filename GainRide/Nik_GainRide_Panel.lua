local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Source = dofile(script_dir .. "GainRideSource_common_logic.lua")
local Segment = dofile(script_dir .. "GainRideSegment_common_logic.lua")
local Apply = dofile(script_dir .. "GainRideApply_common_logic.lua")
local Run = dofile(script_dir .. "GainRideRun_common_logic.lua")
local cfg = dofile(script_dir .. "GainRide_config.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")

local TITLE = "GainRide"

local MODES = {
    { id = "selected", label = "Items seleccionados" },
    { id = "all", label = "Tracks seleccionados" },
    { id = "timesel", label = "Time selection" },
}

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
    summary = {},
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
        S.reads, S.msg, S.summary = nil, err, {}
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
    S.summary = {}
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
        local line = string.format("%s | piezas %d (voz %d, sib %d, plo %d)",
            Source.track_name(tr), #pieces, n.voz, n.sib, n.plo)
        if #pieces > 0 then
            local _, info = Apply.plan(pieces, P.apply)
            line = line .. string.format(" | objetivo %s dB | ganancia [%.1f, %+.1f] | topes %d/%d",
                info.target_text, info.g_min, info.g_max, info.capped_down, info.capped_up)
            if S.preview then
                Segment.add_regions(cfg.preview_prefix, pieces, first)
                first = first + #pieces
            end
        end
        S.summary[#S.summary + 1] = line
    end
    reaper.PreventUIRefresh(-1)
    if S.preview then reaper.UpdateArrange() end
end

local CLAMP = reaper.ImGui_SliderFlags_AlwaysClamp()
local LABEL_W = 190

local function sl_int(id, text, tbl, key, lo, hi, fmt)
    reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
    local ch, v = reaper.ImGui_SliderInt(ctx, text .. "##" .. id,
        math.floor(tbl[key] + 0.5), lo, hi, fmt or "%d", CLAMP)
    if ch then
        tbl[key] = v
        S.dirty = true
    end
    return ch
end

local function sl_dbl(id, text, tbl, key, lo, hi, fmt)
    reaper.ImGui_SetNextItemWidth(ctx, -LABEL_W)
    local ch, v = reaper.ImGui_SliderDouble(ctx, text .. "##" .. id, tbl[key], lo, hi, fmt or "%.2f", CLAMP)
    if ch then
        tbl[key] = v
        S.dirty = true
    end
    return ch
end

local function check(id, text, tbl, key)
    local ch, v = reaper.ImGui_Checkbox(ctx, text .. "##" .. id, tbl[key])
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
    sl_int("shape", "Forma de rampa", ap, "shape", 0, 5)
    sl_dbl("tension", "Tensión", ap, "tension", -1, 1, "%.2f")
    check("keep", "Conservar puntos existentes", ap, "keep_existing")
    reaper.ImGui_Separator(ctx)

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

local function draw()
    reaper.ImGui_Text(ctx, "Fuente")
    for _, m in ipairs(MODES) do
        if reaper.ImGui_RadioButton(ctx, m.label, P.mode == m.id) and P.mode ~= m.id then
            P.mode = m.id
            S.reads, S.msg, S.summary = nil, "Sin analizar.", {}
        end
    end

    reaper.ImGui_Separator(ctx)

    if ButtonStyle.button(ctx, "Analizar##analyze", "neutral", { pad = 14 }) then
        S.analyze = 2
        S.msg = "Analizando..."
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_BeginDisabled(ctx, S.reads == nil or S.analyze > 0 or read_stale())
    if ButtonStyle.button(ctx, "Aplicar##apply", "primary", { pad = 14 }) then
        apply()
    end
    reaper.ImGui_EndDisabled(ctx)
    reaper.ImGui_SameLine(ctx)
    if ButtonStyle.button(ctx, "Borrar vista previa##clear", "neutral", { pad = 14 }) then
        clear_preview()
    end

    reaper.ImGui_Separator(ctx)

    local ch, v = reaper.ImGui_Checkbox(ctx, "Vista previa (regiones)##preview", S.preview)
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

    if reaper.ImGui_BeginTabBar(ctx, "gr_tabs") then
        if reaper.ImGui_BeginTabItem(ctx, "Piezas###t_pieces") then
            tab_pieces()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Clases###t_classes") then
            tab_classes()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Ganancia###t_gain") then
            tab_gain()
            reaper.ImGui_EndTabItem(ctx)
        end
        if reaper.ImGui_BeginTabItem(ctx, "Lectura###t_read") then
            tab_read()
            reaper.ImGui_EndTabItem(ctx)
        end
        reaper.ImGui_EndTabBar(ctx)
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, S.msg)
    if read_stale() then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFB347FF)
        reaper.ImGui_TextWrapped(ctx, "Cambió la lectura: analizá de nuevo para aplicar.")
        reaper.ImGui_PopStyleColor(ctx, 1)
    end
    for _, line in ipairs(S.summary) do
        reaper.ImGui_TextWrapped(ctx, line)
    end
end

local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 520, 600, reaper.ImGui_Cond_FirstUseEver())
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