local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")

-- Mapa: key usada en config.js/config.local.js -> nombre de archivo del script.
-- Mantener sincronizado a mano con el @provides de Nik_RemoteState_Poll.lua.
local SCRIPTS = {
  { key = "statePoll",                   file = "Nik_RemoteState_Poll.lua" },
  { key = "reaPitchSet",                 file = "NikRemote_ReaPitch_SetSemitones.lua" },
  { key = "reaPitchToggle",              file = "NikRemote_ReaPitch_ToggleEnable.lua" },
  { key = "playrateSet",                 file = "NikRemote_PlayRate_Set.lua" },
  { key = "playrateTogglePreservePitch", file = "NikRemote_PlayRate_TogglePreservePitch.lua" },
  { key = "trackVisRefresh",             file = "Nik_TrackVis_Refresh.lua" },
  { key = "playrateTempoMapRead",        file = "Nik_Playrate_ReadTempoMap.lua" },
  { key = "projectTabsRead",             file = "Nik_ProjectTabs_Read.lua" },
  { key = "projectTabsSelect",           file = "Nik_ProjectTabs_Select.lua" },
  { key = "tabPrev",                     file = "NikRemote_TabPrev.lua" },
  { key = "tabNext",                     file = "NikRemote_TabNext.lua" },
  { key = "preMarkerSeek",               file = "Nik_Markers_SeekRelative.lua" },
  { key = "musicStatePublishAll",        file = "Nik_MusicState_PublishAll.lua", dir = "../MusicState/" },
}

local lines = {
  "// AUTO-GENERADO por Nik_RemoteControl_GenerateConfig.lua — no editar a mano.",
  "// Generado en esta PC el " .. os.date("%Y-%m-%d %H:%M:%S"),
  "",
}
local failed = {}

for _, entry in ipairs(SCRIPTS) do
  local function normalize_path(path)
    path = path:gsub("\\", "/")
    while true do
      local collapsed, n = path:gsub("/[^/]+/%.%./", "/", 1)
      if n == 0 then break end
      path = collapsed
    end
    return path
  end

  local abs_path = normalize_path(script_dir .. (entry.dir or "") .. entry.file)
  local numeric_id = reaper.AddRemoveReaScript(true, 0, abs_path, true)

  if numeric_id == 0 then
    table.insert(failed, entry.file)
  else
    local named_id = reaper.ReverseNamedCommandLookup(numeric_id)
    local command_id_str = named_id and ("_" .. named_id) or tostring(numeric_id)
    table.insert(lines, string.format(
      'NIK_LUA_COMMANDS.%s.commandId = "%s";',
      entry.key, command_id_str
    ))
  end
end

local out_path = reaper.GetResourcePath() .. "/reaper_www_root/config.local.js"
local display_path = out_path:gsub("/", "\\")
local f = io.open(out_path, "w")

if not f then
  reaper.ShowMessageBox("No se pudo escribir:\n" .. display_path,
    "Nik RemoteControl — Generate Config", 0)
  return
end

f:write(table.concat(lines, "\n") .. "\n")
f:close()

local msg = "config.local.js generado en:\n" .. display_path
  .. "\n\n" .. (#SCRIPTS - #failed) .. " de " .. #SCRIPTS .. " scripts resueltos."

if #failed > 0 then
  msg = msg .. "\n\nNo encontrados (revisar nombre de archivo):\n" .. table.concat(failed, "\n")
end

reaper.ShowMessageBox(msg, "Nik RemoteControl — Generate Config", 0)