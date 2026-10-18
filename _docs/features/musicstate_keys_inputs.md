# Feature — MusicState: teclas de inputs y combo del Helper (ReaImGui)

Teclas que son del widget y no de la ventana: input con perfil de teclas,
anillo de foco (Tab y flechas entre inputs) y combo con teclado. Lo lee
quien toca `Keys.input`, `Keys.ring_*`, `RowInputs`, el combo de Tonalidad
o agrega un input navegable a una tab. Despacho central, guards, bindings,
modales y foco con REAPER: `musicstate_keys.md`. Patrones genéricos de
ReaImGui: `08_REAIMGUI_PATTERNS.md`.

## 1. Archivos

| Archivo | Rol |
|---|---|
| `MusicState/MusicStateKeys_common_logic.lua` | `Keys.input` (§2) y `Keys.ring_*` (§3), junto al despacho |
| `MusicState/MusicStateRowInputs_common_logic.lua` | Registra Compás, Beat y Cent. en el anillo y arma el perfil de flechas que cambia el valor (§4) |
| `_Shared/ImGuiKeyCombo_common_logic.lua` | Combo con teclado (§5); lo usa la tónica de la tab Tonalidad (`musicstate_helper.md` §2.1) |
| `MusicState/MusicStateRoles_common_logic.lua` | Usa `Keys.input` (§6) |
| `MusicState/MusicStateArmonia_common_logic.lua` | Usa el anillo de foco (§3, §4) |

## 2. Input con perfil

`Keys.input(ctx, label, value, profile)` dibuja un `InputText` y aplica el
perfil de teclas del widget. Devuelve `changed, valor, commit`. Campos del
perfil, todos opcionales:

| Campo | Valores | Efecto |
|---|---|---|
| `on_enter` | `'commit'` (defecto) \| `'none'` | `commit` devuelve true si Enter (sin repeat) cierra una edición |
| `keep_focus` | `false` (defecto) \| `'when_empty'` \| `'always'` | Devuelve el foco al input tras Enter: con el buffer vacío, o siempre |

Llama a `Keys.consume('Enter')` cuando Enter termina la edición. Enter y
Esc cierran el campo (los resuelve ImGui) y no se refocusea salvo con
`keep_focus`. Tab y las flechas no son campos de este perfil: los resuelve
el anillo de foco (§3).

## 3. Anillo de foco

Tab y Shift+Tab recorren los inputs de la tab activa, y las flechas ejecutan
el perfil de cada input. El estado es por tab (lista de items registrados,
orden propio, pedido de foco pendiente) y se reinicia al cambiar de tab. Lo
usa Armonía.

| Función | Dónde se llama | Qué hace |
|---|---|---|
| `Keys.ring_focus(ctx, owner, col)` | Justo **antes** del widget | Si hay un pedido pendiente para `(owner, col)` y ya pasó su frame, `SetKeyboardFocusHere(ctx, 0)` |
| `Keys.ring_item(ctx, owner, col, meta, perfil)` | Justo **después** del widget, y después de volcar su valor a los datos | Registra el item. Con el widget activo, Tab y Shift+Tab dejan un pedido hacia el anterior o el siguiente, y las flechas llaman al perfil |
| `Keys.ring_request(owner, col, hold)` | Donde se quiera pedir foco (ej. "+ Agregar fila") | Deja un pedido pendiente; con `hold`, ver abajo |
| `Keys.ring_holds(owner)` | En quien decide qué fila está activa | true mientras un refoco con `hold` está pendiente o recién aplicado |
| `Keys.ring_neighbor(owner, col, dir, opts)` | Dentro de un `on_up` / `on_down` | Pide el foco del vecino (`dir` = ±1). `opts.same_col`: solo la misma columna. `opts.by_group`: primer item de la misma columna del grupo vecino (`meta.group`) |
| `Keys.ring_config(tab, { order = fn })` | Al armar la tab (opcional) | Orden propio de Tab: `fn(items)` recibe una copia de la lista del frame anterior |

Reglas:

- `owner` identifica el widget entre frames: es la tabla de la fila, nunca el
  índice. Armonía usa `row._uid` en el `PushID`, así un reorden no corre el ID
  de un input enfocado.
- Los items de un frame se consultan en el siguiente (lista del frame
  anterior). El orden por defecto es el de dibujado.
- El pedido se aplica el frame siguiente (el reorden de la fila de origen
  ocurre antes) y expira a los 2 frames si el destino no se dibuja (grupo
  colapsado, fila borrada).
- Tab no da la vuelta: en el último item no hace nada. Repite con `delay` y
  `rate` de `autorepeat`, con un timer para Tab y uno por flecha. Sin ningún
  item activo, Tab entra al primer item y Shift+Tab al último (en `dispatch`,
  con los guards de `musicstate_keys.md` §3).
- Perfil `{ on_up, on_down }`, con `fn(owner, col, shift)`, sin modificadores o
  con Shift. Sin perfil las flechas no hacen nada.
- `ring_focus` va antes del widget y con offset 0: con `-1` después de un
  `InputInt` el foco no llegaba al campo. El `-1` posterior sirve para
  `InputText` (§2, §6).
- Un `InputInt` activo ignora el valor que se le pasa desde afuera. Para
  cambiarlo desde un perfil se cambia el ID del widget (`row._ver_<campo>`,
  campo interno como `_uid`, no se publica) y se pide el foco con `hold`.
  `ring_holds` hace que `drawPositionInputs` siga devolviendo la fila como
  activa: no se reordena ni cambia de grupo hasta salir del trío de posición.
- `ring_item` va después de la asignación `row.<campo> = valor del widget`: si
  va antes, el cambio del perfil se pisa con el valor viejo.
- Los grupos colapsados no se dibujan, así que el anillo los salta solo.

## 4. Perfil de flechas en Armonía

| Campo | ↑ / ↓ | Shift+↑ / Shift+↓ |
|---|---|---|
| Compás | ±1 (mínimo 1) | ±4 |
| Beat | ±1 (1..tope del compás) | ±4 |
| Cent. | ±5 (0..99) | ±25 |
| Acorde | Acorde de la fila anterior / siguiente | Primer Acorde de la sección abierta anterior / siguiente |

El orden de Tab es Compás, Beat, Cent., Acorde, fila por fila. El reorden
corre al pasar de Cent. a Acorde (salir del trío de posición), no al salir de
cada campo. Enter y Esc cierran el campo. Cues no pasa `ring` ni
`arrow_values` a `drawPositionInputs`, y las demás tabs no registran items.

## 5. Combo con teclado

`_Shared/ImGuiKeyCombo_common_logic.lua`: `BeginCombo` + `Selectable` con
lista propia, porque `ImGui_Combo` no permite saber qué ítem está resaltado
ni interceptar teclas dentro del popup. Wrapper genérico, reutilizable por
otros dropdowns.

- Letras A–G saltan al ítem (repetir la letra cicla entre A, A#, Ab…),
  ↑/↓ mueven el resaltado, Enter confirma, Esc cierra sin seleccionar.
- ImGui sigue siendo dueño de flechas, Enter y Esc (el popup no hereda el
  `NoNav` de la raíz). El módulo suma las letras con ciclo
  (`SetKeyboardFocusHere` mueve el foco real; la letra inicial sale de los
  ítems).
- El foco por teclado no se dibuja ni activa con Enter tras una letra: el
  módulo dibuja el resaltado propio y confirma con Enter solo si el último
  gesto fue una letra.
- Un click selecciona; Enter no actúa sobre el hover.
- Con el popup abierto los atajos globales no actúan, ni siquiera en el
  frame en que el popup se cierra solo (`musicstate_keys.md` §3).

## 6. Caso Roles

Roles usa `Keys.input` con `{ on_enter = 'commit', keep_focus = 'always' }`:
Enter con el input vacío deja el cursor ahí, y con texto agrega el rol y
también lo deja (para cargar varios seguidos).

Mecánica: `SetKeyboardFocusHere(ctx, -1)` justo después de dibujar el
`InputText` (el `-1` apunta al widget anterior). Con Enter mantenido el
sistema repite la tecla y ImGui desactiva el input en cada repetición: el
refoco lee Enter **con repeat** y el commit **sin repeat**, así no se
duplican roles. Enter en Roles, tocado o mantenido, no dispara Play/Pause
(`musicstate_helper.md` §7).

## 7. Hallazgos de las sondas

- `SetKeyboardFocusHere` mueve el foco entre inputs de un `BeginChild` con
  scroll: es la base del anillo de foco (§3).
- Con un combo nativo abierto, el contador de popups sube al apretar Esc
  mientras se mantiene el clic sobre un ítem.
- El combo nativo se cierra en `NewFrame` (hallazgo y solución:
  `musicstate_keys.md` §3, `popup_prev`).

Sondas: `Tests-Debug/Nik_Test_KeysFocusProbe.lua` y
`Nik_Test_KeysFocusRequest.lua`.

## 8. Cómo testear

1. Anillo de foco (Armonía): Tab y Shift+Tab recorren Compás, Beat, Cent. y
   Acorde fila por fila, y mantenidos repiten; sin foco, Tab entra al primer
   item y Shift+Tab al último; ↑/↓ en Acorde pasan de fila y con Shift saltan
   a la sección abierta vecina; ↑/↓ en Compás, Beat y Cent. cambian el valor
   con los pasos de §4 y el clamp; ↑ hasta cruzar de sección mantiene el
   foco y reordena recién al salir del trío; en las demás tabs no hacen
   nada.
2. Roles: Enter con el input vacío no agrega nada y deja el cursor; con
   texto agrega un rol y lo deja; Enter mantenido no duplica roles ni
   dispara Play/Pause.
3. Combo de Tonalidad: las letras saltan al ítem y repetidas ciclan; ↑/↓
   mueven el resaltado; Enter confirma y Esc cierra sin cambiar; un click
   selecciona; ningún atajo global actúa con el popup abierto.

## 9. Pendientes

- **Widgets que no son de texto** (checkbox y botones de Armonía): foco
  propio, con recuadro dibujado por nosotros, y Space o Enter para
  accionarlos.
- **Entrada al anillo:** entrar por la fila del cursor y no por la primera.
- **Cues sobre el mismo anillo:** `musicstate_helper.md` §9.
- **Bugs conocidos del combo** (todos en `updateMouseGesture`):
  - Cualquier delta del mouse, incluso fuera del popup o un temblor, apaga
    el recuadro de foco que acaba de prender una flecha.
  - Mouse y después ↑/↓: el recuadro parpadea (la flecha lo prende y el
    delta residual del frame siguiente lo apaga).
  - Un umbral de distancia a un ancla (re-anclando en cada flecha o letra)
    y un filtro con `IsWindowHovered` no lo resuelven. Falta otra señal para
    "el mouse tomó el control".

## 10. Para retomar en otra sesión

Adjuntar: este doc, `musicstate_keys.md`, `musicstate_helper.md`,
`08_REAIMGUI_PATTERNS.md`, `MusicStateKeys_common_logic.lua`,
`MusicStateRowInputs_common_logic.lua` e `ImGuiKeyCombo_common_logic.lua`.
Para el anillo en una tab, además el módulo de esa tab.
`Nik_MusicState_Helper.lua` solo si hace falta (archivo grande: alcanzan las
líneas de `dofile`, `helpers` y el loop con los atajos globales).
