-- MvsepImporter_config.lua
-- Valores editables del importer de MVSEP. Solo datos, sin lógica.

return {
  media_subfolder = "Media", -- subcarpeta relativa a la carpeta del .rpp

  -- Familias reconocidas. Los patterns son patrones de Lua y se aplican
  -- sobre el nombre en minúsculas; ampliá/ajustá si MVSEP nombra distinto.
  stems = {
    { name = "Vocals", patterns = {"vocal"} },
    { name = "Drums",  patterns = {"drum"} },
    { name = "Bass",   patterns = {"bass"} },
    { name = "Guitar", patterns = {"guitar", "gtr", "%f[%a]gt%f[%A]"} },
    { name = "Piano",  patterns = {"piano", "keys"} },
    { name = "Other",  patterns = {"other"} },
  },

  instrumental_patterns = {"instrum"}, -- cubre "instrum" e "instrumental"
  audio_extensions = {"wav", "mp3", "flac"}, -- extensiones válidas a procesar

  -- Compases de aire a la derecha del zoom-fit, para desplazar luego
  -- (count-in, tempo mapping)
  zoom_padding_bars = 4,
  -- "Screenset: Save track view #01" (pisa el screenset nombrado "ALL")
  save_screenset_command_id = 40464,

  -- El padre directo del track de click debe contener click_folder_pattern
  -- y el track cuyo item se recorta debe contener click_track_pattern
  -- (ambos case-insensitive)
  click_folder_pattern = "click",
  click_track_pattern = "beep",
}