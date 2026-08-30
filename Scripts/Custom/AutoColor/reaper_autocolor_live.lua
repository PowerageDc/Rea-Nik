-- ============================================================
-- REAPER Auto Color by Instrument — VERSIÓN LIVE (background)
-- Corre en background y reaplica colores solo cuando detecta
-- cambios reales en las pistas (nombre, cantidad, folder).
-- Usa throttle (chequea cada CHECK_INTERVAL segundos) + hash
-- de estado para evitar trabajo innecesario en cada tick de UI.
--
-- Instalación:
--   Actions List > New Action... > Load ReaScript...
--   Asignale un botón de toolbar o shortcut para poder
--   activarlo/desactivarlo fácilmente (toggle).
--   Al volver a correrlo, REAPER pregunta si querés terminar
--   la instancia anterior (comportamiento estándar de scripts
--   con reaper.defer).
-- ============================================================

-- ================== CONFIG ==================
local PALETTE = "warm" -- opciones: "soft" | "warm" | "cool"
local CHECK_INTERVAL = 0.5 -- segundos entre chequeos (throttle)

local PALETTES = {
  soft = { sat = 0.40, light = 0.78 },
  warm = { sat = 0.62, light = 0.52 },
  cool = { sat = 0.65, light = 0.45 },
}

local INSTRUMENTS = {
  { name = "DRUMS",   hue = 5/360,   patterns = {"drum", "%f[%a]dr%f[%A]", "kick", "snare", "bater", "overhead", "%f[%a]oh"} },
  { name = "BASS",    hue = 25/360,  patterns = {"bass", "baj"} },
  { name = "PERC",    hue = 15/360,  patterns = {"perc"} },
  { name = "GUITAR",  hue = 135/360, sat_override = 0.42, patterns = {"guitar", "guit", "gtr", "%f[%a]gt%f[%A]"} },
  { name = "CLICK",   hue = 350/360, sat_override = 0.45, patterns = {"click", "count", "metrono"} },
  { name = "KEYS",    hue = 205/360, patterns = {"piano", "keys", "%f[%a]key%f[%A]", "teclado"} },
  { name = "STRINGS", hue = 260/360, patterns = {"string", "cuerd", "violin", "cello", "viola"} },
  { name = "VOCALS",  hue = 45/360,  sat_override = 0.70, light_override = 0.85, patterns = {"vocal", "%f[%a]vox%f[%A]", "%f[%a]voz%f[%A]", "%f[%a]voc%f[%A]"} },
  { name = "OTHER",   hue = 235/360, sat_override = 0.28, light_override = 0.55, patterns = {"other", "otro"} },
  { name = "BUS",     hue = 40/360,  sat_override = 0.08, patterns = {"stem", "instrumental", "%f[%a]bus%f[%A]"} },
}

local GRADIENT_STEP = 0.13
local GRADIENT_MAX_SPREAD = 0.55
-- ==============================================

local function detectFamily(name, track)
  local lname = name:lower()
  for _, inst in ipairs(INSTRUMENTS) do
    for _, pat in ipairs(inst.patterns) do
      if lname:find(pat) then
        return inst
      end
    end
  end
  local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
  if depth ~= 0 then
    return INSTRUMENTS[#INSTRUMENTS]
  end
  return nil
end

local function hslToRgb(h, s, l)
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local function hue2rgb(p, q, t)
      if t < 0 then t = t + 1 end
      if t > 1 then t = t - 1 end
      if t < 1/6 then return p + (q - p) * 6 * t end
      if t < 1/2 then return q end
      if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
      return p
    end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    r = hue2rgb(p, q, h + 1/3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1/3)
  end
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

-- Aplica los colores. No usa Undo_Block porque corre
-- automáticamente en background y no queremos ensuciar
-- el historial de undo en cada cambio de nombre.
local function applyColors()
  local cfg = PALETTES[PALETTE]
  local count = reaper.CountTracks(0)
  local groups = {}

  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    local inst = detectFamily(name, track)
    if inst then
      groups[inst.name] = groups[inst.name] or { inst = inst, tracks = {} }
      table.insert(groups[inst.name].tracks, track)
    end
  end

  for _, group in pairs(groups) do
    local inst = group.inst
    local n = #group.tracks
    local sat = inst.sat_override or cfg.sat
    local baseLight = inst.light_override or cfg.light
    local step = GRADIENT_STEP
    if n > 1 then
      step = math.min(GRADIENT_STEP, GRADIENT_MAX_SPREAD / (n - 1))
    end
    for idx, track in ipairs(group.tracks) do
      local offset = (idx - (n + 1) / 2) * step
      local light = math.max(0.15, math.min(0.90, baseLight + offset))
      local r, g, b = hslToRgb(inst.hue, sat, light)
      reaper.SetTrackColor(track, reaper.ColorToNative(r, g, b))
    end
  end

  reaper.UpdateArrange()
end

-- Hash liviano del estado actual: cantidad de tracks + nombre
-- + folder depth de cada uno. Si no cambia, no se hace nada.
local function buildStateHash()
  local count = reaper.CountTracks(0)
  local parts = { tostring(count) }
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    parts[#parts + 1] = name .. "|" .. tostring(depth)
  end
  return table.concat(parts, ";")
end

local function setToggleState(state)
  local _, _, sectionID, cmdID = reaper.get_action_context()
  if cmdID and cmdID ~= -1 then
    reaper.SetToggleCommandState(sectionID, cmdID, state)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

local lastCheck = 0
local lastHash = ""

local function loop()
  local now = reaper.time_precise()
  if now - lastCheck >= CHECK_INTERVAL then
    lastCheck = now
    local h = buildStateHash()
    if h ~= lastHash then
      lastHash = h
      applyColors()
    end
  end
  reaper.defer(loop)
end

setToggleState(1)
reaper.atexit(function() setToggleState(0) end)
loop()
