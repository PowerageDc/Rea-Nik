-- ============================================================
-- MVSEP Stem Importer
-- Selecciona un .zip descargado de MVSEP, lee su contenido sin
-- extraerlo y extrae solo los audios reconocidos a la carpeta Media
-- del proyecto, ya con su nombre final. Cada stem se coloca en su
-- track dentro del folder Stem Bus.
--
-- Requiere en el sistema: PowerShell (Windows) o "unzip" (Mac/Linux,
-- normalmente preinstalado).
-- ============================================================

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Mvsep = dofile(script_dir .. "MvsepImporter_common_logic.lua")
local CFG = Mvsep.config
local MEDIA_SUBFOLDER = CFG.media_subfolder
local AUDIO_EXTENSIONS = CFG.audio_extensions
local ZOOM_PADDING_BARS = CFG.zoom_padding_bars
local SAVE_SCREENSET_COMMAND_ID = CFG.save_screenset_command_id
local CLICK_FOLDER_PATTERN = CFG.click_folder_pattern
local CLICK_TRACK_PATTERN = CFG.click_track_pattern
local detectStem = Mvsep.detect_stem
local isInstrumental = Mvsep.is_instrumental
local getStemBusChildren = Mvsep.get_stem_bus_children

-- Busca, por patrón (isInstrumental), el track Instrumental en TODO
-- el proyecto -- es un track hermano, no un hijo del folder Stem Bus
local function findInstrumentalTrack()
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(track)
    if isInstrumental(tname) then return track end
  end
  return nil
end

local getExtension = Mvsep.get_extension
local isAudioFile = Mvsep.is_audio_file

local importedMaxEnd = 0 -- extremo derecho (posición + largo) mayor entre los items importados

local function insertItemOnTrack(track, filepath)
  local item, length = Mvsep.insert_audio_item(track, filepath)
  if length and length > importedMaxEnd then importedMaxEnd = length end
  return item, length
end

-- Confirma solo el diálogo de guardado de screenset (requiere JS_ReaScriptAPI).
-- Se arma antes de lanzar la acción porque el diálogo puede bloquear Main_OnCommand.
local SCREENSET_DIALOG_TITLE = "Save Track View Screenset #1"

local function autoConfirmScreensetDialog()
  if not reaper.APIExists("JS_Window_Find") then return end
  local deadline = reaper.time_precise() + 10 -- abandona a los 5 s si no aparece
  local foundAt, lastSent = nil, 0
  local function poll()
    local now = reaper.time_precise()
    local hwnd = reaper.JS_Window_Find(SCREENSET_DIALOG_TITLE, true)
    if hwnd then
      foundAt = foundAt or now
      if now - foundAt >= 0.2 and now - lastSent >= 0.5 then
        lastSent = now
        reaper.JS_Window_OnCommand(hwnd, 1) -- 1 = IDOK (botón "Save")
      end
    elseif foundAt then
      return -- la ventana ya se cerró: no se reprograma nada más
    end
    if now < deadline then reaper.defer(poll) end
  end
  reaper.defer(poll)
end

-- Busca el track "beep" cuyo padre directo contiene "click"
local function findClickBeepTrack()
  local found = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, tname = reaper.GetTrackName(track)
    if tname:lower():find(CLICK_TRACK_PATTERN, 1, true) then
      local parent = reaper.GetParentTrack(track)
      if parent then
        local _, pname = reaper.GetTrackName(parent)
        if pname:lower():find(CLICK_FOLDER_PATTERN, 1, true) then
          if found then
            reaper.ShowConsoleMsg("[Click] Más de un track coincide, se usa el primero\n")
            return found
          end
          found = track
        end
      end
    end
  end
  return found
end

-- Recorta el extremo derecho del item del click al extremo mayor de los importados
local function trimClickItem()
  if importedMaxEnd <= 0 then return end
  local track = findClickBeepTrack()
  if not track then
    reaper.ShowConsoleMsg("[Click] No se encontró un track '" .. CLICK_TRACK_PATTERN ..
      "' dentro de un folder '" .. CLICK_FOLDER_PATTERN .. "'; no se recortó nada\n")
    return
  end
  local item = reaper.GetTrackMediaItem(track, 0)
  if not item then
    reaper.ShowConsoleMsg("[Click] El track no tiene items; no se recortó nada\n")
    return
  end
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local newLen = importedMaxEnd - pos
  if newLen <= 0 then return end
  if newLen > len then
    reaper.ShowConsoleMsg("[Click] El item es más corto que los stems; no se extiende\n")
    return
  end
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", newLen)
end

local function main()
  local ok, zipPath = reaper.GetUserFileNameForRead(Mvsep.get_downloads_path() .. "mvsep.zip", "Seleccioná el .zip de MVSEP", "zip")
  if not ok or zipPath == "" then return end

  local projDir, projErr = Mvsep.get_project_dir()
  if not projDir then
    reaper.ShowMessageBox(projErr, "Error", 0)
    return
  end
  local mediaPath = Mvsep.ensure_media_folder(projDir, MEDIA_SUBFOLDER)

  local children, err = getStemBusChildren()
  if not children then
    reaper.ShowMessageBox(err, "Error", 0)
    return
  end

  local entries, listErr = Mvsep.list_zip_entries(zipPath, AUDIO_EXTENSIONS)
  if not entries then
    reaper.ShowConsoleMsg("---- Error al leer el zip ----\n" .. (listErr or "(sin salida)") .. "\n------------------------------\n")
    reaper.ShowMessageBox(
      "No se pudo leer el zip. Abrí View > Show console output en REAPER para ver el error exacto.",
      "Error", 0)
    return
  end

  local plan, jobs, unmatched, seen = {}, {}, {}, {}
  for _, e in ipairs(entries) do
    if isAudioFile(e.name) then
      local isInstr = isInstrumental(e.name)
      local stem = (not isInstr) and detectStem(e.name) or nil
      local label = isInstr and "Instrumental" or (stem and stem.name)
      if not label then
        table.insert(unmatched, e.name .. " (familia no reconocida, no se extrae)")
      elseif seen[label] then
        table.insert(unmatched, e.name .. " (duplicado de " .. label .. ", no se extrae)")
      else
        seen[label] = true
        local newName = label .. "." .. getExtension(e.name)
        local dest = mediaPath .. "/" .. newName
        table.insert(jobs, { entry = e.full, dest = dest })
        table.insert(plan, { label = label, stem = stem, newName = newName, dest = dest })
      end
    end
  end

  if #jobs == 0 then
    reaper.ShowMessageBox(
      "El zip no contiene audios reconocidos para importar." ..
      (#unmatched > 0 and ("\n\nOmitidos: " .. table.concat(unmatched, ", ")) or ""),
      "MVSEP Import", 0)
    return
  end

  local locked = {}
  for _, j in ipairs(jobs) do
    if reaper.file_exists(j.dest) then
      local f = io.open(j.dest, "r+b")
      if f then
        f:close()
      else
        table.insert(locked, j.dest:match("([^/\\]+)$"))
      end
    end
  end
  if #locked > 0 then
    reaper.ShowMessageBox(
      "Estos archivos de Media están en uso por items del proyecto y no se pueden reemplazar:\n\n" ..
      table.concat(locked, "\n") ..
      "\n\nBorrá esos items (o ponelos offline) y volvé a ejecutar. No se extrajo nada.",
      "MVSEP Import", 0)
    return
  end

  local extractOk = Mvsep.extract_zip_entries(zipPath, jobs)
  if not extractOk then
    reaper.ShowMessageBox(
      "Falló la descompresión. Abrí View > Show console output en REAPER para ver el error exacto.",
      "Error", 0)
    return
  end

  local placed = {}
  local refItemLength = nil
  for _, p in ipairs(plan) do
    local targetTrack, noTrackMsg
    if p.stem then
      for _, track in ipairs(children) do
        local _, tname = reaper.GetTrackName(track)
        if detectStem(tname) == p.stem then
          targetTrack = track
          break
        end
      end
      noTrackMsg = " (sin track destino)"
    else
      targetTrack = findInstrumentalTrack()
      noTrackMsg = " (sin track destino: ningún track matchea patrón 'instrum')"
    end

    if targetTrack then
      local _, length = insertItemOnTrack(targetTrack, p.dest)
      refItemLength = refItemLength or length
      table.insert(placed, p.label)
    else
      table.insert(unmatched, p.newName .. noTrackMsg)
    end
  end

  trimClickItem()
  reaper.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
  reaper.UpdateArrange()

  if refItemLength then
    local timesig_num, timesig_denom = reaper.TimeMap_GetTimeSigAtTime(0, 0.0)
    local qnPerBar = timesig_num * (4 / timesig_denom)
    local paddingQN = ZOOM_PADDING_BARS * qnPerBar
    local paddingTime = reaper.TimeMap2_beatsToTime(0, paddingQN)
    local endTime = refItemLength + paddingTime
    reaper.BR_SetArrangeView(0, 0, endTime)
    autoConfirmScreensetDialog()
    if reaper.APIExists("JS_WindowMessage_Post") then
      -- Se postea (no bloquea) para que el script quede libre y su defer pueda confirmar el diálogo
      reaper.JS_WindowMessage_Post(reaper.GetMainHwnd(), "WM_COMMAND", SAVE_SCREENSET_COMMAND_ID, 0, 0, 0)
    else
      reaper.Main_OnCommand(SAVE_SCREENSET_COMMAND_ID, 0) -- Screenset: Save track view #01 (pisa "ALL")
    end
  end

  local msg = "Importados: " .. (#placed > 0 and table.concat(placed, ", ") or "ninguno")
  if #unmatched > 0 then
    msg = msg .. "\n\nOmitidos: " .. table.concat(unmatched, ", ")
  end
  if #unmatched > 0 then reaper.ShowConsoleMsg("[MVSEP] " .. msg .. "\n") end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Import MVSEP stems", -1)
