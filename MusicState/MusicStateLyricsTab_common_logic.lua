-- MusicStateLyricsTab_common_logic.lua
-- Tab "Lyrics" de Nik_MusicState_Helper.lua (paso 3a: visor, solo lectura).
-- Consumido solo por el Helper. A diferencia de Armonia/Cues, la letra no
-- vive en H: la fuente de verdad son los eventos lyric del track Lyrics.
-- Esta tab solo mantiene un cache de lectura en H._lyrics.

local M = {}

local EXT_SECTION = 'NikMusicStateHelper'
local EXT_KEY_AUTOSELECT = 'lyrics_autoselect'
local COLOR_ACTIVE_EXACT = 0x3FBF3FA0
local COLOR_ACTIVE_CARRY = 0x3FBF3F40
local COLOR_SECTION_BG = 0x80808030
local SCROLL_RATIO = 0.35
local POS_COLUMN_W = 90

local function findSectionIdx(sections, time)
  for s_idx = #sections, 1, -1 do
    if sections[s_idx].time <= time then
      return s_idx
    end
  end
  return nil
end

local function getState(H)
  if not H._lyrics then
    H._lyrics = {
      proj = nil,
      state_count = -1,
      track = nil,
      events = {},
      line_count = 0,
      last_active = nil,
      scroll_target = nil,
      autoselect = reaper.GetExtState(EXT_SECTION, EXT_KEY_AUTOSELECT) ~= '0',
    }
  end
  return H._lyrics
end

local function refresh(S, H, helpers)
  local Lyrics = helpers.Lyrics
  local track = Lyrics.FindLyricsTrack(0)
  local events = track and Lyrics.CollectEvents(track) or {}
  local sections = helpers.getSections()
  local lines = 0
  for _, ev in ipairs(events) do
    ev.is_end = (ev.text == Lyrics.END_MARK)
    ev.pos_str = reaper.format_timestr_pos(ev.time, '', 2)
    local s_idx = findSectionIdx(sections, ev.time)
    ev.section_idx = s_idx
    ev.section = s_idx and sections[s_idx].name or nil
    if not ev.is_end then lines = lines + 1 end
  end
  S.track = track
  S.events = events
  S.line_count = lines
  S.proj = H.last_proj
  S.state_count = reaper.GetProjectStateChangeCount(0)
end

local function onRowClick(S, Lyrics, idx)
  local ev = S.events[idx]
  reaper.SetEditCurPos(ev.time, true, false)
  if not S.autoselect then return end
  local next_time = nil
  if not ev.is_end then
    for j = idx + 1, #S.events do
      if S.events[j].time > ev.time + Lyrics.EPS_TIME then
        next_time = S.events[j].time
        break
      end
    end
  end
  if next_time then
    reaper.GetSet_LoopTimeRange(true, false, ev.time, next_time, false)
  else
    reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
  end
  reaper.UpdateArrange()
end

function M.draw(ctx, H, helpers)
  local Lyrics = helpers.Lyrics
  local S = getState(H)

  if S.proj ~= H.last_proj or S.state_count ~= reaper.GetProjectStateChangeCount(0) then
    refresh(S, H, helpers)
  end

  local changed, value = reaper.ImGui_Checkbox(ctx, 'Seleccionar duracion al hacer click', S.autoselect)
  if changed then
    S.autoselect = value
    reaper.SetExtState(EXT_SECTION, EXT_KEY_AUTOSELECT, value and '1' or '0', true)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, 'Recargar', 90, 0) then
    refresh(S, H, helpers)
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format('%d lineas', S.line_count))
  reaper.ImGui_Spacing(ctx)

  helpers.LyricsSync.draw(ctx, S, H, helpers)

  if not S.track then
    reaper.ImGui_TextDisabled(ctx, 'No hay un track de Lyrics en este proyecto (nombre con "lyrics").')
    return
  end

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local body_h = math.max(avail_h - helpers.getListFooterReserveH(), 60)

  local playing = (reaper.GetPlayState() & 1) ~= 0
  local ref_time = playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()
  local active_idx, active_exact = nil, false
  for i, ev in ipairs(S.events) do
    if ev.time <= ref_time + Lyrics.EPS_TIME then
      active_idx = i
      active_exact = math.abs(ev.time - ref_time) <= Lyrics.EPS_TIME
    else
      break
    end
  end
  if active_idx ~= S.last_active then
    S.scroll_target = active_idx
    S.last_active = active_idx
  end

  local click_idx = nil
  local body_visible = reaper.ImGui_BeginChild(ctx, 'lyrics_body', 0, body_h, 0, reaper.ImGui_WindowFlags_NoNav())
  if body_visible then
    if reaper.ImGui_BeginTable(ctx, 'lyrics_rows', 2) then
      reaper.ImGui_TableSetupColumn(ctx, 'Pos', reaper.ImGui_TableColumnFlags_WidthFixed(), POS_COLUMN_W)
      reaper.ImGui_TableSetupColumn(ctx, 'Texto', reaper.ImGui_TableColumnFlags_WidthStretch())

      local last_section = nil
      for i, ev in ipairs(S.events) do
        if ev.section_idx and ev.section_idx ~= last_section then
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), COLOR_SECTION_BG)
          reaper.ImGui_TableNextColumn(ctx)
          reaper.ImGui_TableNextColumn(ctx)
          reaper.ImGui_Text(ctx, ev.section)
        end
        last_section = ev.section_idx

        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_PushID(ctx, i)
        if i == active_idx then
          local color = active_exact and COLOR_ACTIVE_EXACT or COLOR_ACTIVE_CARRY
          reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color)
        end

        reaper.ImGui_TableNextColumn(ctx)
        local clicked = reaper.ImGui_Selectable(ctx, ev.pos_str .. '###line', false,
          reaper.ImGui_SelectableFlags_SpanAllColumns())
        if clicked then click_idx = i end

        reaper.ImGui_TableNextColumn(ctx)
        if ev.is_end then
          reaper.ImGui_TextDisabled(ctx, '- fin -')
        else
          reaper.ImGui_Text(ctx, ev.text)
        end

        if S.scroll_target == i then
          reaper.ImGui_SetScrollHereY(ctx, SCROLL_RATIO)
          S.scroll_target = nil
        end
        reaper.ImGui_PopID(ctx)
      end
      reaper.ImGui_EndTable(ctx)
    end
  end
  reaper.ImGui_EndChild(ctx)

  if click_idx then
    onRowClick(S, Lyrics, click_idx)
  end
end

return M