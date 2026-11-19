-- MidiGenCc_common_logic.lua
-- Lectura, borrado e insercion de eventos CC y pitch bend en un take, y los
-- datos de lane que esas operaciones comparten. Sin UI ni sesion: quien lo
-- consume decide el rango y los eventos. Patron dofile + M={}.

local M = {}

-- Datos de una lane: CC de 7 bits (0 a 127) o pitch bend (513).
function M.lane_info(lane)
  if lane == "pitchbend" or lane == 513 then
    return { kind = "pitchbend", chanmsg = 0xE0, min = -8192, max = 8191, label = "pitch bend" }
  end
  if type(lane) == "number" and lane >= 0 and lane <= 127 then
    return { kind = "cc", chanmsg = 0xB0, num = lane, min = 0, max = 127, label = "CC " .. lane }
  end
  return nil
end

-- msg2 y msg3 del evento para un valor nativo. En pitch bend, msg2 es el LSB
-- y msg3 el MSB del valor de 14 bits con centro en 8192.
function M.encode(info, v)
  v = math.max(info.min, math.min(info.max, math.floor(v + 0.5)))
  if info.kind == "pitchbend" then
    local raw = v + 8192
    return raw % 128, raw // 128
  end
  return info.num, v
end

function M.matches(info, chan, chanmsg, ch, msg2)
  if chanmsg ~= info.chanmsg or ch ~= chan then return false end
  return info.kind ~= "cc" or msg2 == info.num
end

function M.floor_ppq(x) return math.floor(x + 0.5) end

function M.take_hash(take)
  local _, h = reaper.MIDI_GetHash(take, false, "")
  return h
end

-- Clave de un evento CC para reubicarlo despues de ordenar el take.
local function cc_key(ppq, chanmsg, chan, msg2, msg3)
  return string.format("%d:%d:%d:%d:%d", M.floor_ppq(ppq), chanmsg, chan, msg2, msg3)
end

-- Eventos de la lane y el canal dentro de [ppq0, ppq1], con su forma.
function M.read_range(take, info, chan, ppq0, ppq1)
  local list = {}
  local _, _, cc_count = reaper.MIDI_CountEvts(take)
  for i = 0, cc_count - 1 do
    local _, sel, muted, p, chanmsg, ch, m2, m3 = reaper.MIDI_GetCC(take, i)
    if p >= ppq0 and p <= ppq1 and M.matches(info, chan, chanmsg, ch, m2) then
      local _, shape, tension = reaper.MIDI_GetCCShape(take, i)
      list[#list + 1] = {
        ppq = M.floor_ppq(p), chanmsg = chanmsg, chan = ch, msg2 = m2, msg3 = m3,
        sel = sel, muted = muted, shape = shape, tension = tension,
      }
    end
  end
  return list
end

function M.delete_range(take, info, chan, ppq0, ppq1)
  local _, _, cc_count = reaper.MIDI_CountEvts(take)
  for i = cc_count - 1, 0, -1 do
    local _, _, _, p, chanmsg, ch, m2 = reaper.MIDI_GetCC(take, i)
    if p >= ppq0 and p <= ppq1 and M.matches(info, chan, chanmsg, ch, m2) then
      reaper.MIDI_DeleteCC(take, i)
    end
  end
end

-- Inserta los eventos, ordena una vez y recien ahi asigna sus formas.
function M.insert_events(take, events)
  if #events == 0 then return end
  local by_key = {}
  for _, ev in ipairs(events) do
    reaper.MIDI_InsertCC(take, ev.sel or false, ev.muted or false, ev.ppq,
      ev.chanmsg, ev.chan, ev.msg2, ev.msg3)
    by_key[cc_key(ev.ppq, ev.chanmsg, ev.chan, ev.msg2, ev.msg3)] = ev
  end
  reaper.MIDI_Sort(take)
  local _, _, cc_count = reaper.MIDI_CountEvts(take)
  for i = 0, cc_count - 1 do
    local _, _, _, p, chanmsg, ch, m2, m3 = reaper.MIDI_GetCC(take, i)
    local ev = by_key[cc_key(p, chanmsg, ch, m2, m3)]
    if ev then reaper.MIDI_SetCCShape(take, i, ev.shape, ev.tension, true) end
  end
  reaper.MIDI_Sort(take)
end

return M