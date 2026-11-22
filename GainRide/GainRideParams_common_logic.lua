local M = {}

local SECTION, KEY = "GainRide", "params"

local PERSIST_READ = { "window_ms", "lf_hz" }
local APPLY_SKIP = { mode = true, envelope = true }

local TOP_ORDER = { "probe_mode", "merge_tolerance_ms", "window_ms", "print_every_ms",
    "sample_rate", "floor_db", "lf_hz", "preview_prefix" }
local APPLY_ORDER = { "strength", "max_down_db", "max_up_db", "ramp_down_ms", "ramp_up_ms",
    "shape", "tension", "keep_existing" }
local CLASS_ORDER = { "target_db", "offset_db", "ramp_down_ms", "ramp_up_ms" }
local SEG_ORDER = { "open_db", "close_db", "min_gap_ms", "min_len_ms", "smooth_ms",
    "level_split", "level_step_db", "level_hold_ms", "classify", "sib_hf_min", "sib_hz_min",
    "class_min_ms", "plosive", "plo_lf_min", "plo_rise_db", "plo_pre_db", "plo_ms" }

local function serialize(v)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = string.format("[%q]=%s", k, serialize(v[k]))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then
        return string.format("%q", v)
    end
    return tostring(v)
end

-- Copia en dst solo las claves que ya existen y tienen el mismo tipo.
local function merge(dst, src)
    for k, dv in pairs(dst) do
        local sv = src[k]
        if type(sv) == type(dv) then
            if type(dv) == "table" then merge(dv, sv) else dst[k] = sv end
        end
    end
end

-- Guarda en el proyecto solo lo que edita el panel.
function M.save(P)
    local persist = { mode = P.mode, read = {}, seg = P.seg, apply = {} }
    for _, k in ipairs(PERSIST_READ) do persist.read[k] = P.read[k] end
    for k, v in pairs(P.apply) do
        if not APPLY_SKIP[k] then persist.apply[k] = v end
    end
    reaper.SetProjExtState(0, SECTION, KEY, serialize(persist))
end

-- Superpone sobre P (que ya trae los valores por defecto) lo guardado en el
-- proyecto. Devuelve true si había algo válido.
function M.load(P)
    local _, s = reaper.GetProjExtState(0, SECTION, KEY)
    if not s or s == "" then return false end
    local chunk = load("return " .. s, "gainride_params", "t", {})
    if not chunk then return false end
    local ok, saved = pcall(chunk)
    if not ok or type(saved) ~= "table" then return false end
    merge(P, saved)
    return true
end

local function num(x)
    if x == math.floor(x) then return string.format("%d", x) end
    return (string.format("%.4f", x):gsub("0+$", ""):gsub("%.$", ""))
end

local function val(v)
    local t = type(v)
    if t == "number" then return num(v) end
    if t == "string" then return string.format("%q", v) end
    return tostring(v)
end

-- Claves en el orden dado y después el resto, alfabético: una clave nueva en la
-- config no se pierde aunque no esté en la lista.
local function keys_in_order(tbl, order, skip)
    local seen, list = {}, {}
    for _, k in ipairs(order) do
        if tbl[k] ~= nil then
            seen[k] = true
            list[#list + 1] = k
        end
    end
    local rest = {}
    for k in pairs(tbl) do
        if not seen[k] and not (skip and skip[k]) then rest[#rest + 1] = k end
    end
    table.sort(rest)
    for _, k in ipairs(rest) do list[#list + 1] = k end
    return list
end

-- Contenido de GainRide_config.lua con los valores actuales del panel.
function M.config_text(cfg, P)
    local out = {}
    local function line(indent, s)
        out[#out + 1] = string.rep("    ", indent) .. s
    end
    local function fields(indent, tbl, order, skip)
        for _, k in ipairs(keys_in_order(tbl, order, skip)) do
            line(indent, k .. " = " .. val(tbl[k]) .. ",")
        end
    end

    local top = {}
    for k, v in pairs(cfg) do
        if k ~= "apply" and k ~= "seg" then top[k] = v end
    end
    for k, v in pairs(P.read) do top[k] = v end

    local ap = P.apply
    line(0, "return {")
    fields(1, top, TOP_ORDER)
    line(1, "apply = {")
    line(2, "mode = " .. val(ap.mode) .. ",")
    line(2, "envelope = " .. val(ap.envelope) .. ",")
    line(2, "classes = {")
    for _, c in ipairs({ "voz", "sib", "plo" }) do
        local cc = ap.classes[c]
        if cc then
            local parts = {}
            for _, k in ipairs(keys_in_order(cc, CLASS_ORDER)) do
                parts[#parts + 1] = k .. " = " .. val(cc[k])
            end
            line(3, c .. " = { " .. table.concat(parts, ", ") .. " },")
        end
    end
    line(2, "},")
    fields(2, ap, APPLY_ORDER, { mode = true, envelope = true, classes = true })
    line(1, "},")
    line(1, "seg = {")
    fields(2, P.seg, SEG_ORDER)
    line(1, "},")
    line(0, "}")
    return table.concat(out, "\n") .. "\n"
end

return M