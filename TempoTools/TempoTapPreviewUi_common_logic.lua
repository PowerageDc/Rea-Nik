-- TempoTapPreviewUi_common_logic.lua
-- Ventana ReaImGui de la vista previa del snap: resumen, politica de puntos
-- sin ataque, tabla de puntos y botones Aplicar y Cancelar. Dibuja y despacha;
-- el calculo vive en TempoTapPreview_common_logic.lua.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Preview = dofile(script_dir .. "TempoTapPreview_common_logic.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local EditorFocus = dofile(script_dir .. "../_Shared/ImGuiEditorFocus_common_logic.lua")

local M = {}

local TITLE = "Tempo taps - vista previa del snap###tempotap_preview"
local FOOTER_H = 44
local BUTTON_W = 100

local COLORS = {
  low = 0xFFB020FF,
  outlier = 0xFF4040FF,
  rejected = 0xFF40FFFF,
  locked = 0x40E0FFFF,
  dim = 0x888888FF,
}

local overlap = reaper.ImGui_SelectableFlags_AllowOverlap or reaper.ImGui_SelectableFlags_AllowItemOverlap
local SELECT_FLAGS = reaper.ImGui_SelectableFlags_SpanAllColumns() | (overlap and overlap() or 0)

local function draw_summary(ctx, S)
  local s = S.summary
  local function sum(k) return s.down[k] + s.beat[k] end
  reaper.ImGui_Text(ctx, string.format(
    "Ajustados %d | interpolados %d | sin cambio %d | total %d",
    sum("snapped"), sum("interpolated"), sum("kept"), s.total))

  local marks = {
    { "baja confianza", s.low, COLORS.low },
    { "dudosos", s.outlier, COLORS.outlier },
    { "rechazados", s.rejected, COLORS.rejected },
    { "bloqueados", s.locked, COLORS.locked },
  }
  for i, m in ipairs(marks) do
    if i > 1 then reaper.ImGui_SameLine(ctx) end
    reaper.ImGui_TextColored(ctx, m[2] > 0 and m[3] or COLORS.dim,
      string.format("%s %d", m[1], m[2]))
  end

  reaper.ImGui_Text(ctx, string.format(
    "Mediana del desvio %+.1f ms | irregularidad %.1f -> %.1f ms | compases que pasan a un marker por beat: %d",
    s.median_shift * 1000, s.irregularity_raw * 1000, s.irregularity_new * 1000, s.to_beat))
end

local function draw_controls(ctx, S)
  reaper.ImGui_Text(ctx, "Puntos sin ataque:")
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_RadioButton(ctx, "Interpolar", S.policy == "interpolate") then
    Preview.set_policy(S, "interpolate")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_RadioButton(ctx, "Dejar el tap", S.policy == "keep") then
    Preview.set_policy(S, "keep")
  end
  reaper.ImGui_SameLine(ctx)

  local off = S.policy ~= "interpolate"
  if off then reaper.ImGui_BeginDisabled(ctx) end
  reaper.ImGui_SetNextItemWidth(ctx, 160)
  local changed, v = reaper.ImGui_SliderInt(ctx, "Largo max. de tramo###interp_max",
    S.interp_max, 1, Preview.INTERP_MAX_LIMIT, "%d", reaper.ImGui_SliderFlags_AlwaysClamp())
  if changed then Preview.set_interp_max(S, v) end
  if off then reaper.ImGui_EndDisabled(ctx) end
end

local COLUMNS = {
  { "#", 32 }, { "Cmp.Beat", 60 }, { "Tipo", 46 }, { "Tocado", 66 }, { "Nuevo", 66 },
  { "Desv. ms", 66 }, { "Estado", 84 }, { "Ref", 96 }, { "Ratio", 52 },
  { "Marcas", 190 }, { "Sin snap", 64 },
}

local function setup_columns(ctx)
  local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
  for _, c in ipairs(COLUMNS) do
    reaper.ImGui_TableSetupColumn(ctx, c[1], fixed, c[2])
  end
end

-- Marca de lectura de un punto: texto y color. Una sola por punto.
local function mark_of(p)
  if p.locked then return "bloqueado", COLORS.locked end
  if p.rejected then
    return string.format("rechazado x%.1f %+.1f ms",
      p.rejected_ratio, (p.rejected_pos - p.raw) * 1000), COLORS.rejected
  end
  if p.outlier then return "dudoso", COLORS.outlier end
  if p.low then return "baja confianza", COLORS.low end
  return nil
end

-- Una fila. Tipo "beat*": beat sin tap propio, repartido entre dos downbeats.
-- Devuelve true si se tildo o destildo "Sin snap".
local function draw_row(ctx, S, st, k, p)
  reaper.ImGui_PushID(ctx, k)
  reaper.ImGui_TableNextRow(ctx)
  local mark, mark_col = mark_of(p)
  if mark then
    reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(),
      (mark_col & 0xFFFFFF00) | 0x30)
  end
  if p.locked then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLORS.dim)
  end

  reaper.ImGui_TableSetColumnIndex(ctx, 0)
  if reaper.ImGui_Selectable(ctx, tostring(k), st.selected == k, SELECT_FLAGS) then
    st.selected = k
    Preview.go_to(S, k)
  end

  local cells = {
    string.format("%d.%d", p.bar, p.beat),
    p.kind == "down" and "down" or (p.origin == "tapped" and "beat" or "beat*"),
    string.format("%.3f", p.raw),
    string.format("%.3f", p.pos),
    string.format("%+.1f", p.shift * 1000),
    p.status,
    p.ref or "-",
    p.ratio and string.format("x%.1f", p.ratio) or "-",
  }
  for i, text in ipairs(cells) do
    reaper.ImGui_TableSetColumnIndex(ctx, i)
    reaper.ImGui_Text(ctx, text)
  end

  reaper.ImGui_TableSetColumnIndex(ctx, 9)
  if mark then reaper.ImGui_TextColored(ctx, mark_col, mark) end

  reaper.ImGui_TableSetColumnIndex(ctx, 10)
  local changed = reaper.ImGui_Checkbox(ctx, "##lock", p.locked == true)

  if p.locked then reaper.ImGui_PopStyleColor(ctx) end
  reaper.ImGui_PopID(ctx)
  return changed
end

-- Header fijo y cuerpo en un child propio con NoNav; ninguna tabla lleva ScrollY.
local function draw_table(ctx, S, st)
  local flags = reaper.ImGui_TableFlags_SizingFixedFit()
  local n = #COLUMNS

  if reaper.ImGui_BeginTable(ctx, "pts_header", n, flags) then
    setup_columns(ctx)
    reaper.ImGui_TableHeadersRow(ctx)
    reaper.ImGui_EndTable(ctx)
  end

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local body_h = math.max(80, avail_h - FOOTER_H)
  local lock_k
  reaper.ImGui_BeginChild(ctx, "pts_body", 0, body_h, 0, reaper.ImGui_WindowFlags_NoNav())
  if reaper.ImGui_BeginTable(ctx, "pts_rows", n, flags) then
    setup_columns(ctx)
    for k, p in ipairs(S.res.points) do
      if draw_row(ctx, S, st, k, p) then lock_k = k end
    end
    reaper.ImGui_EndTable(ctx)
  end
  reaper.ImGui_EndChild(ctx)

  if lock_k then Preview.toggle_lock(S, lock_k) end
end

-- Devuelve "apply", "cancel" o nil.
local function draw_buttons(ctx)
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + avail_w - 2 * BUTTON_W - 8)
  local action
  if ButtonStyle.button(ctx, "Cancelar", "neutral", BUTTON_W) then action = "cancel" end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Aplicar", "primary", BUTTON_W) then action = "apply" end
  return action
end

-- Devuelve "apply", "cancel" o nil mientras la ventana sigue abierta.
local function frame(ctx, S, st)
  reaper.ImGui_SetNextWindowSize(ctx, 1000, 560, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoNav() | reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, flags)
  local action
  if visible then
    draw_summary(ctx, S)
    reaper.ImGui_Separator(ctx)
    draw_controls(ctx, S)
    reaper.ImGui_Separator(ctx)
    draw_table(ctx, S, st)
    action = draw_buttons(ctx)
    st.focus_tick()
    reaper.ImGui_End(ctx)
  end
  if not open and not action then action = "cancel" end
  return action
end

-- Abre la ventana y la mantiene con defer. S: estado de Preview.new.
-- handlers.on_apply(measures) recibe los compases resultantes;
-- handlers.on_cancel() se llama al cancelar o cerrar la ventana.
function M.run(S, handlers)
  local ctx = reaper.ImGui_CreateContext("Tempo taps - vista previa", 0)
  local st = { focus_tick = EditorFocus.new(ctx, reaper.GetMainHwnd) }

  local function loop()
    local action = frame(ctx, S, st)
    if action == "apply" then
      handlers.on_apply(Preview.measures(S))
    elseif action == "cancel" then
      handlers.on_cancel()
    else
      reaper.defer(loop)
    end
  end
  reaper.defer(loop)
end

return M