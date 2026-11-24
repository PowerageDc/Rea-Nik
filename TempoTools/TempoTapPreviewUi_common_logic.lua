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
  play = 0x30D060FF,
  cursor = 0xA0A0A0FF,
}

local STRIPE_W = 4
local GUTTER_W = STRIPE_W + 6

local overlap = reaper.ImGui_SelectableFlags_AllowOverlap or reaper.ImGui_SelectableFlags_AllowItemOverlap
local SELECT_FLAGS = reaper.ImGui_SelectableFlags_SpanAllColumns() | (overlap and overlap() or 0)

local function draw_summary(ctx, S)
  local s = S.summary
  local function sum(k) return s.down[k] + s.beat[k] end
  reaper.ImGui_Text(ctx, string.format(
    "Ajustados %d | interpolados %d | sin cambio %d | sin marker %d | total %d",
    sum("snapped"), sum("interpolated"), sum("kept"), s.inert, s.total))

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

-- El scroll manual suspende el seguimiento solo con el transporte en marcha o
-- en pausa; detenido, un cambio del cursor siempre lleva la tabla a su fila.
local function suspended(st)
  return st.mode ~= "stop" and st.now < st.suspend_until
end

local function draw_controls(ctx, S, st)
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

  local on, toggled = S.inner_beats, nil
  toggled, on = reaper.ImGui_Checkbox(ctx,
    "Usar los beats internos, tocados o segun los ataques (apagado: un tempo por compas en toda la cancion)###inner_beats",
    on)
  if toggled then Preview.set_inner_beats(S, on) end

  local follow_changed, follow = reaper.ImGui_Checkbox(ctx,
    "Seguir la reproduccion###follow", st.follow)
  if follow_changed then
    st.follow = follow
    if follow then st.suspend_until = 0 end
  end
  reaper.ImGui_SameLine(ctx)
  local no_target = st.cur == nil or st.cur_visible ~= false
  if no_target then reaper.ImGui_BeginDisabled(ctx) end
  if ButtonStyle.button(ctx, "Ir a la reproduccion", "neutral", 150) then
    st.force_scroll = true
    st.suspend_until = 0
  end
  if no_target then reaper.ImGui_EndDisabled(ctx) end
  if st.follow and suspended(st) then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, COLORS.dim, "scroll manual: el seguimiento espera")
  end
end

local COLUMNS = {
  { "", GUTTER_W }, { "#", 32 }, { "Cmp.Beat", 60 }, { "Tipo", 46 }, { "Tocado", 66 }, { "Nuevo", 66 },
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
  if p.inert then return "sin marker", COLORS.dim end
  if p.locked then return "bloqueado", COLORS.locked end
  if p.rejected then
    return string.format("rechazado x%.1f %+.1f ms",
      p.rejected_ratio, (p.rejected_pos - p.raw) * 1000), COLORS.rejected
  end
  if p.outlier then return "dudoso", COLORS.outlier end
  if p.low then return "baja confianza", COLORS.low end
  return nil
end

-- Posicion de referencia segun el transporte: reproduciendo o en pausa, la que
-- se escucha; detenido, el cursor de edicion.
local function read_transport(S, st)
  st.now = reaper.time_precise()
  local prev_mode = st.mode
  local state = reaper.GetPlayState()
  local t
  if (state & 1) ~= 0 then
    st.mode, t = "play", reaper.GetPlayPosition()
  elseif (state & 2) ~= 0 then
    st.mode, t = "pause", reaper.GetPlayPosition()
  else
    st.mode, t = "stop", reaper.GetCursorPosition()
  end
  if prev_mode == "stop" and st.mode ~= "stop" then
    st.suspend_until = 0
    st.last_cur = nil
  end
  st.cur = Preview.index_at(S, t)
end

-- Marca de la fila actual sobre el rect del ultimo item (el Selectable de la
-- fila): franja y marco verdes reproduciendo, a media opacidad en pausa, y solo
-- un marco gris con el transporte detenido. No toca el fondo ni el texto.
local function draw_follow_mark(ctx, st)
  local x1, y1 = reaper.ImGui_GetItemRectMin(ctx)
  local x2, y2 = reaper.ImGui_GetItemRectMax(ctx)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  if st.mode == "stop" then
    reaper.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, COLORS.cursor)
    return
  end
  local col = COLORS.play
  if st.mode == "pause" then col = (col & 0xFFFFFF00) | 0x80 end
  reaper.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + STRIPE_W, y2, col)
  reaper.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, col)
end

-- Hay que desplazar el body en este frame: a la fuerza, o con el seguimiento
-- activo y sin suspension cuando cambio la fila actual.
local function want_scroll(st)
  if st.force_scroll then return st.cur ~= nil end
  if not st.follow or suspended(st) then return false end
  return st.cur ~= nil and st.cur ~= st.last_cur
end

-- Fila actual, justo despues de su Selectable: registra si esta a la vista y,
-- si se pidio desplazar, la deja a band del borde superior del body. Sin
-- fuerza, solo desplaza si la fila no esta en la parte superior (1 - band).
local function track_cur_row(ctx, st)
  local _, y1 = reaper.ImGui_GetItemRectMin(ctx)
  local _, y2 = reaper.ImGui_GetItemRectMax(ctx)
  local top, h = st.body_y, st.body_h
  st.cur_visible = y1 >= top and y2 <= top + h
  if not st.scroll_wanted then return end
  local in_band = y1 >= top and y2 <= top + h * (1 - st.band)
  if in_band and not st.force_scroll then return end
  reaper.ImGui_SetScrollY(ctx, reaper.ImGui_GetScrollY(ctx) + (y1 - top) - h * st.band)
  st.self_scrolled = true
end

-- Una fila. Tipo "beat*": beat sin tap propio, repartido entre dos downbeats.
-- Devuelve true si se tildo o destildo "Sin snap".
local function draw_row(ctx, S, st, k, p)
  reaper.ImGui_PushID(ctx, k)
  reaper.ImGui_TableNextRow(ctx)
  local mark, mark_col = mark_of(p)
  if mark and not p.inert then
    reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(),
      (mark_col & 0xFFFFFF00) | 0x30)
  end
  local dimmed = p.locked or p.inert
  if dimmed then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), COLORS.dim)
  end

  reaper.ImGui_TableSetColumnIndex(ctx, 0)
  if reaper.ImGui_Selectable(ctx, "##row", st.selected == k, SELECT_FLAGS) then
    st.selected = k
    if st.mode == "stop" then st.clicked = k end
    Preview.go_to(S, k)
  end
  if st.cur == k then
    draw_follow_mark(ctx, st)
    track_cur_row(ctx, st)
  end

  reaper.ImGui_TableSetColumnIndex(ctx, 1)
  reaper.ImGui_Text(ctx, tostring(k))

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
    reaper.ImGui_TableSetColumnIndex(ctx, i + 1)
    reaper.ImGui_Text(ctx, text)
  end

  reaper.ImGui_TableSetColumnIndex(ctx, 10)
  if mark then reaper.ImGui_TextColored(ctx, mark_col, mark) end

  reaper.ImGui_TableSetColumnIndex(ctx, 11)
  if p.inert then reaper.ImGui_BeginDisabled(ctx) end
  local changed = reaper.ImGui_Checkbox(ctx, "##lock", p.locked == true)
  if p.inert then reaper.ImGui_EndDisabled(ctx) end

  if dimmed then reaper.ImGui_PopStyleColor(ctx) end
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
  local _, wy = reaper.ImGui_GetWindowPos(ctx)
  local _, wh = reaper.ImGui_GetWindowSize(ctx)
  st.body_y, st.body_h = wy, wh

  local scroll = reaper.ImGui_GetScrollY(ctx)
  if st.scroll_prev and not st.self_scrolled and math.abs(scroll - st.scroll_prev) > 0.5 then
    st.suspend_until = st.now + st.suspend
  end
  st.scroll_prev = scroll
  st.self_scrolled = false

  st.scroll_wanted = want_scroll(st)
  if reaper.ImGui_BeginTable(ctx, "pts_rows", n, flags) then
    setup_columns(ctx)
    for k, p in ipairs(S.res.points) do
      if draw_row(ctx, S, st, k, p) then lock_k = k end
    end
    reaper.ImGui_EndTable(ctx)
  end
  if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_GetMouseWheel(ctx) ~= 0 then
    st.suspend_until = st.now + st.suspend
  end
  st.force_scroll = false
  st.last_cur = st.clicked or st.cur
  st.clicked = nil
  reaper.ImGui_EndChild(ctx)

  if lock_k then Preview.toggle_lock(S, lock_k) end
end

-- Devuelve "apply", "cancel" o nil.
local function draw_buttons(ctx, S)
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_Separator(ctx)
  local x0 = reaper.ImGui_GetCursorPosX(ctx)
  local changed, v = reaper.ImGui_Checkbox(ctx, "Borrar los taps al aplicar", S.clear_taps)
  if changed then S.clear_taps = v end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetCursorPosX(ctx, x0 + avail_w - 2 * BUTTON_W - 8)
  local action
  if ButtonStyle.button(ctx, "Cancelar", "neutral", BUTTON_W) then action = "cancel" end
  reaper.ImGui_SameLine(ctx)
  if ButtonStyle.button(ctx, "Aplicar", "primary", BUTTON_W) then action = "apply" end
  return action
end

-- Devuelve "apply", "cancel" o nil mientras la ventana sigue abierta.
local function frame(ctx, S, st)
  local w = S.window
  if w then
    reaper.ImGui_SetNextWindowPos(ctx, w.x, w.y, reaper.ImGui_Cond_FirstUseEver())
  end
  reaper.ImGui_SetNextWindowSize(ctx, w and w.w or 1000, w and w.h or 560,
    reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoNav() | reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, TITLE, true, flags)
  local action
  if visible then
    local x, y = reaper.ImGui_GetWindowPos(ctx)
    local ww, hh = reaper.ImGui_GetWindowSize(ctx)
    S.window = { x = x, y = y, w = ww, h = hh }
    read_transport(S, st)
    draw_summary(ctx, S)
    reaper.ImGui_Separator(ctx)
    draw_controls(ctx, S, st)
    reaper.ImGui_Separator(ctx)
    draw_table(ctx, S, st)
    action = draw_buttons(ctx, S)
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
  local cfg = S.cfg
  local st = {
    focus_tick = EditorFocus.new(ctx, reaper.GetMainHwnd),
    follow = cfg.follow_default and true or false,
    band = cfg.follow_band,
    suspend = cfg.follow_suspend,
    suspend_until = 0,
  }

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