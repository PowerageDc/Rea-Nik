return {
  -- Archivo con la clave del zip, fuera del repo.
  key_file = "C:\\Scripts\\ProjectPack.key",
  winrar = "C:\\Program Files\\WinRAR\\WinRAR.exe",
  winrar_profile = "RPPStems",
  -- Carpeta de destino de los .zip. Vacío = Descargas del usuario.
  dest_dir = "",
  -- Patrones de nombre de archivo que no entran al zip, en cualquier subcarpeta.
  exclude_files = { "*.RPP-bak", "*.tmp", "*.srt" },
  -- Carpetas que no entran al zip, por nombre o por ruta relativa al proyecto.
  -- Se suman la carpeta de render por defecto y la configurada en cada proyecto.
  exclude_dirs = { "Backups", "Media\\Old" },
  -- Tiempo máximo, en segundos, que se espera el resultado del empaquetado.
  max_wait_s = 7200,
}