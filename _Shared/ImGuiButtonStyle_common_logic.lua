-- ImGuiButtonStyle_common_logic.lua
-- Estilo semantico de botones ReaImGui (primario, neutro, peligro). Genera
-- solo color y redondeo: no toca anchos, SameLine ni layout.
-- Patron dofile + M={}. Vive en _Shared/ porque es
-- generico y lo consumen las tabs del Helper (y luego ring_button).
--
-- Colores en formato ReaImGui 0xRRGGBBAA. La paleta es editable en vivo
-- desde Tests-Debug/Nik_Test_ButtonStyle.lua (M.palette es la tabla real).

local M = {}

M.KINDS = { 'primary', 'neutral', 'danger', 'subtle' }

-- Mezcla un canal de cada byte RGB de color (0xRRGGBBAA) hacia target
-- (255 = blanco, 0 = negro) en proporcion t. El alfa no se toca.
local function mix(color, target, t)
  local function ch(shift)
    local c = (color >> shift) & 0xFF
    return math.floor(c + (target - c) * t + 0.5)
  end
  return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | (color & 0xFF)
end

-- hovered mas claro y active mas oscuro que la base.
function M.derive(base)
  return { button = base, hovered = mix(base, 255, 0.18), active = mix(base, 0, 0.18) }
end

-- Campo ausente = se deja el color default del tema (no se apila nada).
M.palette = {
  primary = M.derive(0xB8FF6DFF),
  neutral = {},
  danger  = M.derive(0xA83232FF),
  subtle  = { button = 0x00000000, hovered = 0xFFFFFF26, active = 0xFFFFFF40 },
}
M.palette.primary.text = 0x000000FF
M.palette.danger.text = 0xFFFFFFFF

M.rounding = 4

local COLOR_FIELDS = {
  { field = 'button',  col = 'ImGui_Col_Button' },
  { field = 'hovered', col = 'ImGui_Col_ButtonHovered' },
  { field = 'active',  col = 'ImGui_Col_ButtonActive' },
  { field = 'text',    col = 'ImGui_Col_Text' },
}

-- Pila con la cantidad de colores apilados por cada push: la cantidad
-- depende del tipo, asi pop siempre desapila lo que apilo su push.
local pushed = {}

local function resolve(kind)
  return M.palette[kind] or M.palette.neutral  -- tipo desconocido -> neutro
end

function M.push(ctx, kind)
  local p = resolve(kind)
  local n = 0
  for _, cf in ipairs(COLOR_FIELDS) do
    local v = p[cf.field]
    if v then
      reaper.ImGui_PushStyleColor(ctx, reaper[cf.col](), v)
      n = n + 1
    end
  end
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), M.rounding)
  pushed[#pushed + 1] = n
end

function M.pop(ctx)
  local n = table.remove(pushed)
  if not n then return end
  reaper.ImGui_PopStyleVar(ctx, 1)
  if n > 0 then reaper.ImGui_PopStyleColor(ctx, n) end
end

-- Texto visible de una etiqueta ImGui (sin el sufijo ## o ### de ID).
local function visibleText(label)
  return label:match('^(.-)##') or label
end

-- Ancho segun opts: w fijo (negativo = rellenar), o pad = margen a cada
-- lado del texto (con min_w opcional), o 0 = tamano nativo.
function M.width(ctx, label, opts)
  if opts.w then return opts.w end
  if opts.pad then
    local tw = reaper.ImGui_CalcTextSize(ctx, visibleText(label))
    return math.max(tw + 2 * opts.pad, opts.min_w or 0)
  end
  return 0
end

-- Boton completo: push, Button, pop. Devuelve true si hubo clic.
-- opts: numero (ancho fijo) o tabla { w, pad, min_w, h }. nil = nativo.
function M.button(ctx, label, kind, opts)
  if type(opts) == 'number' then opts = { w = opts } end
  opts = opts or {}
  local w = M.width(ctx, label, opts)
  M.push(ctx, kind)
  local clicked = reaper.ImGui_Button(ctx, label, w, opts.h or 0)
  M.pop(ctx)
  return clicked
end

return M
