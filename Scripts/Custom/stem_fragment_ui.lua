-- stem_fragment_ui.lua
-- UI (ReaImGui) para captura de fragmentos y split+glue de stems para ReaBeat
-- Requiere: ReaImGui instalado via ReaPack, y stem_fragment_capture.lua en la misma carpeta

local script_path = ({reaper.get_action_context()})[2]:match("^(.*[/\\])")
local M = dofile(script_path .. "stem_fragment_capture.lua")

local ctx = reaper.ImGui_CreateContext('Stem Fragment Capture')
local FONT = reaper.ImGui_CreateFont('sans-serif', 14)
reaper.ImGui_Attach(ctx, FONT)

local open = true

local function get_selected_track_name()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then return nil, nil end
  local _, name = reaper.GetTrackName(track)
  return track, name
end

local function draw_header()
  local sel_track = get_selected_track_name()

  if M.state.source_track then
    local _, src_name = reaper.GetTrackName(M.state.source_track)
    reaper.ImGui_Text(ctx, "Track fuente: " .. src_name)
  else
    reaper.ImGui_Text(ctx, "Track fuente: (ninguno)")
  end

  local can_duplicate = sel_track ~= nil and M.state.duplicated_track == nil
  if not can_duplicate then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "Duplicar track seleccionado") then
    M.duplicar_track(sel_track)
  end
  if not can_duplicate then reaper.ImGui_EndDisabled(ctx) end

  if M.state.duplicated_track then
    local _, dup_name = reaper.GetTrackName(M.state.duplicated_track)
    reaper.ImGui_Text(ctx, "Track duplicado: " .. dup_name)
  end
end

local function draw_captura()
  reaper.ImGui_Separator(ctx)

  local can_marcar = M.state.duplicated_track ~= nil
  if not can_marcar then reaper.ImGui_BeginDisabled(ctx) end

  if reaper.ImGui_Button(ctx, "Marcar corte") then
    local ok, err = M.marcar_corte()
    if not ok then reaper.MB(err, "Error", 0) end
  end

  if not can_marcar then reaper.ImGui_EndDisabled(ctx) end

  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local hint
  if (ts_end - ts_start) > 0.0001 then
    hint = "Selección de tiempo activa -> se usará como fragmento"
  else
    hint = "Sin selección -> desde fin del último fragmento hasta el cursor"
  end
  reaper.ImGui_TextDisabled(ctx, hint)
end

local function draw_tabla()
  reaper.ImGui_Separator(ctx)

  if #M.state.fragments == 0 then
    reaper.ImGui_TextDisabled(ctx, "Sin fragmentos todavía.")
    return
  end

  local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()
  if reaper.ImGui_BeginTable(ctx, "tabla_fragmentos", 5, flags) then
    reaper.ImGui_TableSetupColumn(ctx, "#")
    reaper.ImGui_TableSetupColumn(ctx, "Inicio")
    reaper.ImGui_TableSetupColumn(ctx, "Fin")
    reaper.ImGui_TableSetupColumn(ctx, "Duración")
    reaper.ImGui_TableSetupColumn(ctx, "")
    reaper.ImGui_TableHeadersRow(ctx)

    local delete_id = nil

    for i, frag in ipairs(M.state.fragments) do
      reaper.ImGui_PushID(ctx, frag.id)
      reaper.ImGui_TableNextRow(ctx)

      reaper.ImGui_TableSetColumnIndex(ctx, 0)
      local label = tostring(i)
      if M.es_discontinuo(i) then label = label .. " ⚠" end
      reaper.ImGui_Text(ctx, label)

      reaper.ImGui_TableSetColumnIndex(ctx, 1)
      reaper.ImGui_Text(ctx, M.format_time_compases(frag.start_pos))

      reaper.ImGui_TableSetColumnIndex(ctx, 2)
      reaper.ImGui_Text(ctx, M.format_time_compases(frag.end_pos))

      reaper.ImGui_TableSetColumnIndex(ctx, 3)
      reaper.ImGui_Text(ctx, string.format("%.2fs", frag.end_pos - frag.start_pos))

      reaper.ImGui_TableSetColumnIndex(ctx, 4)
      if reaper.ImGui_Button(ctx, "Eliminar") then
        delete_id = frag.id
      end

      reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_EndTable(ctx)

    if delete_id then M.eliminar_fragmento(delete_id) end
  end
end

local function draw_footer()
  reaper.ImGui_Separator(ctx)

  local can_apply = #M.state.fragments > 0
  if not can_apply then reaper.ImGui_BeginDisabled(ctx) end

  if reaper.ImGui_Button(ctx, "Aplicar cortes y glue") then
    local preview = M.generar_preview()
    reaper.ShowConsoleMsg(preview .. "\n")
    local resp = reaper.MB(preview .. "\n\n¿Confirmar?", "Confirmar split + glue", 1)
    if resp == 1 then
      local ok, err = M.aplicar_split_glue()
      if not ok then reaper.MB(err, "Error", 0) end
    end
  end

  if not can_apply then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cerrar") then
    open = false
  end
end

local function loop()
  reaper.ImGui_PushFont(ctx, FONT, 14)
  reaper.ImGui_SetNextWindowSize(ctx, 480, 400, reaper.ImGui_Cond_FirstUseEver())
  local visible, still_open = reaper.ImGui_Begin(ctx, 'Stem Fragment Capture', true)
  open = still_open

  if visible then
    draw_header()
    draw_captura()
    draw_tabla()
    draw_footer()
    reaper.ImGui_End(ctx)
  end

  reaper.ImGui_PopFont(ctx)

  if open then reaper.defer(loop) end
end

reaper.defer(loop)