-- Nik_Test_ButtonStyle.lua
-- Vista previa de ImGuiButtonStyle_common_logic.lua. Muestra los tipos de
-- boton sueltos, deshabilitados, en fila con SameLine y dentro de una tabla
-- (balance de Push/Pop). Los selectores de color editan la paleta en vivo;
-- "Imprimir paleta" la vuelca a la consola lista para pegar en el modulo.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Style = dofile(script_dir .. "../_Shared/ImGuiButtonStyle_common_logic.lua")

local ctx = reaper.ImGui_CreateContext('Test ButtonStyle')

local LABELS = { primary = 'Agregar', neutral = 'Ir', danger = 'Borrar', subtle = 'Recargar' }
local FIELDS = { 'button', 'hovered', 'active', 'text' }

local function drawPreview()
  reaper.ImGui_Text(ctx, 'Sueltos')
  for _, kind in ipairs(Style.KINDS) do
    Style.button(ctx, LABELS[kind] .. '##solo_' .. kind, kind, 100, 0)
    reaper.ImGui_SameLine(ctx)
  end
  reaper.ImGui_NewLine(ctx)

  reaper.ImGui_Text(ctx, 'Deshabilitados')
  reaper.ImGui_BeginDisabled(ctx)
  for _, kind in ipairs(Style.KINDS) do
    Style.button(ctx, LABELS[kind] .. '##dis_' .. kind, kind, 100, 0)
    reaper.ImGui_SameLine(ctx)
  end
  reaper.ImGui_EndDisabled(ctx)
  reaper.ImGui_NewLine(ctx)

  reaper.ImGui_Text(ctx, 'Anchos de Armonia (Ir 52, Borrar 62) y boton nativo de referencia')
  Style.button(ctx, 'Ir##w', 'neutral', 52, 0)
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, 'Borrar##w', 'danger', 62, 0)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Button(ctx, 'Nativo', 62, 0)
  reaper.ImGui_Spacing(ctx)

  reaper.ImGui_Text(ctx, 'Ancho por texto + margen (pad 4, 12, 24; pad 4 con minimo 52) y subtle')
  Style.button(ctx, 'Ir##p4', 'neutral', { pad = 4 })
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, 'Ir##p12', 'neutral', { pad = 12 })
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, 'Ir##p24', 'neutral', { pad = 24 })
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, 'Ir##min', 'neutral', { pad = 4, min_w = 52 })
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, 'Recargar##sub', 'subtle', { pad = 10 })
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, '+##sub', 'subtle', { w = 22 })
  reaper.ImGui_SameLine(ctx)
  Style.button(ctx, '-##sub', 'subtle', { w = 22 })
  reaper.ImGui_Spacing(ctx)

  reaper.ImGui_Text(ctx, 'Dentro de tabla')
  if reaper.ImGui_BeginTable(ctx, 'tbl_preview', 3, reaper.ImGui_TableFlags_Borders()) then
    for row = 1, 3 do
      reaper.ImGui_PushID(ctx, row)
      for _, kind in ipairs(Style.KINDS) do
        reaper.ImGui_TableNextColumn(ctx)
        Style.button(ctx, LABELS[kind] .. '##t_' .. kind, kind, -1, 0)
      end
      reaper.ImGui_PopID(ctx)
    end
    reaper.ImGui_EndTable(ctx)
  end
end

local function drawPaletteEditor()
  reaper.ImGui_Text(ctx, 'Paleta (edicion en vivo)')
  local flags = reaper.ImGui_ColorEditFlags_NoInputs()
  for _, kind in ipairs(Style.KINDS) do
    reaper.ImGui_Text(ctx, string.format('%-8s', kind))
    for _, f in ipairs(FIELDS) do
      reaper.ImGui_SameLine(ctx)
      local cur = Style.palette[kind][f]
      local label = (cur and f or (f .. ' def')) .. '###' .. kind .. f
      local changed, col = reaper.ImGui_ColorEdit4(ctx, label, cur or 0x808080FF, flags)
      if changed then Style.palette[kind][f] = col end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, 'default##' .. kind) then Style.palette[kind] = {} end
  end
  local _, r = reaper.ImGui_SliderInt(ctx, 'Redondeo', Style.rounding, 0, 12)
  Style.rounding = r
  if reaper.ImGui_Button(ctx, 'Imprimir paleta') then
    local out = { 'M.rounding = ' .. Style.rounding, 'M.palette = {' }
    for _, kind in ipairs(Style.KINDS) do
      local p = Style.palette[kind]
      local parts = {}
      for _, f in ipairs(FIELDS) do
        if p[f] then parts[#parts + 1] = string.format('%s = 0x%08X', f, p[f]) end
      end
      out[#out + 1] = string.format('  %-7s = { %s },', kind, table.concat(parts, ', '))
    end
    out[#out + 1] = '}'
    reaper.ShowConsoleMsg(table.concat(out, '\n') .. '\n')
  end
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 560, 480, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Test ButtonStyle', true)
  if visible then
    drawPreview()
    reaper.ImGui_Separator(ctx)
    drawPaletteEditor()
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
