-- Nik_ReaPitchBus_Knob.lua
-- Panel nativo en REAPER (ReaImGui): knob de semitonos para todas las
-- instancias de ReaPitch en los hijos del Stem Bus, + reset + toggle ON/OFF.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ReaPitchBus = dofile(script_dir .. "../_Shared/ReaPitchBus_common_logic.lua")

-- === Config ===
local SEMITONE_MIN = -12
local SEMITONE_MAX = 12
local DRAG_PX_PER_SEMITONE = 6.0        -- modo normal
local DRAG_PX_PER_SEMITONE_FINE = 24.0  -- con Ctrl
local KNOB_RADIUS = 45
local ARC_START = math.rad(135)  -- ángulo de inicio del arco
local ARC_SWEEP = math.rad(270)  -- recorrido total del arco

local ctx = reaper.ImGui_CreateContext('ReaPitch Bus')

-- === Estado ===
local current_value = nil     -- number | "mixed" | nil ("none")
local enabled_state = "none"  -- "on" | "off" | "mixed" | "none"
local drag_start_value = 0
local drag_undo_open = false
local last_read = 0

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function read_state()
  local instances = ReaPitchBus.find_all_instances()
  if #instances == 0 then
    current_value = nil
    enabled_state = "none"
    return
  end

  local values = {}
  local all_on, all_off = true, true
  for _, inst in ipairs(instances) do
    local normalized = reaper.TrackFX_GetParamNormalized(inst.track, inst.fx, ReaPitchBus.SEMITONE_PARAM)
    table.insert(values, ReaPitchBus.normalized_to_semitones(normalized))
    if reaper.TrackFX_GetEnabled(inst.track, inst.fx) then all_off = false else all_on = false end
  end

  local mixed = false
  for i = 2, #values do
    if math.abs(values[i] - values[1]) > 0.01 then mixed = true break end
  end
  current_value = mixed and "mixed" or math.floor(values[1] + 0.5)

  if all_on then enabled_state = "on"
  elseif all_off then enabled_state = "off"
  else enabled_state = "mixed" end
end

local function apply_semitones(value)
  local instances = ReaPitchBus.find_all_instances()
  if #instances == 0 then return end
  local normalized = ReaPitchBus.semitones_to_normalized(value)
  for _, inst in ipairs(instances) do
    reaper.TrackFX_SetParamNormalized(inst.track, inst.fx, ReaPitchBus.SEMITONE_PARAM, normalized)
  end
end

local function reset_semitones()
  local instances = ReaPitchBus.find_all_instances()
  if #instances == 0 then return end
  reaper.Undo_BeginBlock()
  apply_semitones(0)
  reaper.Undo_EndBlock("NikRemote: reset semitonos ReaPitch (Stem Bus)", -1)
  read_state()
end

local function toggle_enable()
  local instances = ReaPitchBus.find_all_instances()
  if #instances == 0 then return end
  local all_on = true
  for _, inst in ipairs(instances) do
    if not reaper.TrackFX_GetEnabled(inst.track, inst.fx) then all_on = false break end
  end
  local new_state = not all_on
  reaper.Undo_BeginBlock()
  for _, inst in ipairs(instances) do
    reaper.TrackFX_SetEnabled(inst.track, inst.fx, new_state)
  end
  reaper.Undo_EndBlock("NikRemote: toggle ReaPitch " .. (new_state and "ON" or "OFF") .. " (Stem Bus)", -1)
  read_state()
end

-- === Knob widget ===
local function draw_knob(ctx)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local pos_x, pos_y = reaper.ImGui_GetCursorScreenPos(ctx)
  local size = KNOB_RADIUS * 2
  local center_x, center_y = pos_x + KNOB_RADIUS, pos_y + KNOB_RADIUS

  reaper.ImGui_InvisibleButton(ctx, "##reapitch_knob", size, size)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, reaper.ImGui_MouseButton_Left())
  local active = reaper.ImGui_IsItemActive(ctx)
  local activated = reaper.ImGui_IsItemActivated(ctx)
  local deactivated = reaper.ImGui_IsItemDeactivated(ctx)

  if double_clicked then
    if drag_undo_open then
      reaper.Undo_EndBlock("NikRemote: aplicar semitonos a ReaPitch (Stem Bus)", -1)
      drag_undo_open = false
    end
    reset_semitones()
  elseif activated then
    drag_start_value = (type(current_value) == "number") and current_value or 0
    reaper.ImGui_ResetMouseDragDelta(ctx, reaper.ImGui_MouseButton_Left())
    reaper.Undo_BeginBlock()
    drag_undo_open = true
  end

  if active and drag_undo_open then
    local _, delta_y = reaper.ImGui_GetMouseDragDelta(ctx, reaper.ImGui_MouseButton_Left())
    local ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl())
      or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
    local px_per_semitone = ctrl and DRAG_PX_PER_SEMITONE_FINE or DRAG_PX_PER_SEMITONE
    local raw = drag_start_value - (delta_y / px_per_semitone)
    local new_value = clamp(math.floor(raw + 0.5), SEMITONE_MIN, SEMITONE_MAX)
    if new_value ~= current_value then
      current_value = new_value
      apply_semitones(new_value)
    end
  end

  if deactivated and drag_undo_open then
    reaper.Undo_EndBlock("NikRemote: aplicar " .. tostring(current_value) .. " semitonos a ReaPitch (Stem Bus)", -1)
    drag_undo_open = false
  end

  -- --- Dibujo ---
  local numeric_value = (type(current_value) == "number") and current_value or 0
  local frac = (numeric_value - SEMITONE_MIN) / (SEMITONE_MAX - SEMITONE_MIN)
  local value_angle = ARC_START + frac * ARC_SWEEP

  reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, KNOB_RADIUS, 0x2A2A2AFF, 48)
  reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, KNOB_RADIUS, 0x1A1A1AFF, 48, 2.0)

  reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, KNOB_RADIUS + 8, ARC_START, ARC_START + ARC_SWEEP, 48)
  reaper.ImGui_DrawList_PathStroke(draw_list, 0x404040FF, 0, 3.0)

  if type(current_value) == "number" then
    local zero_frac = (0 - SEMITONE_MIN) / (SEMITONE_MAX - SEMITONE_MIN)
    local zero_angle = ARC_START + zero_frac * ARC_SWEEP
    local a1, a2 = zero_angle, value_angle
    if a1 > a2 then a1, a2 = a2, a1 end

    local magnitude = math.abs(numeric_value) / SEMITONE_MAX
    local color
    if magnitude < 0.4 then color = 0x7DBBBBFF
    elseif magnitude < 0.75 then color = 0xE0A040FF
    else color = 0xE0503FFF end

    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, KNOB_RADIUS + 8, a1, a2, 48)
    reaper.ImGui_DrawList_PathStroke(draw_list, color, 0, 3.0)
  end

  local needle_len = KNOB_RADIUS - 8
  local nx = center_x + math.cos(value_angle) * needle_len
  local ny = center_y + math.sin(value_angle) * needle_len
  local needle_color = (current_value == "mixed") and 0x808080FF or 0xE8E8E8FF
  reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, nx, ny, needle_color, 2.5)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, 4, needle_color, 16)

  local zero_frac2 = (0 - SEMITONE_MIN) / (SEMITONE_MAX - SEMITONE_MIN)
  local zero_angle2 = ARC_START + zero_frac2 * ARC_SWEEP
  local tick_x1 = center_x + math.cos(zero_angle2) * (KNOB_RADIUS - 4)
  local tick_y1 = center_y + math.sin(zero_angle2) * (KNOB_RADIUS - 4)
  local tick_x2 = center_x + math.cos(zero_angle2) * (KNOB_RADIUS + 4)
  local tick_y2 = center_y + math.sin(zero_angle2) * (KNOB_RADIUS + 4)
  reaper.ImGui_DrawList_AddLine(draw_list, tick_x1, tick_y1, tick_x2, tick_y2, 0x606060FF, 1.5)
end

-- === Loop principal ===
local function loop()
  if not drag_undo_open then
    local now = reaper.time_precise()
    if now - last_read > 0.3 then
      read_state()
      last_read = now
    end
  end

  reaper.ImGui_SetNextWindowPos(ctx, 200, 200, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_SetNextWindowSize(ctx, 220, 260, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'ReaPitch — Stem Bus', true)
  if visible then
    draw_knob(ctx)

    local label
    if current_value == nil then label = "—"
    elseif current_value == "mixed" then label = "mixed"
    elseif current_value > 0 then label = "+" .. current_value
    else label = tostring(current_value) end

    reaper.ImGui_Text(ctx, "Semitonos: " .. label)

    if reaper.ImGui_Button(ctx, "Reset") then
      reset_semitones()
    end
    reaper.ImGui_SameLine(ctx)

    local toggle_label = (enabled_state == "on") and "ReaPitch: ON"
      or (enabled_state == "off") and "ReaPitch: OFF"
      or (enabled_state == "mixed") and "ReaPitch: mixed"
      or "ReaPitch: —"
    if reaper.ImGui_Button(ctx, toggle_label) then
      toggle_enable()
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)