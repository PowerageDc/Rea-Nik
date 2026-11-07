-- Nik_SubtitleExport_Export.lua
-- Genera un .srt con la armonía del proyecto activo. La ventana es el item
-- MIDI seleccionado (o, sin item, la time selection) y los acordes salen con
-- la transposición vigente de ReaPitch. El archivo queda junto al .rpp.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Logic       = dofile(script_dir .. "SubtitleExport_common_logic.lua")
local Config      = dofile(script_dir .. "SubtitleExport_config.lua")
local Transpose   = dofile(script_dir .. "../_Shared/MusicTranspose_common_logic.lua")
local ReaPitchBus = dofile(script_dir .. "../_Shared/ReaPitchBus_common_logic.lua")

local PROJ = 0
local NAMESPACE = "NSAUDIOMUSIC"
local TITLE = "SubtitleExport"

local function fail(msg)
    reaper.MB(msg, TITLE, 0)
end

local function readProjExtState(key)
    local ok, value = reaper.GetProjExtState(PROJ, NAMESPACE, key)
    if ok > 0 and value ~= "" then return value end
    return nil
end

-- Ventana de export: item MIDI seleccionado o, si no hay, time selection.
-- Devuelve inicio y fin en segundos, o nil y un mensaje de error.
local function getWindow()
    local midi_items = {}
    for i = 0, reaper.CountSelectedMediaItems(PROJ) - 1 do
        local item = reaper.GetSelectedMediaItem(PROJ, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            midi_items[#midi_items + 1] = item
        end
    end
    if #midi_items > 1 then
        return nil, "Hay más de un item MIDI seleccionado. Dejá seleccionado solo el del video."
    end
    if #midi_items == 1 then
        local pos = reaper.GetMediaItemInfo_Value(midi_items[1], "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(midi_items[1], "D_LENGTH")
        return pos, pos + len
    end
    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_end > ts_start then return ts_start, ts_end end
    return nil, "Seleccioná el item MIDI del video (o definí una time selection)."
end

-- Transposición vigente. Devuelve true, función de transposición (nil si no
-- hay que transponer) y delta; o false y un mensaje de error.
local function resolveTranspose()
    local raw, enabled = ReaPitchBus.read_aggregated_state()
    local kind, delta = Logic.parseSemitones(raw)
    if kind == "mixed" then
        return false, "Las instancias de ReaPitch del Stem Bus tienen semitonos distintos: no hay una transposición única."
    end
    if kind == "invalid" then
        return false, "No se pudo interpretar el semitono de ReaPitch: " .. tostring(raw)
    end
    if kind == "none" or delta == 0 then return true, nil, 0 end

    -- Con ReaPitch apagado el audio no se transpone aunque el semitono siga cargado.
    if enabled ~= "on" then
        local state = (enabled == "off") and "desactivado" or "activado solo en algunas instancias"
        local answer = reaper.MB(
            ("ReaPitch está %s, así que el audio no se transpone como indica el semitono (%+d).\n\n"
                .. "Sí: transponer los acordes igual\nNo: exportar sin transponer\nCancelar: no exportar"):format(state, delta),
            TITLE, 3)
        if answer == 2 then return false, nil end
        if answer == 7 then return true, nil, 0 end
    end

    local key = Logic.parseKey(readProjExtState("project_key"))
    if not key then
        return false, ("ReaPitch transpone %d semitonos pero el proyecto no tiene tonalidad cargada."):format(delta)
    end
    local resolved = Transpose.key(key.tonic, key.mode, delta)
    return true, function(chord)
        return Transpose.chord(chord, delta, resolved.use_sharps)
    end, delta
end

local function main()
    local harmony_json = readProjExtState("harmony_data")
    if not harmony_json then
        return fail("El proyecto no tiene armonía cargada.")
    end

    local _, project_path = reaper.EnumProjects(-1)
    if not project_path or project_path == "" then
        return fail("Guardá el proyecto antes de exportar.")
    end

    local t0, t_end = getWindow()
    if not t0 then return fail(t_end) end

    local ok, transpose, delta = resolveTranspose()
    if not ok then
        if transpose then fail(transpose) end
        return
    end

    -- Compás (1-indexed) + qn_offset a tiempo de proyecto, con el tempo map.
    local events = {}
    for _, ev in ipairs(Logic.parseHarmony(harmony_json)) do
        if ev.measure >= 1 then
            local _, qn_start = reaper.TimeMap_GetMeasureInfo(PROJ, ev.measure - 1)
            events[#events + 1] = {
                t = reaper.TimeMap2_QNToTime(PROJ, qn_start + ev.qn_offset),
                chord = ev.chord,
            }
        end
    end

    local entries = Logic.buildEntries(events, t0, t_end, {
        rules = Config.chord_rules,
        gap_ms = Config.gap_ms,
        carry_in = Config.carry_in,
        transpose = transpose,
        offset_s = Config.video_offset_s,
    })
    if #entries == 0 then
        return fail("No hay acordes dentro de la ventana seleccionada.")
    end

    local out_path = (project_path:gsub("%.[Rr][Pp][Pp]$", "")) .. Config.output_suffix .. ".srt"
    local file, err = io.open(out_path, "wb")
    if not file then
        return fail("No se pudo escribir el archivo:\n" .. out_path .. "\n" .. tostring(err))
    end
    file:write(Logic.toSrt(entries, { newline = Config.newline, bom = Config.bom }))
    file:close()

    local shortest, longest = math.huge, 0
    for _, e in ipairs(entries) do
        local dur = e.stop - e.start
        shortest = math.min(shortest, dur)
        longest = math.max(longest, dur)
    end
    reaper.ShowConsoleMsg(("SubtitleExport: %d subtítulos, transposición %+d semitonos, inicio en %.3f s, desfase %.3f s\nDuración mínima %.3f s, máxima %.3f s\n%s\n")
        :format(#entries, delta, t0, Config.video_offset_s or 0, shortest, longest, out_path))
end

main()