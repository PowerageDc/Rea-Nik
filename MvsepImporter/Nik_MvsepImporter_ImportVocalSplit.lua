-- Nik_MvsepImporter_ImportVocalSplit.lua
-- Importa el zip de MVSEP con la voz separada en lead y backing. Los dos
-- audios van a tracks nuevos debajo del track de voz del Stem Bus (o como
-- últimos hijos si no hay track de voz), alineados con el item de voz
-- existente, que queda silenciado.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Mvsep = dofile(script_dir .. "MvsepImporter_common_logic.lua")
local CFG = Mvsep.config
local RECIPE = CFG.vocal_split

local function showError(msg)
  reaper.ShowMessageBox(msg, "MVSEP Voces", 0)
end

local function findStemByName(name)
  for _, stem in ipairs(CFG.stems) do
    if stem.name == name then return stem end
  end
  return nil
end

-- Prefiere el track cuyo nombre es exactamente el de la familia; si no
-- hay, el primero que la detecta por patrón. Los nombres en `excluded`
-- (tracks de salida de la receta) nunca cuentan como origen.
local function findSourceTrack(children, stem, excluded)
  local fallback = nil
  for _, tr in ipairs(children) do
    local _, name = reaper.GetTrackName(tr)
    local lname = name:lower()
    if not excluded[lname] then
      if lname == stem.name:lower() then return tr end
      if not fallback and Mvsep.detect_stem(name) == stem then fallback = tr end
    end
  end
  return fallback
end

-- Una entrada del zip por salida de la receta. Devuelve (picked) o
-- (nil, patrón que no se encontró).
local function pickEntries(entries)
  local picked = {}
  for _, out in ipairs(RECIPE.outputs) do
    local found = nil
    for _, e in ipairs(entries) do
      if e.name:lower():find(out.pattern) then
        found = e
        break
      end
    end
    if not found then return nil, out.pattern end
    table.insert(picked, found)
  end
  return picked
end

local function main()
  local ok, zipPath = reaper.GetUserFileNameForRead(
    Mvsep.get_downloads_path(), "Seleccioná el .zip de voces separadas de MVSEP", "zip")
  if not ok then return end

  local projDir, projErr = Mvsep.get_project_dir()
  if not projDir then showError(projErr) return end

  local children, err = Mvsep.get_stem_bus_children()
  if not children then showError(err) return end
  if #children == 0 then showError("El Stem Bus no tiene tracks hijos") return end

  local entries, listErr = Mvsep.list_zip_entries(zipPath, CFG.audio_extensions)
  if not entries then
    reaper.ShowConsoleMsg("---- Error al leer el zip ----\n" .. (listErr or "(sin salida)") .. "\n------------------------------\n")
    showError("No se pudo leer el zip. Abrí View > Show console output en REAPER para ver el error exacto.")
    return
  end

  local picked, missingPattern = pickEntries(entries)
  if not picked then
    showError("El zip no parece ser de voces separadas: no hay ningún audio que coincida con '" .. missingPattern .. "'.")
    return
  end

  local excluded, existing = {}, {}
  for _, out in ipairs(RECIPE.outputs) do excluded[out.track:lower()] = true end
  for _, tr in ipairs(children) do
    local _, name = reaper.GetTrackName(tr)
    existing[name:lower()] = tr
  end

  local withItems = {}
  for _, out in ipairs(RECIPE.outputs) do
    local tr = existing[out.track:lower()]
    if tr and reaper.CountTrackMediaItems(tr) > 0 then table.insert(withItems, out.track) end
  end
  if #withItems > 0 then
    showError("Estos tracks ya tienen audio importado:\n\n" .. table.concat(withItems, "\n") ..
      "\n\nBorrá sus items y volvé a ejecutar. No se extrajo nada.")
    return
  end

  local mediaPath = Mvsep.ensure_media_folder(projDir, CFG.media_subfolder)
  local jobs, dests = {}, {}
  for i, out in ipairs(RECIPE.outputs) do
    dests[i] = mediaPath .. "/" .. out.file .. "." .. Mvsep.get_extension(picked[i].name)
    jobs[i] = { entry = picked[i].full, dest = dests[i] }
  end

  local locked = Mvsep.find_locked_files(jobs)
  if #locked > 0 then
    showError("Estos archivos de Media están en uso por items del proyecto y no se pueden reemplazar:\n\n" ..
      table.concat(locked, "\n") .. "\n\nNo se extrajo nada.")
    return
  end

  if not Mvsep.extract_zip_entries(zipPath, jobs) then
    showError("Falló la descompresión. Abrí View > Show console output en REAPER para ver el error exacto.")
    return
  end

  local sourceStem = findStemByName(RECIPE.source_stem)
  local sourceTrack = sourceStem and findSourceTrack(children, sourceStem, excluded) or nil
  local info = sourceTrack and Mvsep.get_source_info(sourceTrack) or nil

  local warnings = {}
  local position = 0
  if info and info.consistent and info.origin >= 0 then
    position = info.origin
  else
    table.insert(warnings, "No se pudo alinear con el item de '" .. RECIPE.source_stem ..
      "' (no hay track o item, orígenes distintos, playrate distinto de 1 o posición negativa): los items se colocaron en 0.")
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local targets, missing = {}, {}
  for i, out in ipairs(RECIPE.outputs) do
    targets[i] = existing[out.track:lower()]
    if not targets[i] then table.insert(missing, i) end
  end

  if #missing > 0 then
    local names = {}
    for _, i in ipairs(missing) do table.insert(names, RECIPE.outputs[i].track) end
    local newTracks, insErr = Mvsep.insert_tracks_after(sourceTrack or children[#children], names)
    if not newTracks then
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("MVSEP: importar voces separadas", -1)
      showError(insErr)
      return
    end
    for k, i in ipairs(missing) do
      targets[i] = newTracks[k]
      if sourceTrack then
        reaper.SetMediaTrackInfo_Value(newTracks[k], "I_CUSTOMCOLOR",
          reaper.GetMediaTrackInfo_Value(sourceTrack, "I_CUSTOMCOLOR"))
      end
    end
    if sourceTrack and RECIPE.mute_source then
      reaper.SetMediaTrackInfo_Value(sourceTrack, "B_MUTE", 1)
    end
  end

  local needFx = false
  for _, tr in ipairs(targets) do
    if Mvsep.count_fx_by_name(tr, RECIPE.copy_fx) == 0 then needFx = true end
  end
  if needFx then
    local fxSource = nil
    if sourceTrack and Mvsep.count_fx_by_name(sourceTrack, RECIPE.copy_fx) > 0 then
      fxSource = sourceTrack
    else
      fxSource = Mvsep.find_track_with_fx(children, RECIPE.copy_fx)
    end
    if fxSource then
      for _, tr in ipairs(targets) do
        if Mvsep.count_fx_by_name(tr, RECIPE.copy_fx) == 0 then
          Mvsep.copy_fx_by_name(fxSource, tr, RECIPE.copy_fx)
        end
      end
    else
      table.insert(warnings, "Ningún track del Stem Bus tiene '" .. RECIPE.copy_fx .. "': los tracks nuevos quedaron sin ese FX.")
    end
  end

  for i, _ in ipairs(RECIPE.outputs) do
    local item, length = Mvsep.insert_audio_item(targets[i], dests[i], position)
    local fname = dests[i]:match("([^/\\]+)$")
    if not item then
      table.insert(warnings, "No se pudo crear el source de " .. fname)
    elseif info and math.abs(length - info.length) > 0.05 then
      table.insert(warnings, string.format("%s dura %.2f s y el audio de '%s' dura %.2f s.",
        fname, length, RECIPE.source_stem, info.length))
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
  Mvsep.build_missing_peaks()
  reaper.Undo_EndBlock("MVSEP: importar voces separadas", -1)

  if #warnings > 0 then
    reaper.ShowConsoleMsg("[MVSEP Voces]\n- " .. table.concat(warnings, "\n- ") .. "\n")
  end
end

main()