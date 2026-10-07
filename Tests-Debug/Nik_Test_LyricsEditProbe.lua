-- Nik_Test_LyricsEditProbe.lua
-- Probe descartable de la etapa E0 (3c): comportamiento de la API MIDI ante
-- los casos que condicionan MoveEvent/SetText. Correr en un proyecto de prueba.
-- Todo queda en un bloque de undo ("Probe LyricsEdit"): un Ctrl+Z lo saca.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Lyrics = dofile(script_dir .. "../MusicState/MusicStateLyrics_common_logic.lua")

local function p(...)
  local t = {}
  for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
  reaper.ShowConsoleMsg(table.concat(t, ' ') .. '\n')
end

local function mkTrack(name, items)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', name, true)
  for _, it in ipairs(items) do
    reaper.CreateNewMIDIItemInProj(tr, it[1], it[2], false)
  end
  return tr
end

local function firstTake(tr, i)
  return reaper.GetActiveTake(reaper.GetTrackMediaItem(tr, i or 0))
end

local function insertAt(take, t, text)
  local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, t)
  local ok = reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 5, text)
  reaper.MIDI_Sort(take)
  return ok, ppq
end

local function dumpItems(label, tr)
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    p(string.format('  [%s] item %d: pos=%.3f len=%.3f', label, i,
      reaper.GetMediaItemInfo_Value(it, 'D_POSITION'),
      reaper.GetMediaItemInfo_Value(it, 'D_LENGTH')))
  end
end

local function dumpRaw(label, tr)
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local take = firstTake(tr, i)
    local _, _, _, cnt = reaper.MIDI_CountEvts(take)
    p(string.format('  [%s] item %d: %d eventos de texto', label, i, cnt))
    for e = 0, cnt - 1 do
      local _, _, _, ppq, typ, msg = reaper.MIDI_GetTextSysexEvt(take, e)
      p(string.format('    #%d ppq=%s tipo=%s texto=%s proj=%.3f', e,
        tostring(ppq), tostring(typ), tostring(msg),
        reaper.MIDI_GetProjTimeFromPPQPos(take, ppq)))
    end
  end
end

reaper.ClearConsole()
reaper.Undo_BeginBlock()

p('== T1: SetTextSysexEvt con nil (cambiar texto sin tocar posicion/tipo) ==')
local t1 = mkTrack('PROBE_T1', { { 0, 10 } })
local k1 = firstTake(t1)
insertAt(k1, 2, 'A')
insertAt(k1, 4, 'B')
dumpRaw('antes', t1)
local okc, res = pcall(reaper.MIDI_SetTextSysexEvt, k1, 0, nil, nil, nil, nil, 'A2', nil)
p('  pcall ok=' .. tostring(okc) .. ' retorno=' .. tostring(res))
dumpRaw('despues', t1)

p('== T2: insertar ANTES del inicio del item (PPQ negativo) ==')
local t2 = mkTrack('PROBE_T2', { { 20, 30 } })
local k2 = firstTake(t2)
local ok2, ppq2 = insertAt(k2, 18, 'NEG')
p('  insert ok=' .. tostring(ok2) .. ' ppq pedido=' .. tostring(ppq2))
dumpRaw('T2', t2)

p('== T3: insertar PASADO el final del item (item 0-10, evento en 12) ==')
local t3 = mkTrack('PROBE_T3', { { 0, 10 } })
local k3 = firstTake(t3)
local ok3, ppq3 = insertAt(k3, 12, 'PAST')
p('  insert ok=' .. tostring(ok3) .. ' ppq=' .. tostring(ppq3))
dumpRaw('T3', t3)
p('  CollectEvents ve: ' .. #Lyrics.CollectEvents(t3) .. ' evento(s)')

p('== T4: MIDI_SetItemExtents moviendo el INICIO (item 20-30, evento en 25) ==')
local t4 = mkTrack('PROBE_T4', { { 20, 30 } })
local k4 = firstTake(t4)
insertAt(k4, 25, 'X')
dumpRaw('antes', t4)
dumpItems('antes', t4)
local item4 = reaper.GetTrackMediaItem(t4, 0)
local okx = reaper.MIDI_SetItemExtents(item4,
  reaper.TimeMap2_timeToQN(0, 15), reaper.TimeMap2_timeToQN(0, 30))
p('  SetItemExtents ok=' .. tostring(okx))
dumpItems('despues', t4)
dumpRaw('despues', t4)

p('== T5a: EnsureTake con destino ANTES del primer item (item 20-30, destino 15) ==')
local t5a = mkTrack('PROBE_T5a', { { 20, 30 } })
Lyrics.EnsureTake(t5a, 15, 15)
dumpItems('T5a', t5a)

p('== T5b: EnsureTake en HUECO entre items (0-10 y 20-30, destino 18) ==')
local t5b = mkTrack('PROBE_T5b', { { 0, 10 }, { 20, 30 } })
Lyrics.EnsureTake(t5b, 18, 18)
dumpItems('T5b', t5b)

p('== T5c: EnsureTake a 20 ms del final (item 0-10, destino 9.98) ==')
local t5c = mkTrack('PROBE_T5c', { { 0, 10 } })
Lyrics.EnsureTake(t5c, 9.98, 9.98)
dumpItems('T5c', t5c)

p('== T5d: EnsureTake a 5 ms del final (item 0-10, destino 9.995) ==')
local t5d = mkTrack('PROBE_T5d', { { 0, 10 } })
Lyrics.EnsureTake(t5d, 9.995, 9.995)
dumpItems('T5d', t5d)

p('== T1b: SetTextSysexEvt, variantes de parametros ==')
local t1b = mkTrack('PROBE_T1b', { { 0, 10 } })
local k1b = firstTake(t1b)
insertAt(k1b, 2, 'A')
insertAt(k1b, 4, 'B')
local variants = {
  { 'tipo explicito', function()
      return reaper.MIDI_SetTextSysexEvt(k1b, 0, nil, nil, nil, 5, 'A_tipo', nil)
    end },
  { 'tipo y ppq explicitos', function()
      local _, _, _, ppq = reaper.MIDI_GetTextSysexEvt(k1b, 0)
      return reaper.MIDI_SetTextSysexEvt(k1b, 0, nil, nil, ppq, 5, 'A_ppq', nil)
    end },
  { 'todo explicito', function()
      local _, sel, mut, ppq = reaper.MIDI_GetTextSysexEvt(k1b, 0)
      return reaper.MIDI_SetTextSysexEvt(k1b, 0, sel, mut, ppq, 5, 'A_todo', false)
    end },
}
for _, v in ipairs(variants) do
  local okv, res = pcall(v[2])
  p('  ' .. v[1] .. ': ok=' .. tostring(okv) .. ' retorno=' .. tostring(res))
  dumpRaw(v[1], t1b)
end

p('== FIN ==')
reaper.UpdateArrange()
reaper.Undo_EndBlock('Probe LyricsEdit', -1)