-- Nik_Markers_SeekRelative.lua
-- Seek relativo: N compases antes de un marker dado. Se dispara desde el
-- popup de markers del control remoto (long-press sobre un marker) -- ver
-- marker-browser.js / PENDING_optionsbar_markers.md, punto 3.
--
-- El paso de compases usa la accion nativa 41043 ("Move edit cursor back
-- one measure") en vez de calculo manual sobre TimeMap -- REAPER ya
-- resuelve tempo/time-signature correctamente con su propia logica de
-- navegacion, mas confiable que reimplementarla a mano.
--
-- Lee dos ExtState escritos por el JS antes de disparar este script:
--   NikRemote/preseek_marker_id  -> id del marker elegido (markrgnindexnumber)
--   NikRemote/preseek_bars       -> cantidad de compases hacia atras (entero >=1)

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local MarkerBars = dofile(script_dir .. "MarkerBars_common_logic.lua")

local MOVE_CURSOR_BACK_ONE_MEASURE = 41043

local proj = 0

local targetMarkerId = tonumber(reaper.GetExtState("NikRemote", "preseek_marker_id"))
local bars = tonumber(reaper.GetExtState("NikRemote", "preseek_bars"))
if not targetMarkerId or not bars or bars < 1 then return end

local markerPos = MarkerBars.find_marker_pos(proj, targetMarkerId)
if not markerPos then return end

-- 1) Ubicar el edit cursor exacto en el marker, sin tocar playback todavia.
reaper.SetEditCurPos(markerPos, false, false)

-- 2) Retroceder 'bars' compases con la accion nativa (tempo/time-sig aware).
for i = 1, bars do
  reaper.Main_OnCommand(MOVE_CURSOR_BACK_ONE_MEASURE, 0)
  end

-- 3) Leer la posicion final del edit cursor.
local targetTime = reaper.GetCursorPositionEx(proj)

-- 4) Seek en vivo: seekplay=true mueve la reproduccion si esta sonando,
-- no solo el cursor de edicion -- comportamiento pedido para ensayo.
reaper.SetEditCurPos(targetTime, true, true)
