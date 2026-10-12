# Feature — MusicState: atajos de teclado del Helper (ReaImGui)

Despacho central de teclas del Helper (`Nik_MusicState_Helper.lua`): atajos
globales que se reenvían a REAPER, bindings por tab, repetición por hold,
teclas de los modales y paso del foco del teclado entre el Helper y REAPER.
Es solo del panel nativo ReaImGui; el prompter web tiene su propio manejo
(ver `musicstate_instrumentista.md`).

Las §1 a §8 describen **cómo está hecho hoy**. La §9 recoge los pasos del
refactor: los hechos (con sus bugs conocidos) y el diseño ya acordado de los
pendientes, para retomarlos sin repetir la discusión.

## 1. Archivos

| Archivo | Rol |
|---|---|
| `MusicState/MusicStateKeys_common_logic.lua` | Despacho: bindings, guards, repetición, colisiones, `Keys.held`, `Keys.modal`, `Keys.consume`, `Keys.input`, `Keys.ring_*` (anillo de foco, §4.7) |
| `MusicState/MusicStateKeys_config.lua` | Bindings globales y por tab, en datos puros (convención de `<Dominio>_config.lua`, ver `01_CONVENCIONES.md`) |
| `_Shared/ImGuiHostFocus_common_logic.lua` | Foco del teclado ventana ReaImGui ↔ REAPER y anti-rebote por auto-repeat |
| `_Shared/ImGuiConfirmModal_common_logic.lua` | Ciclo de vida común de un modal de confirmación |
| `MusicState/Nik_MusicState_FocusHelper.lua` | One-shot para REAPER: lleva el foco al Helper |
| `Nik_MusicState_Helper.lua` | Carga los módulos, registra las acciones Lua (`host_focus`, `close_helper`) y llama al ciclo de frame |
| `MusicStateLyricsSync_common_logic.lua` | `register_keys`: la tecla de tap `B` como hold de la tab Lyrics |
| `MusicState/MusicStateRowInputs_common_logic.lua` | Registra Compás, Beat y Cent. en el anillo de foco y arma el perfil de flechas que cambia el valor (§4.7) |

## 2. Ciclo del frame

Todo dentro del `if visible` del Helper:

```lua
Keys.begin_frame(ctx)    -- al inicio: fotos del estado
Keys.set_tab('Lyrics')   -- dentro de cada BeginTabItem
Keys.dispatch(ctx)       -- justo antes de ImGui_End
```

**El despacho va al final del frame, no al inicio.** Así ve lo que pasó
durante el frame (tab dibujada, popup abierto, teclas consumidas) y las
teclas de una tab dependen de la tab de ese mismo frame, sin lag. Lo que
necesita el estado de *antes* del frame (¿había un campo en edición?) se
toma como foto en `begin_frame`.

`begin_frame` registra: `focused` (`IsWindowFocused` con `ChildWindows`),
`item_active_start` (`IsAnyItemActive`) y `popup_start` (`IsPopupOpen` con
`AnyPopupId`).

## 3. Guards

Un binding actúa solo si se cumplen todos:

- La ventana tiene el foco (con `ChildWindows`: una tabla con `ScrollY` crea
  una ventana hija, ver `08_REAIMGUI_PATTERNS.md` §5).
- No había un item activo **al inicio del frame** ni lo hay ahora.
- No había un popup abierto **al inicio del frame** ni lo hay ahora.
- La tecla no fue consumida este frame (`Keys.consume(nombre)`).
- Los modificadores coinciden **exactamente** (Shift+→ no dispara →).
- No cambió la tab en este frame.

**Por qué las dos fotos del inicio.** Con el despacho al final, el Enter que
commitea un input desactiva el item en ese mismo frame: sin la foto de
`IsAnyItemActive`, el atajo global dispararía igual (el viejo problema de
`consumed_enter`). Con el popup pasa lo mismo al revés:
`CloseCurrentPopup` cierra el popup en el mismo frame, así que el Enter que
confirma un modal (o el Esc que lo cancela) llegaba al `dispatch` con
`IsPopupOpen` en `false` y reproducía o limpiaba la selección de tiempo.
Bug real, confirmado en el modal de alta de Lyrics.

**Popups que ImGui cierra solo.** Un combo nativo se cierra con Esc o Enter
dentro de `NewFrame`, antes de `begin_frame`: la foto del inicio ya lo ve
cerrado y el Esc o el Enter llegaba al `dispatch` con todos los guards
abiertos (limpiaba la selección de tiempo o reproducía). `dispatch` guarda el
estado **vivo** de los popups al final del frame (`popup_prev`) y
`begin_frame` lo suma a `popup_start`: un popup abierto al terminar el frame
anterior cuenta como abierto en este. Se guarda el estado vivo y no
`popup`, que ya incluye la foto del inicio y nunca se apagaría. Costo: tras
cerrarse un popup los atajos quedan cerrados un frame más.

`ignore_item_active` e `ignore_popup` relajan estos guards por binding (F4
los usa los dos: una tecla de función no se tipea).

`Keys.consume('Enter')` queda para los widgets que usan una tecla
puntual; `Keys.input` (§4.6) lo llama solo cuando Enter termina una edición.

## 4. Bindings

### 4.1 Campos

Documentados en el encabezado de `MusicStateKeys_config.lua`. Resumen:

- `id` único, convención `<área>.<acción>` (`time.go_start`, `lyrics.tap`).
- `key`: nombre de tecla de ReaImGui sin el prefijo `ImGui_Key_`.
- `mods`: `{ 'ctrl', 'shift', 'alt', 'super' }`, comparados exactos.
- Qué hacer, uno solo: `cmd` (número de acción de REAPER, o **nombre** de una
  acción con ID estable entre PCs: `'_SWS_…'`, `'_S&M_…'`, resuelto con
  `NamedCommandLookup`), `action` (nombre de una función Lua que el Helper
  registra en `Keys.init`) o `fn` (función, solo en bindings de tab).
- `kind`: `'press'` (por defecto) o `'hold'`.
- `autorepeat`: `true` (valores globales) o `{ delay =, rate = }`.
- `ignore_item_active`, `ignore_popup`, `override`.

### 4.2 Tipos

- **`press`:** un disparo por flanco de subida (`IsKeyPressed` sin repeat).
- **`press` con `autorepeat`:** tras `delay` segundos apretada repite cada
  `rate`. Timer propio (`IsKeyDown` + `time_precise`), no el repeat nativo de
  ImGui (delay y rate compartidos por todo el contexto). Solo se prende con un
  press que ocurre con **todos** los guards abiertos; se apaga al soltar,
  al perder foco, al cambiar de tab o al cerrarse cualquier guard. Cerrar un
  modal con la tecla apretada no dispara de golpe. El piso de la cadencia es
  el frame del `defer` (~30 ms). Valores por defecto `delay = 0.5`,
  `rate = 0.15`, pensados para afinar a mano en la config.
- **`hold`:** no se despacha. Se consulta con `Keys.held(ctx, id)`, que se
  evalúa **en el momento de la llamada** (durante el draw de la tab), no en el
  `dispatch` del final del frame: el tap de Lyrics no puede perder un frame de
  latencia (la compensación de -150 ms quedaría descalibrada). Los flancos
  (press/release) los detecta quien consulta, con su propio estado previo
  (`08_REAIMGUI_PATTERNS.md` §4).

### 4.3 Colisiones

Se validan al registrar y se reportan por consola (`[MusicStateKeys]`):

- id repetido, tecla desconocida, modificador desconocido, falta o exceso de
  `cmd`/`action`/`fn`, `fn` en un binding global, `cmd` que no existe en esta
  PC, `hold` con acción o `autorepeat`;
- misma tecla y modificadores dos veces en la **capa global** o dos veces en la
  **misma tab**: se ignora la segunda;
- una tecla de tab que pisa una global: error y se ignora la de tab, salvo
  `override = true`, que suprime la global solo mientras esa tab está activa.
  Si la `fn` de ese binding devuelve `false` ("no la usé"), el despacho
  ejecuta la global suprimida (el binding de tab guarda la referencia en
  `overrides`). Solo un `false` explícito, solo con `override`; una `fn` que no
  devuelve nada cuenta como usada.

Un `cmd` con nombre que empieza con `_RS` (ID de un script) avisa pero carga:
cambia entre PCs (ver `00_CONTEXTO_GENERAL.md`, Command ID) y el config se
despliega por ReaPack.

### 4.4 Bindings actuales

Globales (`MusicStateKeys_config.lua`, sección `global`):

| id | Tecla | Acción |
|---|---|---|
| `transport.playstop` | Space | 40044 |
| `transport.playpause` | Enter | 40073 |
| `nav.measure_prev` / `nav.measure_next` | ← / → (repiten) | 41041 / 41040 |
| `nav.marker_prev` / `nav.marker_next` | ´ / ç (`Apostrophe` / `Slash`, medidas con la sonda en este teclado) | 40172 / 40173 |
| `time.go_start` | W | 40042 |
| `time.go_end` | Fin | 40043 |
| `time.clear_selection` | Esc | 40020 (quita selección de tiempo y loop) |
| `host.focus` | F4 | acción Lua `host_focus` (ver §6) |
| `host.close` | F5 | acción Lua `close_helper` |

Por tab (sección `tab` y `register_keys`):

| id | Tab | Tecla | Acción |
|---|---|---|---|
| `lyrics.tap` | Lyrics | B (hold) | tap-to-sync (`LyricsSync`) |
| `lyrics.undo` | Lyrics | Ctrl+Z | 40029 |
| `lyrics.redo` | Lyrics | Ctrl+Shift+Z | 40030 |
| `lyrics.escape` | Lyrics | Esc (override) | deselecciona la fila; sin fila seleccionada cae a `time.clear_selection` |

Undo y redo de REAPER solo en Lyrics: sus ediciones son puntos de undo del
proyecto (`Undo_BeginBlock`) y la cola de tap ya se reconcilia si una línea
desaparece (`reconcile`). Las ediciones de Armonía, Cues, Roles y Tonalidad
viven en `H` y no pasan por el undo de REAPER: un Ctrl+Z global ahí
desharía una acción cualquiera del proyecto.

### 4.5 Cómo agregar un atajo

Una línea en `global` (o en `tab.<Tab>`) con `cmd`. Si lleva lógica propia:
`action` con la función registrada en `Keys.init` (global) o `fn` pasada a
`Keys.add_tab` (tab; el módulo de la tab expone `register_keys(Keys)` y el
shell lo llama una vez después de `Keys.init`).

### 4.6 Input con perfil

`Keys.input(ctx, label, valor, perfil)` dibuja un `InputText` y aplica el
perfil de teclas del widget (§9.4). Devuelve `changed, valor, commit`. Campos
del perfil, todos opcionales:

| Campo | Valores | Efecto |
|---|---|---|
| `on_enter` | `'commit'` (defecto) \| `'none'` | `commit` devuelve true si Enter (sin repeat) cierra una edición |
| `keep_focus` | `false` (defecto) \| `'when_empty'` \| `'always'` | Devuelve el foco al input tras Enter: con el buffer vacío, o siempre |

Llama a `Keys.consume('Enter')` cuando Enter termina la edición. Lo usa la
tab Roles. Enter y Esc cierran el campo (los resuelve ImGui) y no se
refocusea salvo con `keep_focus`; `on_escape` no hizo falta. Tab y las
flechas no son campos de este perfil: los resuelve el anillo de foco (§4.7).

### 4.7 Anillo de foco

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
  con los guards de §3).
- Perfil `{ on_up, on_down }`, con `fn(owner, col, shift)`, sin modificadores o
  con Shift. Sin perfil las flechas no hacen nada: ↑/↓ no tienen atajo
  global.
- `ring_focus` va antes del widget y con offset 0: con `-1` después de un
  `InputInt` el foco no llegaba al campo (causa probable, inferida: el
  último item es un botón del stepper). El `-1` posterior sirve
  para `InputText` (§4.6).
- Un `InputInt` activo ignora el valor que se le pasa desde afuera. Para
  cambiarlo desde un perfil se cambia el ID del widget (`row._ver_<campo>`,
  campo interno como `_uid`, no se publica) y se pide el foco con `hold`.
  `ring_holds` hace que `drawPositionInputs` siga devolviendo la fila como
  activa: no se reordena ni cambia de grupo hasta salir del trío de posición.
- `ring_item` va después de la asignación `row.<campo> = valor del widget`: si
  va antes, el cambio del perfil se pisa con el valor viejo.

Armonía:

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

## 5. Modales

`ImGuiConfirmModal_common_logic.lua`: `Modal.begin(ctx, id, p, keys)` devuelve
`visible, cancel, confirm, stale`.

- `p` es el **pendiente** del modal (datos congelados, nunca el estado vivo:
  `08_REAIMGUI_PATTERNS.md` §6). El helper maneja dos campos de `p`: `p.open`
  (true = abrir una sola vez, se apaga solo) y `p.armed` (false en el primer
  frame visible: Esc y Enter se ignoran, para que la tecla que abrió el modal
  no lo cierre).
- `cancel` y `confirm` salen del lector `keys` (por defecto Esc y
  Enter/KeypadEnter; el Helper pasa `Keys.modal`, que lee la sección `modal`
  de la config). Sin repetición.
- `stale`: el popup se cerró por otra vía y el pendiente sigue: el llamador lo
  descarta.
- El cuerpo, los botones y qué hace cada uno quedan en quien lo usa; el
  llamador cierra con `CloseCurrentPopup` y termina con `EndPopup` solo si
  `visible`.

Lo usan el modal de alta de la tab Lyrics y el de colisión de pegado de
Armonía. En este último **Enter sobrescribe** y Esc cancela (decisión del
usuario: es lo que pidió al pegar); la acción se marca en los botones
(`Sobrescribir [Enter]`, `Cancelar [Esc]`) y vale la regla del primer frame
sin teclas. Un botón activado en el mismo frame (flechas + Enter) manda sobre
la tecla, y con Esc y Enter juntos gana cancelar. Un cambio de proyecto
descarta el pendiente. Con un popup abierto ningún atajo global ni hold actúa
(guards de la §3).

## 6. Foco del teclado entre el Helper y REAPER

Con el foco en la ventana ImGui, REAPER no recibe las teclas. Por eso W, Fin y
Esc se **replican** con `Main_OnCommand` y por eso hace falta una tecla para
pasar el foco sin mouse.

- **F4 en el Helper** → foco a REAPER (acción `host_focus`):
  `BR_Win32_SetFocus(BR_Win32_GetMainHwnd())` (SWS), con `JS_Window_SetFocus`
  de respaldo.
- **F4 en REAPER** → el one-shot `Nik_MusicState_FocusHelper.lua` (asignado a
  F4 en la sección Main del Action List, a mano en cada PC) busca la ventana
  por su título exacto (`MusicState Helper`, el de `ImGui_Begin`) y le da el
  foco con `BR_Win32_FindWindowEx` + `BR_Win32_SetFocus` (o `JS_Window_Find`).
  No enfoca ningún input: queda en la ventana.
- **Anti-rebote.** Si la tecla sigue apretada tras el cambio, Windows manda
  repeticiones a la ventana que acaba de recibir el foco y ImGui las lee como
  un press nuevo: rebota. Cada lado arma una ventana de 0,8 s al cambiar el
  foco (`HostFocus.arm`) y el otro la consulta al recibir la tecla
  (`HostFocus.blocked`), deslizándola 0,15 s por cada press ignorado. Se
  comparte por ExtState no persistente. Un clic con el mouse no arma nada.
- **F5** abre el Helper desde REAPER (el propio script en el Action List) y lo
  cierra desde adentro (`close_helper` corta el `defer` con una bandera).
  Ignorada los primeros 0,8 s de vida del script, por el mismo motivo del
  rebote. No usa el ID `_RS…` del script: es específico de la PC y llamarlo
  desde adentro le pediría a REAPER terminar el script a mitad de frame. Lo
  que cierra la ventana al apretar F5 en REAPER es REAPER terminando la
  instancia en ejecución (inferido: el Helper no tiene lógica de toggle).
  Lo que no se haya publicado (`H`) se pierde, igual que con la X de la
  ventana.

Dependencias: SWS (ya declarada del proyecto); `js_ReaScriptAPI` solo como
respaldo. Sin ninguna de las dos, el módulo avisa una sola vez por consola.

## 7. Hallazgos del probe (Paso 1)

Medidos con las mismas condiciones del Helper (`CreateContext(…, 0)` y
`WindowFlags_NoNav` en la raíz):

- `IsKeyPressed(Tab)` se lee con y sin un input activo. `NoNav` solo bloquea
  la navegación de ImGui, no la lectura de la tecla.
- `SetKeyboardFocusHere` mueve el foco entre inputs de un `BeginChild` con
  scroll: es la base del anillo de foco propio (§9, Paso 6).
- **`ImGui_SetNextWindowFocus` no sirve para llevar el teclado a la ventana
  desde REAPER:** `IsWindowFocused` da `true` y se ve en la barra, pero el
  teclado no le llega hasta hacer clic. Las vías por título (SWS y JS) sí.
- Combo nativo con el popup abierto: el contador de popups sube al apretar Esc
  mientras se mantiene el clic sobre un ítem. `ImGui_Combo` no permite saber
  qué ítem está resaltado ni interceptar teclas dentro del popup (§9, Paso 5).
- **El combo nativo se cierra en `NewFrame`.** Con Esc (o Enter sobre un ítem)
  el popup ya está cerrado cuando corre `begin_frame`: medido, Esc con el combo
  abierto llegaba con `popup_start=false`. Se resolvió con `popup_prev` (§3).

El probe vive en `Tests-Debug/Nik_Test_KeysFocusProbe.lua` y
`Nik_Test_KeysFocusRequest.lua`.

## 8. Cómo testear

Regresión del módulo, todo debe pasar:

1. Arranque sin errores en la consola de REAPER.
2. Space, Enter, ´/ç (marker anterior y siguiente) y ←/→ (con repetición)
   como siempre. W va al inicio, Fin al final, Esc limpia la selección de
   tiempo.
3. Con un input de Armonía en edición, W escribe una "w" y no mueve el cursor;
   Fin y Esc tampoco actúan.
4. Repetición: soltar, cambiar de tab o abrir un modal con la tecla apretada
   la corta; cerrar el modal con la tecla todavía apretada no dispara de
   golpe.
5. Lyrics: el tap con `B` mantiene su latencia (con la compensación ya
   calibrada); con un campo en edición, con el modal abierto o con el header
   "Sincronizar" colapsado no tapea; en Armonía `B` no hace nada.
6. Modal de alta de Lyrics: Enter y Esc cancelan o confirman según el modal y
   **no** reproducen ni limpian la selección de tiempo; el Enter que abre el
   modal desde el campo no lo cierra; un cambio de proyecto con modal pendiente
   lo descarta.
7. F4 en ambos sentidos, incluso con un modal abierto, y mantenida 2 s: sin
   rebote. Con el Helper cerrado, F4 en REAPER no hace nada.
8. F5: cierra el Helper con la ventana enfocada y sin campo ni modal activos;
   mantenida al abrir no lo cierra.
9. Ctrl+Z y Ctrl+Shift+Z en Lyrics deshacen y rehacen; en Armonía no hacen
   nada.
10. Colisión (prueba temporal): una tecla de tab igual a una global avisa por
    consola; con `override = true` la tab gana y la global sigue en las demás.
11. `cmd = '_SWS_NOEXISTE'` avisa que no existe; un `_RS…` avisa pero carga.
12. Modal de pegado de Armonía (colisión): Enter sobrescribe y pega, Esc
    cancela, ninguno reproduce ni limpia la selección de tiempo; con el foco
    en Cancelar (flechas) Enter cancela; un cambio de proyecto con el modal
    abierto lo cierra sin pegar; sin colisión pega directo.
13. Anillo de foco (Armonía): Tab y Shift+Tab recorren Compás, Beat, Cent. y
    Acorde fila por fila, y mantenidos repiten; sin foco, Tab entra al primer
    item y Shift+Tab al último; ↑/↓ en Acorde pasan de fila y con Shift saltan
    a la sección abierta vecina; ↑/↓ en Compás, Beat y Cent. cambian el valor
    con los pasos de §4.7 y el clamp; ↑ hasta cruzar de sección mantiene el
    foco y reordena recién al salir del trío; en las demás tabs no hacen
    nada.

## 9. Pasos del refactor: hechos y pendientes

### 9.1 Paso 4b-2 — Hecho

El modal de pegado de Armonía usa `Modal.begin` (ver §5) y
`InputCommit.globalKeyPressed` se eliminó. Cues consumirá el mismo helper.

### 9.2 Paso 4c — Hecho

Esc por tab en Lyrics (`lyrics.escape`, primer caso de `override` con
fallback, ver §4.3). Primer Esc con una fila seleccionada (`S.sel`): lo mismo
que volver a clickearla (deselecciona y, con "Seleccionar duración al hacer
click" activo, limpia el rango de tiempo), **sin mover el cursor de edición**.
Segundo Esc, sin fila seleccionada: la `fn` devuelve `false` y cae a la global
(40020). El mecanismo sirve para cualquier tab que quiera refinar un atajo
global sin reimplementarlo.

### 9.3 Paso 5 — Combo con teclado (Tonalidad): hecho, con bugs conocidos

Reemplazar `ImGui_Combo` por `BeginCombo` + `Selectable`, con la lista propia
para saber el ítem resaltado: letras A–G saltan al ítem (repetir la letra
cicla entre A, A#, Ab…), ↑/↓ mueven el resaltado, Enter confirma, Esc cierra
sin seleccionar. Wrapper genérico en `_Shared/`, reutilizable por otros
dropdowns. Con el popup abierto los atajos globales no actúan, ni siquiera en
el frame en que el popup se cierra solo (`popup_prev`, §3).

**Hecho:** `_Shared/ImGuiKeyCombo_common_logic.lua`, usado por Tonalidad
(tónica y modo). ImGui sigue siendo dueño de flechas, Enter y Esc (el popup no
hereda el `NoNav` de la raíz). El módulo suma las letras con ciclo
(`SetKeyboardFocusHere` mueve el foco real; la letra inicial sale de los
ítems) y, como el foco por teclado no se dibuja ni activa con Enter tras una
letra, dibuja el resaltado propio y confirma con Enter solo si el último
gesto fue una letra. Un click selecciona; Enter no actúa sobre el hover.

**Bugs conocidos, sin corregir (todos en `updateMouseGesture`):**

- Cualquier delta del mouse, incluso fuera del popup o un temblor, apaga el
  recuadro de foco que acaba de prender una flecha.
- Mouse y después ↑/↓: el recuadro parpadea (la flecha lo prende y el delta
  residual del frame siguiente lo apaga).
- Probados sin éxito: umbral de distancia a un ancla (re-anclando en cada
  flecha o letra) y filtro con `IsWindowHovered`. Pendiente: otra señal para
  "el mouse tomó el control".

### 9.4 Paso 6 — Anillo de foco y perfil de teclas por componente

**Estado:** 6a (caso Roles), 6b (wrapper `Keys.input`, §4.6) y 6c (anillo de
foco con Tab, repetición y flechas por perfil, §4.7) hechos. `on_escape` no
hizo falta: ImGui cierra el campo con Esc y el guard de item activo evita que
Esc llegue a `time.clear_selection`. Pendiente el 6d (widgets que no son de
texto, §9.5).

**Anillo de foco.** Hoy Tab no hace nada entre inputs (§7: la lectura anda, la
navegación de ImGui está apagada por diseño). Propuesta:

- Cada input se registra al dibujarse con `(id, fila, columna)` opcionales.
  Tab y Shift+Tab recorren el orden de la tab activa (orden propio por tab,
  no el de dibujado); ↑/↓ pasan a la misma columna de la fila de arriba o de
  abajo (ej. Armonía: desde el input de acorde a la fila superior o inferior).
- El foco se aplica el frame siguiente con `SetKeyboardFocusHere` antes de
  dibujar el widget destino. Para widgets que no son texto (combo, botón,
  checkbox) el foco es propio: recuadro dibujado por nosotros y Space o Enter
  los accionan.
- **El destino se identifica por la tabla de la fila, no por el índice.**
  Armonía reordena al soltar el foco (`resortAndFocusRow`): mover el foco de la
  fila A a la B dispara el reorden justo en ese momento.
- Los grupos colapsados no se dibujan, así que el anillo los salta solo.
- `RowInputs` debería registrar sus tres campos sin que el llamador lo repita.

**Perfil de teclas por componente.** Un comportamiento que es del widget, no de
la ventana, se declara en la tab como una tabla de configuración y lo
interpreta un wrapper (`Keys.input(ctx, id, label, valor, perfil)` que
devuelve cambio, valor y commit). Campos previstos:

```lua
{ on_enter = 'commit',          -- 'commit' | 'none'
  keep_focus = 'when_empty',    -- false | 'when_empty' | 'always'
  on_escape = 'revert',         -- 'revert' | 'blur'
  on_tab = 'next',              -- 'next' | 'none' (anillo de foco)
  on_up = fn, on_down = fn }    -- ej. Armonía: ir a la fila de arriba o abajo
```

**Qué quedó distinto de esta propuesta (6c):** el anillo se declara por tab
con `ring_focus` / `ring_item` y la tab puede traer su orden (`ring_config`).
`on_tab` no es un campo del perfil: Tab recorre el anillo por defecto. El
perfil de un input es `{ on_up, on_down }` (pasado a `ring_item`) y se
declara por input, así cada tab decide qué hacen las flechas (en Armonía:
mover de fila en Acorde, cambiar el valor en Compás, Beat y Cent.). El foco
se aplica con `SetKeyboardFocusHere(ctx, 0)` antes del widget, no con `-1`
después (ver §4.7).

**Caso Roles (hecho, 6a y 6b):** Roles usa `Keys.input` con
`{ on_enter = 'commit', keep_focus = 'always' }`: Enter con el input vacío
deja el cursor ahí, y con texto agrega el rol y también lo deja (para cargar
varios seguidos). Mecánica: `SetKeyboardFocusHere(ctx, -1)` justo después de
dibujar el InputText (el `-1` apunta al widget anterior). Con Enter mantenido
el sistema repite la tecla y ImGui desactiva el input en cada repetición: el
refoco lee Enter **con repeat** y el commit **sin repeat**, así no se
duplican roles. `Keys.consume('Enter')` quedó dentro del wrapper (§4.6).

Reprobado en el 6a y 6b: Enter en Roles (tocado y mantenido) no dispara
Play/Pause (`musicstate_helper.md` §7).

### 9.5 Otros pendientes

- **Anillo de foco, pendientes del 6c:** 6d (checkbox y botones de Armonía con
  recuadro propio, accionados con Space o Enter); entrar al anillo por la fila
  del cursor y no por la primera; Cues sobre el mismo anillo cuando se rehaga
  sobre Lyrics.
- **Teclas ´ y ç:** el nombre de tecla de ReaImGui depende del layout del
  teclado (`Apostrophe` y `Slash` valen para este). En otra PC de sala,
  verificar con `Tests-Debug/Nik_Test_KeyProbe.lua` antes de desplegar.
  ↑/↓ quedaron libres, a disposición de un perfil de flechas entre líneas
  de Lyrics.
- **Repetición:** afinar `delay` y `rate` de ←/→ a mano (los valores por
  defecto parecieron rápidos a primera vista).
- **Teclas a `Cues`:** Cues se rehace sobre Lyrics y consumirá el helper de
  modal, los holds y el anillo de foco (registro de abstracción abajo).
- **Despliegue:** `MusicStateKeys_config.lua` se pisa en cada update de
  ReaPack (mismo caso que `MonitorMix_config.lua`, ver `05_REAPACK_DEPLOY.md`).
  El `@provides` del Helper suma los dos módulos de `_Shared/`, los dos de
  teclas y `[main] Nik_MusicState_FocusHelper.lua`. Las teclas de F4 y F5 en
  el Action List se asignan a mano en cada PC.
- **Posible extensión, no hecha:** leer el keymap de REAPER para no repetir
  los atajos en la config. No es un objetivo: el despacho replica las teclas
  que el Helper decide.

### 9.6 Registro de abstracción Lyrics → Cues

| Pieza | Estado |
|---|---|
| Despacho central, repetición, validación de colisiones | Hecho, sin dependencia de Lyrics |
| Helper de modal | Hecho; Lyrics y Armonía lo usan, Cues después |
| Cache con recarga por `GetProjectStateChangeCount` / cambio de proyecto | Candidato (cambia la fuente de datos) |
| Lista con fila vigente (play vs. edit cursor), highlight y auto-scroll | Candidato; Cues probablemente cambie la regla de seguimiento |
| Selección por clave `{time}` en vez de índice | Candidato, patrón general |
| Click → mueve el cursor y la selección de tiempo (toggle) | Candidato |
| Cola de tap (`held`, flancos, compensación) | Parcial: el gesto y la compensación sí, el fin por hold quizá no. `Keys.held` ya permite una tecla propia por tab |
| Panel de edición (nudge, al cursor, borrar, agregar con confirmación) | Parcial: la UI sí, la persistencia no |
| Filtro por rol (dropdown) | Nuevo en Cues, no existe en Lyrics |
| Datos | Lyrics lee del proyecto (cache); Armonía y Cues mutan `H` y se publican con "Guardar y Publicar": la abstracción necesita un adaptador de almacenamiento (`insert`, `delete`, `move`, `find_near`, `list`) |
| `drawPositionInputs` en Cues | Sin `get_max_beats` todavía |
