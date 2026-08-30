-- ============================================================
-- REAPER Auto Color by Instrument (con degradado por familia)
-- Colorea automáticamente las pistas según su nombre y aplica
-- una variación de tono cuando hay varias pistas del mismo tipo
-- (ej. 3 guitarras -> mismo hue, distinta luminosidad).
--
-- Instalación:
--   Actions List > New Action... > Load ReaScript...
--   Seleccionar este archivo y correrlo (o asignarle un shortcut
--   / botón de toolbar).
--
-- Para cambiar de paleta, editar la variable PALETTE más abajo.
-- ============================================================

-- ================== CONFIG ==================
local PALETTE = "warm" -- opciones: "soft" | "warm" | "cool"

local PALETTES = {
  soft = { sat = 0.40, light = 0.78 },
  warm = { sat = 0.62, light = 0.52 },
  cool = { sat = 0.65, light = 0.45 },
}

-- hue en escala 0-1 (equivalente a grados/360)
-- Se mantiene fijo entre paletas para que cada instrumento
-- sea siempre reconocible sin importar la paleta elegida.
local INSTRUMENTS = {
  { name = "DRUMS",   hue = 355/360, patterns = {"drum", "%f[%a]dr%f[%A]", "kick", "snare", "bater", "overhead", "%f[%a]oh"} },
  { name = "BASS",    hue = 30/360,  patterns = {"bass", "baj"} },
  { name = "PERC",    hue = 70/360,  patterns = {"perc"} },
  { name = "GUITAR",  hue = 110/360, patterns = {"guitar", "guit", "gtr", "%f[%a]gt%f[%A]"} },
  { name = "CLICK",   hue = 160/360, patterns = {"click", "count", "metrono"} },
  { name = "KEYS",    hue = 208/360, patterns = {"piano", "keys", "%f[%a]key%f[%A]", "teclado"} },
  { name = "STRINGS", hue = 270/360, patterns = {"string", "cuerd", "violin", "cello", "viola"} },
  { name = "VOCALS",  hue = 328/360, patterns = {"vocal", "%f[%a]vox%f[%A]", "%f[%a]voz%f[%A]", "%f[%a]voc%f[%A]"} },
  { name = "BUS",     hue = 40/360,  sat_override = 0.08,
    patterns = {"stem", "%f[%a]bus%f[%A]"} },
}

-- diferencia de luminosidad entre pistas de la misma familia
local GRADIENT_STEP = 0.07
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
  -- fallback: folder sin nombre reconocido -> se trata como bus
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

local function main()
  local cfg = PALETTES[PALETTE]
  if not cfg then
    reaper.ShowMessageBox("Paleta '" .. tostring(PALETTE) .. "' no existe. Usar soft / warm / cool.", "Error", 0)
    return
  end

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
    for idx, track in ipairs(group.tracks) do
      local offset = (idx - (n + 1) / 2) * GRADIENT_STEP
      local light = math.max(0.15, math.min(0.90, cfg.light + offset))
      local r, g, b = hslToRgb(inst.hue, sat, light)
      reaper.SetTrackColor(track, reaper.ColorToNative(r, g, b))
    end
  end

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Auto color tracks by instrument (" .. PALETTE .. ")", -1)
