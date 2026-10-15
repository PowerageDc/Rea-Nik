# Feature — MusicState: ingreso de letras y tab Lyrics del Helper

Cómo se cargan las líneas de letra en el track `🎤 Lyrics`: script de
ingreso y tab Lyrics del Helper (ReaImGui). Decisiones, API del módulo,
gotchas y comportamiento por paso. Estado de la feature, publicador y
pendientes generales: `musicstate_lyrics.md`; contrato de datos:
`musicstate_data_model.md` §4.7; UI de cantante: `musicstate_cantante.md`.
Helper: `musicstate_helper.md`; atajos: `musicstate_keys.md`; patrones de
ReaImGui: `08_REAIMGUI_PATTERNS.md`.

## 1. Estado

| Pieza | Estado |
|---|---|
| Módulo `MusicStateLyrics_common_logic.lua` + `Nik_MusicState_LyricsInput.lua` (línea en cursor o selección con `GetUserInputs`, marcador `·` de fin, upsert, aviso ante eventos dentro de la selección) | Implementado |
| Tab Lyrics del Helper: lectura (§6) | Implementado |
| Cola de tap-to-sync (§7) | Implementado |
| Edición de la fila seleccionada y alta de líneas (§8) | Implementado; sin probar: el alta con un fin pendiente de la cola (`musicstate_lyrics.md` §6) |
| Publicar desde la tab (`Lyrics.Publish`, botón y auto-publicar) | Pendiente (§9) |

## 2. Decisiones

- **Ingreso por API, no por el diálogo del editor MIDI.**
  `MIDI_InsertTextSysexEvt` (tipo 5) inserta el lyric directo en el take,
  sin editor abierto. La posición se convierte con
  `MIDI_GetPPQPosFromProjTime`: sigue al mapa de tempo y no se cuantiza.
  Un único item MIDI en el track cubre la posición: se crea (desde el
  inicio del proyecto) o se extiende (`MIDI_SetItemExtents`). Descartado
  el diálogo nativo de texto del editor MIDI: exige el editor abierto con
  su propio cursor, distinto del de arrange.
- **Edición idempotente (upsert).** El texto en el punto de inicio
  reemplaza al evento existente (el campo se precarga con él). Texto vacío
  = solo marcador de fin `·`. El `·` no se duplica ni se inserta si en esa
  posición ya hay un `·` o una línea real. Con eventos dentro de la
  selección de tiempo, aviso Sí (reemplazar) / No (conservar) / Cancelar.
  Todo en un solo bloque de undo.
- **Lógica sin UI en el módulo.** `PlanLine` lee el estado y `ApplyLine`
  lo aplica; ninguna abre diálogos, así que las usan por igual el script
  de ingreso (diálogos nativos) y la tab del Helper.
- **La tab no usa `H` para la letra.** La fuente de verdad son los eventos
  MIDI y cada edición se aplica directo, con su undo. La tab mantiene solo
  un cache de lectura (`H._lyrics`), recargado cuando cambia
  `GetProjectStateChangeCount` o el proyecto activo.
- **Publicación desde la tab vía `Lyrics.Publish(proj)`**, a extraer al
  módulo; `PublishLyrics` queda como cáscara fina y sigue siendo el punto
  de entrada del cliente web (§9). Decidido, no implementado.
- **La posición no se edita con `RowInputs` ni con las conversiones del
  Helper** (descartado): el redondeo a la grilla de 0.25 destruye el
  `qn_offset` libre, y editar la posición en vivo trae los bugs de reorden
  y foco de `musicstate_helper.md` §5. La posición se ajusta con nudge,
  "mover al cursor" y tap.
- **El fin de línea sale del gesto, no del texto** (descartado: línea en
  blanco pegada = `·`). La letra copiada de internet casi nunca trae
  líneas en blanco entre frases y cerrar casi cada línea es el caso
  común; el fin sale de mantener la tecla (§7) y las líneas en blanco se
  ignoran.

## 3. Archivos

- `MusicState/Nik_MusicState_LyricsInput.lua` — ingreso de líneas (UI
  mínima sobre el módulo).
- `MusicState/MusicStateLyrics_common_logic.lua` — descubrimiento del
  track y lógica de edición, sin diálogos ni ImGui (§4).
- `MusicState/MusicStateLyricsTab_common_logic.lua` — tab Lyrics del
  Helper (`M.draw(ctx, H, helpers)`).
- `MusicState/MusicStateLyricsSync_common_logic.lua` — cola de tap-to-sync
  (`M.draw(ctx, S, H, helpers)`), vía `helpers.LyricsSync`. Expone también
  `flush` y `onEdit`, el contrato con las ediciones del panel (§8).
- `MusicState/MusicStateLyricsEdit_common_logic.lua` — panel de edición de
  la fila seleccionada y alta de líneas (`M.draw(ctx, S, H, helpers)`;
  `M.drawAddOnly` dibuja solo la fila de alta cuando no hay track), vía
  `helpers.LyricsEdit`.
- `Tests-Debug/Nik_Test_LyricsEditProbe.lua` — probe de la API MIDI para
  la edición (texto en el lugar, PPQ fuera del item, `SetItemExtents`,
  casos de `EnsureTake`). Crea pistas `PROBE_*` en un solo bloque de undo.
- `Tests-Debug/Nik_Test_LyricsDecideAdd.lua` — test de consola de
  `DecideAdd` con eventos simulados (no toca el proyecto).

Los módulos y la tab están en el `@provides` del Helper.

## 4. API del módulo

Constantes: `END_MARK` (`·`), `DEFAULT_TRACK_NAME` (`🎤 Lyrics`),
`EPS_TIME` (0.01 s, tolerancia para "misma posición"), `PAD_TIME` (5 s,
margen al crear o extender el item), `MIN_SEP` (2 × `EPS_TIME`,
separación mínima entre eventos vecinos al mover).

- `FindLyricsTrack(proj)`, `CreateLyricsTrack()`.
- `CollectEvents(track)`: eventos lyric (tipo 5) de todos los items,
  ordenados por tiempo, con `take`, `idx`, `text` y `time`.
- `EventsNear(list, t)`, `EventsBetween(list, t1, t2)`: ambos con epsilon;
  `EventsBetween` es estricto en los dos bordes.
- `DeleteEvents(list)`: borra por take en índice descendente, en un solo
  lote (los índices se desfasan si se borra de a uno).
- `EnsureTake(track, t_from, t_to)`, `InsertAt(...)`, `CleanText(s)`,
  `GetTimeContext()` (selección de tiempo si mide más de 2×`EPS_TIME`; si
  no, el edit cursor y `nil`). `EnsureTake`: sin item previo al destino y
  con items MIDI existentes, extiende el inicio del primero hasta 0 en vez
  de crear uno solapado; la extensión hacia adelante no pasa del inicio
  del item siguiente (afecta también a los taps).
- `PlanLine(track, t1, t2)`: contexto con `prefill`, `at_start`, `at_end`,
  `inside` y `end_time`. No modifica nada.
- `ApplyLine(track, ctx, text, opts)`: con `track = nil` lo crea.
  `opts.replace_inside` decide si se borran los eventos dentro de la
  selección; si hay eventos dentro y no se reemplazan, no se inserta el
  `·` de `t2` (el par es posicional: quedaría huérfano después del fin de
  la última línea conservada). Devuelve `false, "end_occupied"` si el
  texto es vacío y ya hay un evento en la posición del marcador; si no,
  `true, track`.
- `DecideAdd(ctx, text)`: decisión pura para el alta, a partir del `ctx`
  de `PlanLine` y el texto ya limpio. Devuelve `{kind = "apply" |
  "confirm_line" | "confirm_inside" | "reject"}` más `n` (eventos dentro
  de la selección), `has_line` (hay una línea en `t1`) y `replaces_end`
  (hay un `·` en `t1`, que `ApplyLine` reemplaza sin modal). En `reject`
  trae `code`: `"reserved"` (el texto es `·`) o `"end_occupied"`.
- `PairEvents(events)`: marca `is_end` y deriva el par línea/fin por
  posición (`end_idx` en la línea, `owner` en el fin). En un grupo de
  eventos a menos de `EPS_TIME` entre sí, los fines cierran la línea
  anterior y las líneas abren una nueva. No se guarda: se recalcula en
  cada lectura.
- `Resolve(list, key)`: índice del evento que coincide con la clave
  `{time, is_end}` (tolerancia `EPS_TIME`).
- Edición: `SetText`, `DeleteLine`, `DeleteEnd`, `MoveEvent`,
  `AddEnd`. Reciben una clave `{time, is_end}`, nunca `take`/`idx`
  (caducan con cualquier edición), y releen el track al ejecutarse.
  Devuelven `true, change` (descriptor para `LyricsSync.onEdit`) o
  `false, "<código>"`. Un bloque de undo por operación (§8).

## 5. Gotchas verificados

- `GetUserInputs` con un solo campo: `extrawidth=350,separator=\n` para
  que las comas de la letra no partan el valor.
- Los archivos que contienen `·`, `🎤` o `→` tienen que guardarse en
  UTF-8; si no, el `·` se inserta mal y el publicador no lo reconoce.
- Limpiar la selección de tiempo: `GetSet_LoopTimeRange(true, false, 0, 0,
  false)`.
- `reaper.ImGui_GetKeyName` no existe en la versión instalada (error de
  `nil`): la etiqueta de la tecla de tap es un texto fijo
  (`KEY_TAP_LABEL`) junto a `KEY_TAP`.
- Un botón que se deshabilita o se desplaza mientras se lo mantiene
  pierde el release o el click (`08_REAIMGUI_PATTERNS.md` §4).
- `MIDI_SetTextSysexEvt` exige `typeIn = 5` explícito: con `nil` devuelve
  `true` pero ignora el mensaje. Con el tipo explícito y el resto en `nil`
  cambia el texto sin tocar la posición.
- `MIDI_SetItemExtents` moviendo el inicio de un item conserva el tiempo
  de proyecto de los eventos (cambia el PPQ, no la posición).
- Un evento insertado antes del inicio del item o pasado su final se
  acepta con PPQ negativo o fuera de rango. No se usan: el destino de un
  movimiento siempre se resuelve con `EnsureTake`.
- `ev.take` y `ev.idx` caducan con cualquier edición (`MIDI_Sort`,
  borrados). Un `ctx` de `PlanLine` no debe sobrevivir a un frame ni a un
  modal: se vuelve a planear al confirmar.
- Lua: `a and b or c` cae en `c` cuando `b` es `nil` (bug real en
  `MoveEvent`, el tope del último par del track): usar `if/else`.

## 6. Tab: lectura

- Cache en `H._lyrics`: se relee solo cuando cambia
  `GetProjectStateChangeCount(0)` o `H.last_proj`. El botón "Recargar" es
  la salida de emergencia.
- Fila vigente: sigue la posición de reproducción mientras suena y el edit
  cursor cuando está detenido. Mismo highlight que Armonía (verde sólido
  si coincide exacto, tenue por carry-over) y auto-scroll cuando cambia la
  fila vigente. Separadores de sección: fila gris, no `CollapsingHeader`.
- Click en una línea: mueve el edit cursor (`SetEditCurPos(t, true,
  false)`, sin seek en reproducción) y, con el toggle activo, selecciona
  el tiempo hasta el evento siguiente (línea o `·`). En la última línea,
  o en un `·`, limpia la selección. Toggle persistido con `SetExtState`
  (sección `NikMusicStateHelper`, clave `lyrics_autoselect`).
- Registro en el contenedor del Helper: `dofile` del módulo y de la tab,
  `helpers.Lyrics` y un `BeginTabItem('Lyrics')`.

## 7. Tab: cola de tap-to-sync

- **Dónde vive.** `MusicStateLyricsSync_common_logic.lua`
  (`helpers.LyricsSync`). La tab dibuja su panel colapsable ("Sincronizar
  (tap)") **antes** del `return` de "sin track de Lyrics", porque el
  primer tap puede crear el track. Estado en `S.sync` (`S = H._lyrics`),
  solo en memoria: se descarta al cambiar de proyecto y no sobrevive al
  cierre del Helper.
- **Dos fases.** Preparar: `InputTextMultiline` para pegar; cada línea con
  contenido es un ítem, las líneas en blanco y los `·` sueltos se
  ignoran. Sincronizar: se muestra el siguiente ítem y los dos que
  siguen, con TAP, Saltar, Deshacer y Vaciar. Con la cola cargada no hay
  `InputText` activo, así que la tecla de tap no choca con ningún campo.
- **Tap.** Una sola señal `held`, alimentada por la tecla (`KEY_TAP`, hoy
  `B`) y por el botón TAP (`IsItemActive`). Los flancos salen de comparar
  con el frame anterior (`IsKeyDown`, no `IsKeyPressed`/`IsKeyReleased`,
  para unificar con el botón). La tecla exige ventana enfocada
  (`ChildWindows`) y ningún item activo; si la ventana pierde el foco,
  cuenta como soltada. Solo opera con reproducción activa. Inserta con
  `PlanLine`/`ApplyLine` en `GetPlayPosition()` (no `GetPlayPosition2`, que
  no descuenta la latencia de salida de audio) más la compensación.
- **Compensación.** Valor en ms para inicio y fin (default −150, rango
  −500..+200, `DragInt`), persistido al soltar el control en
  `NikMusicStateHelper` / `lyrics_tap_latency_ms`. Se calibra tapeando 3 o
  4 líneas con ataques claros contra el stem de Vocals. Independiente de
  `nikMusicStateLyricsLeadSec`, que solo afecta al mostrar.
- **Fin por hold.** Al soltar, si el hold duró al menos 250 ms
  (`MIN_HOLD_S`, fijo) y el toggle está activo (`lyrics_tap_close`), el
  `·` queda **pendiente**. Se resuelve por frame (también con el header
  colapsado): se inserta si pasa el gap mínimo (`lyrics_tap_gap_ms`,
  default 400 ms, en tiempo de proyecto, independiente del playrate), si
  se detiene la reproducción o si hay un seek hacia atrás; se descarta si
  llega un press dentro del gap (carry-over). "Vaciar cola" inserta el
  pendiente antes de vaciar; un cambio de proyecto lo descarta sin
  insertar.
- **Deshacer y reconciliación.** Cada entrada de `hist` es `{time, text,
  end_time}` o `{skip = true}`, con la invariante `pos == #hist + 1`.
  "Deshacer" borra por identidad (`EventsNear` sobre `time` y
  `end_time`), no con el undo de REAPER, y cancela el `·` si seguía
  pendiente. Si la cantidad de líneas del track baja (Ctrl+Z, borrado a
  mano), la cola retrocede hasta la última línea tapeada que todavía
  existe.
- **Layout estable.** El botón TAP no se deshabilita al completar la cola
  (pasa a "Cola completa"): deshabilitarlo con el botón apretado perdía el
  release de la última línea. La línea de aviso bajo el botón se reserva
  siempre: si aparece y desaparece, el layout se corre y se pierde el
  click de "Saltar" o "Deshacer".
- **Limitaciones conocidas.** (1) Redo (Ctrl+Shift+Z) devuelve la línea al
  track pero no a la cola, y volver a tapearla deja dos copias. (2) Borrar
  a mano la última línea y recuperarla con Ctrl+Z no refresca la cola: la
  reconciliación solo reacciona cuando la cantidad de líneas baja. (3)
  Los taps hacen upsert en su posición y no borran letra existente; para
  re-sincronizar desde cero se borra desde el panel de edición (§8) o a
  mano. (4) Un re-tap sobre una línea existente reemplaza el texto y
  "Deshacer" no lo restaura. (5) Ctrl+Z o Redo de REAPER sobre una edición
  del panel de edición: ver §8.

## 8. Tab: edición de la fila seleccionada y agregar línea

- **Dónde vive.** `MusicStateLyricsEdit_common_logic.lua`
  (`helpers.LyricsEdit`), dibujado por la tab entre el panel de sync y la
  lista. Alto fijo: sin selección queda deshabilitado, no oculto, y la
  línea de aviso se reserva siempre. Estado en `S.edit`.
- **Selección.** `S.sel = {time, is_end}`, identificada por tiempo y no
  por índice (refresh recarga todo): se resuelve en cada frame con
  `Resolve` y se limpia sola si deja de resolverse o cambia el proyecto.
  El click en una fila la selecciona, mueve el cursor y, con el toggle
  activo, aplica la selección de tiempo; un segundo click la deselecciona
  y limpia esa selección de tiempo. "Borrar línea" también la limpia
  (toggle activo). Tras mover un borde (nudge, al cursor, agregar fin,
  borrar solo el fin), la tab recalcula la selección de tiempo en el
  frame siguiente (`S.reselect`, `applyTimeRange`). "Ir al inicio" mueve
  el cursor sin tocar la selección.
- **Par línea/fin.** Derivado por posición en cada refresh
  (`PairEvents`), nunca guardado. La lista muestra la duración (`· X.XX
  s`) y marca los fines sin línea como "fin (sin linea)". Insertar una
  línea dentro del span de otra le corta el fin: el modelo es posicional,
  igual que el cliente.
- **Texto.** `InputText` con borrador atado a la clave del evento; commit
  al perder el foco (Enter, Tab o click afuera), Esc revierte; texto
  vacío o `·` rechazado con aviso. El commit usa la clave del borrador,
  no la selección actual. `SetText` edita en el lugar (§5). Los atajos
  globales del contenedor no chocan (`08_REAIMGUI_PATTERNS.md` §5).
- **Borrar.** "Borrar línea" borra la línea y su fin en un solo bloque de
  undo (un fin suelto pasaría a cerrar la línea anterior). "Borrar fin"
  (con un `·` seleccionado) y "Borrar solo el fin" (con la línea) dejan
  la línea en carry-over.
- **Posición.** Filas "Inicio" y "Fin": nudge de −100, −20, +20 y +100 ms
  y "Al cursor". El nudge se detiene en el tope; "Al cursor" rechaza si
  cae fuera de rango. Un evento nunca cruza ni pisa a un vecino
  (`MIN_SEP`): no hay reordenamiento ni colisiones por nudge. Mover el
  inicio deja el fin quieto; el check "El fin acompaña" (apagado por
  defecto, sin persistir) mueve el par conservando la duración. "Fin > Al
  cursor" en una línea sin fin lo crea (`AddEnd`). Mover = borrar +
  insertar por la ruta de los taps (`EnsureTake`), en un solo bloque de
  undo. Tras mover, la selección y el borrador siguen al evento y la
  lista hace scroll hasta la fila.
- **Agregar línea.** Fila "Agregar" al final del panel (campo y botón),
  siempre habilitada: no depende de la selección. Sin track de Lyrics la
  tab dibuja solo esa fila (`drawAddOnly`) y el alta crea el track.
  Agrega en el cursor o, con selección de tiempo, la línea en `t1` y el
  `·` en `t2`; con el campo vacío inserta solo el `·`. Enter en el campo
  agrega (también vacío); Tab o click afuera no. Orden:
  `LyricsSync.flush`, `GetTimeContext`, `PlanLine`, `DecideAdd` (el flush
  va antes: un `·` pendiente insertado después dejaría viejo el `ctx`).
  `apply` aplica directo, `reject` avisa, y `confirm_*` abre el modal. El
  modal de reemplazo es obligatorio porque, con "Seleccionar duración al
  hacer click" activo, clickear una línea deja una selección de tiempo
  igual a su rango y agregar sobre ella reemplazaría esa línea (upsert en
  `t1`).
- **Confirmación.** Se guarda en `Ed.add_pending` `(t1, t2, texto)` y una
  vista previa congelada de lo que se pisa (hasta 5 líneas con su
  posición, texto cortado a 50 caracteres, y la cantidad de `·` aparte);
  nunca el `ctx`. Al confirmar se vuelve a planear y, si `kind`, `n` o
  `has_line` cambiaron, se cancela con aviso. Un cambio de proyecto con el
  modal abierto lo descarta. Línea existente: Reemplazar / Cancelar.
  Eventos dentro de la selección: Reemplazar todo / Conservar / Cancelar
  (`opts.replace_inside`); si además hay una línea en `t1`, es el mismo
  modal de tres botones. Conservar no inserta el `·` de `t2` (§4). El
  título del modal es su ID: `'Agregar linea###lyrics_add_confirm'` evita
  que se vea el identificador.
- **Teclas del modal.** Esc cancela, leído por el helper de modal
  (`Modal.begin` con `Keys.modal`, `musicstate_keys.md` §5; el panel tiene
  `NoNav` y ImGui cierra los popups con Esc por la navegación). Enter
  ejecuta Reemplazar en el modal de un botón y Cancelar en el de tres (un
  Enter reflejo no borra varias líneas), evaluado después de los botones:
  si uno se activó con las flechas, manda ese. Ambas teclas se ignoran el
  primer frame y sin auto-repeat, para que el Enter que abre el modal
  desde el campo no lo confirme. Los atajos globales y la tecla de tap no
  actúan con un popup abierto (`08_REAIMGUI_PATTERNS.md` §6).
- **Después de agregar.** La selección pasa a la línea nueva (al `·` si el
  texto era vacío) y la lista hace scroll hasta ella; `S.state_count = -1`
  fuerza la recarga y, con el toggle activo, `S.reselect` hace que la
  selección de tiempo la siga. Una línea agregada no entra en `hist`, así
  que no hay `onEdit`. `applyTimeRange` llega hasta el fin del item de
  Lyrics cuando una línea no tiene evento siguiente (incluye el margen de
  `PAD_TIME` de `EnsureTake`); vale también para el click en la última
  línea.
- **Contrato con la cola de tap.** Cada operación llama a
  `LyricsSync.flush` antes (inserta el fin pendiente) y a
  `LyricsSync.onEdit(S.sync, Lyrics, change)` después, con un descriptor
  `{kind = "move" | "endadd" | "delete" | "text", ...}`. `move` reescribe
  `time` y `end_time` de la entrada de `hist`; `endadd` anota el
  `end_time`; borrar una línea convierte la entrada en `skip` (conserva la
  posición de la cola y "Deshacer" la desapila sin borrar nada); borrar un
  fin limpia `end_time`. Los borrados reinician `seen_lines` para que
  `reconcile` no los tome por un Ctrl+Z. `S.sync` puede ser `nil` (cola
  nunca abierta). Si "Deshacer" no encuentra la línea, muestra `Sy.warn`
  con prioridad (también con el transporte detenido); se limpia con el
  siguiente tap, "Deshacer" o "Vaciar cola".
- **Refresh.** Las operaciones fuerzan la recarga del cache con
  `S.state_count = -1` (la tab recarga al inicio del frame siguiente) y
  parchean solo lo que la UI usa en el frame de transición.
- **Granularidad de undo.** Un bloque por operación: diez clicks de nudge
  son diez puntos de undo. Agruparlos (`Undo_OnStateChange` con flush por
  inactividad) es una mejora opcional, con el riesgo de que un cierre
  inesperado deje cambios sin punto propio.
- **Limitaciones conocidas.** Un Ctrl+Z o Redo de REAPER sobre un nudge o
  movimiento deja la línea en su posición anterior mientras `hist` guarda
  la nueva: "Deshacer" retrocede la cola sin borrar la línea y avisa, y la
  línea se borra desde el panel. Mover a mano en el editor MIDI cae en el
  mismo caso. Reconocerla por posiciones previas se descartó por frágil:
  podía asignar un borrado o un movimiento a la entrada equivocada.

## 9. Publicar desde la tab (pendiente)

- Extraer `Lyrics.Publish(proj)` de `Nik_MusicState_PublishLyrics.lua` (el
  script queda como cáscara de pocas líneas), que devuelva versión,
  cantidad de líneas y tamaño en bytes.
- Botón Publicar y toggle de auto-publicar con debounce. No hay bucle: el
  cliente usa `FetchLyrics` al detectar el cambio de versión
  (`musicstate_bridge.md` §5).
- Aprovechar para probar el tope de `EXTSTATE` con una letra larga
  (`musicstate_data_model.md` §6).
- Disparar el auto-publicar por una firma del contenido (texto y tiempo de
  `S.events`, calculada en `refresh`) y no por
  `GetProjectStateChangeCount`, que cambia con cualquier edición del
  proyecto. El debounce tiene que superar la cadencia de nudges y taps
  (≥ 1,5 s). Verificar que publicar (ExtState global) no incrementa ese
  contador.
- Pendiente menor: revisar si la agrupación de undo (§8) vale la pena.
- Al implementarlo: actualizar este doc y `musicstate_helper.md`.

## 10. Para retomar en otra sesión

Adjuntar: este doc, `musicstate_helper.md`,
`MusicStateLyricsTab_common_logic.lua`, `MusicStateLyrics_common_logic.lua`,
`MusicStateLyricsSync_common_logic.lua`,
`MusicStateLyricsEdit_common_logic.lua`, `08_REAIMGUI_PATTERNS.md` e
`ImGuiInputCommit_common_logic.lua`. `Nik_MusicState_Helper.lua` solo si
hace falta (archivo grande: alcanzan las líneas de `dofile`, `helpers` y
el loop con los atajos globales). Para publicar desde la tab, además
`Nik_MusicState_PublishLyrics.lua`.
