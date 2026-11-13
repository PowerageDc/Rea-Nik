local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Core = dofile(script_dir .. "VstiControl_common_logic.lua")
local Map = dofile(script_dir .. "VstiControlMap_common_logic.lua")
local ButtonStyle = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")
local HostFocus = dofile(script_dir .. "../_Shared/ImGuiHostFocus_common_logic.lua")

local M = {}

local RETURN_FOCUS_TO_EDITOR = true
local KS_BUTTON_W = 140
local SOURCE_REFRESH_S = 0.25
local COLOR_OK = 0x7CD67CFF
local COLOR_ERR = 0xE06C6CFF

local MODES = { "cursor", "per_note", "range" }
local MODE_LABELS = { "Cursor", "Por nota", "Rango" }
local SHAPE_NAMES = { "linear", "slow", "fast_start", "fast_end", "bezier", "square" }
local SHAPE_ITEMS = table.concat(SHAPE_NAMES, "\0") .. "\0"
local BEZIER_IDX = 4

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

function M.run(cfg)
  local ctx = reaper.ImGui_CreateContext("VstiControl " .. cfg.name, 0)
  local title = cfg.name .. " - VstiControl###vstictl_" .. cfg.name
  local d = cfg.defaults or {}

  local S = {
    mode = 1,
    ks_offset = d.ks_offset or 0,
    ks_length = d.ks_length or 60,
    ks_velocity = d.ks_velocity or 100,
    shape = 0,
    tension = d.ramp_tension or 0.0,
    status = "",
    status_ok = true,
    src_label = nil,
    src_err = nil,
    src_t = 0,
    cc = {},
    pos = {},
  }
  for i, name in ipairs(SHAPE_NAMES) do
    if name == (d.ramp_shape or "linear") then S.shape = i - 1 end
  end

  local function cc_state(c)
    local st = S.cc[c]
    if not st then
      st = { from = 0, to = c.scale and c.scale.pos or c.max or 127 }
      S.cc[c] = st
    end
    return st
  end

  local function live_cfg()
    local ld = copy(d)
    ld.ks_offset = S.ks_offset
    ld.ks_length = S.ks_length
    ld.ks_velocity = S.ks_velocity
    ld.ramp_shape = SHAPE_NAMES[S.shape + 1]
    ld.ramp_tension = (S.shape == BEZIER_IDX) and S.tension or nil
    return { channel = cfg.channel, middle_c = cfg.middle_c, defaults = ld }
  end

  local function exec(spec)
    local ok, msg = Core.exec(live_cfg(), spec)
    S.status = spec.label .. ": " .. msg
    S.status_ok = ok
  end

  local function btn(label, kind, w)
    return ButtonStyle.button(ctx, label, kind, w and { w = w } or { pad = 8 })
  end

  local function draw_ks(group)
    local list = {}
    for _, c in ipairs(group.controls) do
      if c.kind == "ks" and not c.variants then list[#list + 1] = c end
    end
    if #list == 0 then return end

    local avail = reaper.ImGui_GetContentRegionAvail(ctx)
    local cols = math.max(1, math.floor((avail + 8) / (KS_BUTTON_W + 8)))
    for i, c in ipairs(list) do
      if (i - 1) % cols ~= 0 then reaper.ImGui_SameLine(ctx) end
      if btn(c.label .. "##ks" .. i, "neutral", KS_BUTTON_W) then
        local spec = copy(c)
        spec.type = "keyswitch"
        spec.mode = c.mode or MODES[S.mode]
        exec(spec)
      end
    end
  end

  local function draw_ks_variants(group, gi)
    local list = {}
    for _, c in ipairs(group.controls) do
      if c.kind == "ks" and c.variants then list[#list + 1] = c end
    end
    if #list == 0 then return end

    local flags = reaper.ImGui_TableFlags_SizingFixedFit()
    if not reaper.ImGui_BeginTable(ctx, "ksv" .. gi, 2, flags) then return end
    local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
    reaper.ImGui_TableSetupColumn(ctx, "Keyswitch", fixed, 150)
    reaper.ImGui_TableSetupColumn(ctx, "Variantes", fixed, 0)
    reaper.ImGui_TableHeadersRow(ctx)

    for i, c in ipairs(list) do
      reaper.ImGui_PushID(ctx, "v" .. i)
      reaper.ImGui_TableNextRow(ctx)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, c.label)

      reaper.ImGui_TableNextColumn(ctx)
      for vi, v in ipairs(c.variants) do
        if vi > 1 then reaper.ImGui_SameLine(ctx) end
        if btn(v.label .. "##va" .. vi, "neutral") then
          local spec = copy(c)
          for k, val in pairs(v) do spec[k] = val end
          spec.type = "keyswitch"
          spec.label = c.label .. " " .. v.label
          spec.variants = nil
          spec.mode = c.mode or MODES[S.mode]
          exec(spec)
        end
      end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end

  local function raw_of(c, v)
    if c.scale then return Map.scale_to_raw(c, v) end
    return v
  end

  local function slider(c, id, v)
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    if c.scale then
      local fmt = "%.1f " .. (c.scale.unit or "")
      local _, nv = reaper.ImGui_SliderDouble(ctx, id, v, -c.scale.neg, c.scale.pos, fmt)
      return nv
    end
    local _, nv = reaper.ImGui_SliderInt(ctx, id, v, c.min or 0, c.max or 127)
    return nv
  end

  local function draw_cc(group, gi)
    local list = {}
    for _, c in ipairs(group.controls) do
      if c.kind == "cc" then list[#list + 1] = c end
    end
    if #list == 0 then return end

    local flags = reaper.ImGui_TableFlags_SizingFixedFit()
    if not reaper.ImGui_BeginTable(ctx, "cc" .. gi, 4, flags) then return end
    local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
    reaper.ImGui_TableSetupColumn(ctx, "Control", fixed, 130)
    reaper.ImGui_TableSetupColumn(ctx, "Desde", fixed, 110)
    reaper.ImGui_TableSetupColumn(ctx, "Hasta", fixed, 110)
    reaper.ImGui_TableSetupColumn(ctx, "Acciones", fixed, 0)
    reaper.ImGui_TableHeadersRow(ctx)

    for i, c in ipairs(list) do
      local st = cc_state(c)
      local lo, hi = c.min or 0, c.max or 127
      reaper.ImGui_PushID(ctx, "r" .. i)
      reaper.ImGui_TableNextRow(ctx)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, c.label)

      reaper.ImGui_TableNextColumn(ctx)
      st.from = slider(c, "##from", st.from)

      reaper.ImGui_TableNextColumn(ctx)
      st.to = slider(c, "##to", st.to)

      reaper.ImGui_TableNextColumn(ctx)
      if btn("<>##sw", "subtle") then st.from, st.to = st.to, st.from end
      reaper.ImGui_SameLine(ctx)
      if btn("Tomar##tk", "subtle") then
        local v, err = Core.value_at_cursor(live_cfg(), c.cc)
        if v then
          st.from = c.scale and Map.raw_to_scale(c, v) or math.max(lo, math.min(hi, v))
        else
          S.status, S.status_ok = c.label .. ": " .. err, false
        end
      end
      reaper.ImGui_SameLine(ctx)
      if btn("Punto##pt", "neutral") then
        exec({ type = "cc_point", label = c.label .. " punto", cc = c.cc,
               value = raw_of(c, st.from) })
      end
      reaper.ImGui_SameLine(ctx)
      if btn("Rampa##rp", "primary") then
        exec({ type = "cc_ramp", label = c.label .. " rampa", cc = c.cc,
               from = raw_of(c, st.from), to = raw_of(c, st.to) })
      end
      for pi, p in ipairs(c.presets or {}) do
        reaper.ImGui_SameLine(ctx)
        if btn(p.label .. "##ps" .. pi, "neutral") then
          exec({ type = "cc_point", label = c.label .. " " .. p.label,
                 cc = c.cc, value = p.value })
        end
      end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end

  local function draw_position(group, gi)
    local list = {}
    for _, c in ipairs(group.controls) do
      if c.kind == "position" then list[#list + 1] = c end
    end
    if #list == 0 then return end

    local flags = reaper.ImGui_TableFlags_SizingFixedFit()
    if not reaper.ImGui_BeginTable(ctx, "pos" .. gi, 3, flags) then return end
    local fixed = reaper.ImGui_TableColumnFlags_WidthFixed()
    reaper.ImGui_TableSetupColumn(ctx, "Control", fixed, 130)
    reaper.ImGui_TableSetupColumn(ctx, "Posicion", fixed, 224)
    reaper.ImGui_TableSetupColumn(ctx, "Accion", fixed, 0)
    reaper.ImGui_TableHeadersRow(ctx)

    for i, c in ipairs(list) do
      local first = c.first or 1
      reaper.ImGui_PushID(ctx, "p" .. i)
      reaper.ImGui_TableNextRow(ctx)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, c.label)

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -1)
      local _, n = reaper.ImGui_SliderInt(ctx, "##pos", S.pos[c] or first,
        first, first + c.count - 1, "Pos %d")
      S.pos[c] = n

      reaper.ImGui_TableNextColumn(ctx)
      if btn("Aplicar##ap", "primary") then
        local spec, err = Map.position_spec(live_cfg(), c, n)
        if spec then
          if spec.type == "keyswitch" then spec.mode = MODES[S.mode] end
          exec(spec)
        else
          S.status, S.status_ok = c.label .. ": " .. err, false
        end
      end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end

  local function draw()
    reaper.ImGui_Text(ctx, "Modo KS:")
    for i, label in ipairs(MODE_LABELS) do
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_RadioButton(ctx, label, S.mode == i) then S.mode = i end
    end

    reaper.ImGui_SetNextItemWidth(ctx, 110)
    local _, o = reaper.ImGui_SliderInt(ctx, "Offset##ks_off", S.ks_offset, -240, 240)
    S.ks_offset = o
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 110)
    local _, l = reaper.ImGui_SliderInt(ctx, "Largo##ks_len", S.ks_length, 1, 960)
    S.ks_length = l
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 110)
    local _, v = reaper.ImGui_SliderInt(ctx, "Vel##ks_vel", S.ks_velocity, 1, 127)
    S.ks_velocity = v

    reaper.ImGui_Text(ctx, "Curva:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 110)
    local _, sh = reaper.ImGui_Combo(ctx, "##shape", S.shape, SHAPE_ITEMS)
    S.shape = sh
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_BeginDisabled(ctx, S.shape ~= BEZIER_IDX)
    reaper.ImGui_SetNextItemWidth(ctx, 110)
    local _, t = reaper.ImGui_SliderDouble(ctx, "Tension##tension", S.tension, -1.0, 1.0, "%.2f")
    S.tension = t
    reaper.ImGui_EndDisabled(ctx)

    reaper.ImGui_Separator(ctx)
    local now = reaper.time_precise()
    if S.mode ~= 1 and now - S.src_t > SOURCE_REFRESH_S then
      S.src_label, S.src_err = Core.describe_source()
      S.src_t = now
    end
    if S.mode == 1 then
      reaper.ImGui_Text(ctx, " ")
    else
      reaper.ImGui_Text(ctx, "Fuente: " .. (S.src_label or S.src_err or "-"))
    end
    local color = S.status_ok and COLOR_OK or COLOR_ERR
    reaper.ImGui_TextColored(ctx, color, S.status ~= "" and S.status or " ")
    reaper.ImGui_Separator(ctx)

    for gi, group in ipairs(cfg.groups) do
      reaper.ImGui_PushID(ctx, "g" .. gi)
      reaper.ImGui_Text(ctx, group.title)
      draw_ks(group)
      draw_ks_variants(group, gi)
      draw_cc(group, gi)
      draw_position(group, gi)
      reaper.ImGui_PopID(ctx)
      reaper.ImGui_Spacing(ctx)
    end
  end

  local was_active = false

  local function return_focus_if_idle()
    local active = reaper.ImGui_IsAnyItemActive(ctx)
    local popup = reaper.ImGui_IsPopupOpen(ctx, "", reaper.ImGui_PopupFlags_AnyPopupId())
    local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
    local hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_ChildWindows())
    local released = was_active and not active
    local left = focused and not hovered
    was_active = active
    if active or popup then return end
    if released or left then
      HostFocus.toHwnd(reaper.MIDIEditor_GetActive())
    end
  end

  local function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 620, 640, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, title, true, reaper.ImGui_WindowFlags_NoNav())
    if visible then
      draw()
      if RETURN_FOCUS_TO_EDITOR then return_focus_if_idle() end
      reaper.ImGui_End(ctx)
    end
    if open then reaper.defer(loop) end
  end

  reaper.defer(loop)
end

return M