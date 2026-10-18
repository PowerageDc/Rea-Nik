# Feature — MusicState: atajos de teclado del Helper (ReaImGui)

Despacho central de teclas del Helper (`Nik_MusicState_Helper.lua`): atajos
globales que se reenvían a REAPER, bindings por tab, repetición por hold,
teclas de los modales y paso del foco del teclado entre el Helper y REAPER.
Es solo del panel nativo ReaImGui; el prompter web tiene su propio manejo
(`musicstate_instrumentista.md` y `musicstate_cantante.md`).

Fuera de este doc: input con perfil de teclas, anillo de foco (Tab y
flechas) y combo con teclado: `musicstate_keys_inputs.md`. Patrones
genéricos de ReaImGui: `08_REAIMGUI_PATTERNS.md`.

## 1. Archivos

| Archivo | Rol |
|---|---|
| `MusicState/MusicStateKeys_common_logic.lua` | Despacho: bindings, guards, repetición, colisiones, `Keys.held`, `Keys.modal`, `Keys.consume`. También aloja `Keys.input` y `Keys.ring_*` (`musicstate_keys_inputs.md`) |
| `MusicState/MusicStateKeys_config.lua` | Bindings globales y por tab, en datos puros (convención de `<Dominio>_config.lua`, ver `01_CONVENCIONES.md`) |
| `_Shared/ImGuiHostFocus_common_logic.lua` | Foco del teclado ventana ReaImGui ↔ REAPER y anti-rebote por auto-repeat |
| `_Shared/ImGuiConfirmModal_common_logic.lua` | Ciclo de vida común de un modal de confirmación |
| `MusicState/Nik_MusicState_FocusHelper.lua` | One-shot para REAPER: lleva el foco al Helper |
| `Nik_MusicState_Helper.lua` | Carga los módulos, registra las acciones Lua (`host_focus`, `close_helper`) y llama al ciclo de frame |
| `MusicState/MusicStateLyricsSync_common_logic.lua` | `register_keys`: la tecla de tap `B` como hold de la tab Lyrics |
| `Tests-Debug/Nik_Test_KeysFocusProbe.lua`, `Nik_Test_KeysFocusRequest.lua`, `Nik_Test_KeyProbe.lua` | Sondas de foco del teclado y de nombres de tecla (§7, §9) |

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
`AnyPopupId`, sumado a `popup_prev`, §3).

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
`IsAnyItemActive`, el atajo global dispararía igual. Con el popup pasa lo
mismo: `CloseCurrentPopup` lo cierra en el mismo frame, así que el Enter que
confirma un modal (o el Esc que lo cancela) llegaría al `dispatch` con
`IsPopupOpen` en `false` y reproduciría o limpiaría la selección de tiempo.

**Popups que ImGui cierra solo.** Un combo nativo se cierra con Esc o Enter
dentro de `NewFrame`, antes de `begin_frame`: la foto del inicio ya lo ve
cerrado. `dispatch` guarda el estado **vivo** de los popups al final del
frame (`popup_prev`) y `begin_frame` lo suma a `popup_start`: un popup
abierto al terminar el frame anterior cuenta como abierto en este. Se
guarda el estado vivo y no `popup`, que ya incluye la foto del inicio y
nunca se apagaría. Costo: tras cerrarse un popup los atajos quedan
cerrados un frame más.

`ignore_item_active` e `ignore_popup` relajan estos guards por binding (F4
los usa los dos: una tecla de función no se tipea).

`Keys.consume('Enter')` queda para los widgets que usan una tecla puntual;
`Keys.input` (`musicstate_keys_inputs.md` §2) lo llama solo cuando Enter
termina una edición.

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
  `rate = 0.15`.
- **`hold`:** no se despacha. Se consulta con `Keys.held(ctx, id)`, que se
  evalúa **en el momento de la llamada** (durante el draw de la tab), no en el
  `dispatch` del final del frame: el tap de Lyrics no puede perder un frame de
  latencia (la compensación calibrada quedaría descalibrada). Los flancos
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
cambia entre PCs (`00_CONTEXTO_GENERAL.md`, Command ID) y el config se
despliega por ReaPack.

### 4.4 Bindings actuales

Globales (`MusicStateKeys_config.lua`, sección `global`):

| id | Tecla | Acción |
|---|---|---|
| `transport.playstop` | Space | 40044 |
| `transport.playpause` | Enter | 40073 |
| `nav.measure_prev` / `nav.measure_next` | ← / → (repiten) | 41041 / 41040 |
| `nav.marker_prev` / `nav.marker_next` | ´ / ç (`Apostrophe` / `Slash`, nombres medidos con la sonda en este teclado) | 40172 / 40173 |
| `time.go_start` | W | 40042 |
| `time.go_end` | Fin | 40043 |
| `time.clear_selection` | Esc | 40020 (quita selección de tiempo y loop) |
| `host.focus` | F4 | acción Lua `host_focus` (§6) |
| `host.close` | F5 | acción Lua `close_helper` (§6) |

↑/↓ no tienen atajo global: quedan libres para el perfil de flechas de cada
input (`musicstate_keys_inputs.md` §3).

Por tab (sección `tab` y `register_keys`):

| id | Tab | Tecla | Acción |
|---|---|---|---|
| `lyrics.tap` | Lyrics | B (hold) | tap-to-sync (`LyricsSync`) |
| `lyrics.undo` | Lyrics | Ctrl+Z | 40029 |
| `lyrics.redo` | Lyrics | Ctrl+Shift+Z | 40030 |
| `lyrics.escape` | Lyrics | Esc (override) | deselecciona la fila; sin fila seleccionada cae a `time.clear_selection` |

`lyrics.escape` con una fila seleccionada (`S.sel`) hace lo mismo que volver
a clickearla: deselecciona y, con "Seleccionar duración al hacer click"
activo, limpia el rango de tiempo, **sin mover el cursor de edición**. Sin
fila seleccionada la `fn` devuelve `false` y cae a la global (40020). El
mecanismo sirve para cualquier tab que quiera refinar un atajo global sin
reimplementarlo.

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
Armonía. En el de pegado **Enter sobrescribe** y Esc cancela; la acción se
marca en los botones (`Sobrescribir [Enter]`, `Cancelar [Esc]`) y vale la
regla del primer frame sin teclas. Un botón activado en el mismo frame
(flechas + Enter) manda sobre la tecla, y con Esc y Enter juntos gana
cancelar. Un cambio de proyecto descarta el pendiente. Con un popup abierto
ningún atajo global ni hold actúa (guards de §3).

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
  que no se haya publicado (`H`) se pierde, igual que con la X de la ventana.

Dependencias: SWS; `js_ReaScriptAPI` solo como respaldo. Sin ninguna de las
dos, el módulo avisa una sola vez por consola.

## 7. Sondas y hallazgos

Con el contexto creado con `config_flags=0` y `WindowFlags_NoNav` en la
raíz (las condiciones del Helper):

- `IsKeyPressed(Tab)` se lee con y sin un input activo: `NoNav` solo bloquea
  la navegación de ImGui, no la lectura de la tecla.
- **`ImGui_SetNextWindowFocus` no sirve para llevar el teclado a la ventana
  desde REAPER:** `IsWindowFocused` da `true` y se ve en la barra, pero el
  teclado no le llega hasta hacer clic. Las vías por título (SWS y JS) sí.

Sondas: `Tests-Debug/Nik_Test_KeysFocusProbe.lua` y
`Nik_Test_KeysFocusRequest.lua` (foco), `Nik_Test_KeyProbe.lua` (nombres de
tecla según el layout del teclado).

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

Pruebas del anillo de foco y del combo: `musicstate_keys_inputs.md` §8.

## 9. Pendientes

- **Teclas ´ y ç:** el nombre de tecla de ReaImGui depende del layout del
  teclado (`Apostrophe` y `Slash` valen para el de dev). En otra PC de sala,
  verificar con `Tests-Debug/Nik_Test_KeyProbe.lua` antes de desplegar.
- **Repetición:** afinar `delay` y `rate` de ←/→ a mano en la config (los
  valores por defecto parecen rápidos).
- **Despliegue:** `MusicStateKeys_config.lua` se pisa en cada update de
  ReaPack y las teclas de F4 y F5 se asignan a mano en cada PC:
  `05_REAPACK_DEPLOY.md`, Pendientes.
- Pendientes del input con perfil, el anillo de foco y el combo:
  `musicstate_keys_inputs.md` §9.
