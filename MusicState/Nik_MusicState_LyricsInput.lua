local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Lyrics = dofile(script_dir .. "MusicStateLyrics_common_logic.lua")

local TITLE = "Lyrics"

local function describe(list)
  local parts = {}
  for i = 1, math.min(3, #list) do
    parts[i] = "\"" .. list[i].text .. "\""
  end
  local s = table.concat(parts, ", ")
  if #list > 3 then s = s .. " y " .. (#list - 3) .. " más" end
  return s
end

local function fmtPos(t)
  return reaper.format_timestr_pos(t, "", 2)
end

local function main()
  local track = Lyrics.FindLyricsTrack(0)
  if not track then
    local ans = reaper.MB(
      "No se encontró el track de Lyrics.\n¿Crear \"" .. Lyrics.DEFAULT_TRACK_NAME .. "\"?",
      TITLE, 4)
    if ans ~= 6 then return end
  end

  local t1, t2 = Lyrics.GetTimeContext()
  local ctx = Lyrics.PlanLine(track, t1, t2)

  local title = TITLE .. "  " .. fmtPos(t1)
  if t2 then title = title .. " → " .. fmtPos(t2) end
  local ok, csv = reaper.GetUserInputs(
    title, 1, "extrawidth=350,separator=\n,Texto (vacío = solo fin)", ctx.prefill)
  if not ok then return end
  local text = Lyrics.CleanText(csv)

  local opts = {}
  if text ~= "" and #ctx.inside > 0 then
    local ans = reaper.MB(
      "Hay " .. #ctx.inside .. " evento(s) dentro de la selección: " .. describe(ctx.inside) ..
      ".\n\nSí = reemplazarlos\nNo = conservarlos e insertar igual\nCancelar = no hacer nada",
      TITLE, 3)
    if ans == 2 then return end
    opts.replace_inside = (ans == 6)
  end

  local done, info = Lyrics.ApplyLine(track, ctx, text, opts)
  if not done and info == "end_occupied" then
    reaper.MB("Ya hay un evento en esa posición; no se insertó el marcador de fin.", TITLE, 0)
  end
end

main()