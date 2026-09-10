# Arquitectura: Input+commit y teclado como transporte (ReaImGui)

Basado en `test_input_enter_y_teclado_transporte.lua`. Patrones ya validados,
listos para portar a la UI real.

## A) Input + botón, commit único por Enter real o click en botón

**Problema que resuelve:** commit accidental al clickear afuera del input
(en cualquier otro punto de la ventana) después de tipear.

**Reglas:**
- `InputText` **sin** el flag `EnterReturnsTrue`. El buffer se sincroniza en
  cada tecla → cualquier botón externo siempre lee el valor real tipeado.
- `IsItemFocused` **no sirve** para distinguir Enter de click-afuera: clickear
  un widget no-focusable (Text, Dummy) no le quita el foco al input.
- Señal correcta: Enter y la deactivation del item ocurren en el **mismo
  frame** (la propia tecla causa la deactivation). Un click afuera deactiva
  sin que se haya presionado Enter ese frame.

```lua
local changed, new_buf = ImGui_InputText(ctx, '##item', buf)
if changed then buf = new_buf end

local deact_edit = ImGui_IsItemDeactivatedAfterEdit(ctx)
local enter_key  = ImGui_IsKeyPressed(ctx, ImGui_Key_Enter(), false)
                 or ImGui_IsKeyPressed(ctx, ImGui_Key_KeypadEnter(), false)
local enter_commit = deact_edit and enter_key

ImGui_SameLine(ctx)
local clicked = ImGui_Button(ctx, 'Agregar')

if (enter_commit or clicked) and buf ~= '' then
  -- commit real: por Enter o por boton
end
```

**Extensión a N inputs:** el mismo par `(deact_edit, enter_key)` se calcula
por widget, inmediatamente después de dibujarlo (son funciones "sobre el
último item"). No hay estado global que compartir entre inputs — cada uno
resuelve su propio commit de forma independiente.

## B) Teclado como transporte, sin robar foco de REAPER

**Problema que resuelve:** mover cursor de edición / play-pause desde la UI
sin tener que alternar foco ventana↔REAPER, y sin que el atajo nativo de
REAPER se dispare en paralelo (doble movimiento).

**Validado:** con foco en la ventana ImGui, un atajo de teclado nativo de
REAPER (ej. ir a marker siguiente) **no se ejecuta** — ReaImGui captura la
tecla de forma exclusiva. No hay riesgo de doble disparo.

### B.1 — Evitar el recuadro de navegación de ImGui

Las flechas por defecto mueven el foco visual entre widgets (Nav de Dear
ImGui), interfiere con usarlas como atajos propios. Se desactiva por
ventana, no afecta la lectura de teclas:

```lua
ImGui_Begin(ctx, 'Titulo', true, ImGui_WindowFlags_NoNav())
```

### B.2 — Leer teclas y ejecutar acciones nativas

```lua
if ImGui_IsWindowFocused(ctx) then
  if ImGui_IsKeyPressed(ctx, KEY_X, false) then
    Main_OnCommand(CMD_ID_X, 0)
  end
end
```

- `repeat = false` en `IsKeyPressed` evita múltiples disparos si la tecla
  se mantiene apretada (salvo que se quiera repeat explícitamente).
- Los Command ID de acciones nativas se buscan en el Action List (click
  derecho → "Copy selected action command ID") y se declaran como
  constantes con nombre — no asumir, siempre confirmar ahí.

### B.3 — Guard global para teclas "libres" (Space/Enter → transporte)

Teclas usadas también por widgets (Enter, Space) necesitan chequear que
**ningún** item esté activo antes de interpretarlas como atajo global:

```lua
if not ImGui_IsAnyItemActive(ctx) then
  if ImGui_IsKeyPressed(ctx, ImGui_Key_Space(), false) then
    Main_OnCommand(CMD_PLAYSTOP, 0)
  end
end
```

`IsAnyItemActive` es un chequeo de todo el contexto, no por widget → escala
sin trackear cada input/dropdown/lista a mano.

### B.4 — Conflicto Enter: commit de input vs. atajo global

`IsAnyItemActive` no alcanza para Enter específicamente: el input se
desactiva en el **mismo frame** en que se presiona Enter, así que para
cuando se evalúa el guard de B.3, el item ya figura inactivo y el atajo
global se dispararía igual, duplicando el evento (agrega el item **y**
pausa el transporte a la vez).

**Solución:** flag de un frame que "consume" la tecla en el punto donde se
usó, para que ningún otro handler la vuelva a interpretar ese mismo frame.

```lua
-- en el frame, antes de dibujar nada:
consumed_enter = false

-- seccion A, junto al commit del input:
consumed_enter = enter_commit

-- seccion B, atajo global:
if not consumed_enter and (enter_key_pressed) then
  Main_OnCommand(CMD_PLAYPAUSE, 0)
end
```

## Extensión a una UI con muchos componentes

- **Cada input** resuelve su propio commit con el patrón de A — no hay
  estado compartido entre inputs, cada widget es independiente.
- **`IsAnyItemActive`** ya cubre inputs, dropdowns, listas con botones,
  etc. sin cambios — es la razón por la que se eligió ese guard y no una
  lista manual de "¿qué widget está activo?".
- **Dropdowns (Combo) con popup abierto:** no confirmado si heredan
  `WindowFlags_NoNav` de la ventana padre o si el popup necesita su propio
  flag — validar en cuanto se agregue el primer dropdown real.
- **Teclas que colisionan con edición de texto** (Enter, Space, y
  potencialmente Backspace/flechas si se usan como atajo) requieren el
  patrón `consumed_*` de B.4 — no alcanza con `IsAnyItemActive` solo,
  porque la desactivación y el key-press pueden coincidir en el mismo
  frame. Generalizar como *"todo handler que consume una tecla puntual
  marca un flag de ese frame; los atajos globales de esa misma tecla
  chequean el flag antes de disparar"* — no hace falta una tabla de
  conflictos por widget, un flag por tecla candidata alcanza.
- **Teclas sin colisión posible** (flechas para navegación custom, sin
  ningún input activo posible en simultáneo) no necesitan flag de
  consumo — alcanza con el guard de ventana enfocada (B.2).
