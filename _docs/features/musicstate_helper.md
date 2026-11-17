# Feature — MusicState: Helper (ReaImGui)

`Nik_MusicState_Helper.lua`: panel nativo ReaImGui, único proceso residente
de la feature (corre mientras el usuario lo tiene abierto, vía
`reaper.defer(loop)`) y única fuente de verdad de las cinco keys que se
publican (formato de cada una: `musicstate_data_model.md` §2 y §4).

Fuera de este doc: guardado y puente (`musicstate_bridge.md`), atajos de
teclado (`musicstate_keys.md`, `musicstate_keys_inputs.md`), ingreso de
letras y tab Lyrics (`musicstate_lyrics_helper.md`), patrones y gotchas
genéricos de ReaImGui (`08_REAIMGUI_PATTERNS.md`).

## 1. Contenedor y módulos de tab

El contenedor (`Nik_MusicState_Helper.lua`) se ocupa de: contexto y fuente
ImGui, detección de cambio de proyecto, carga y guardado
`ProjExtState ↔ H` (`musicstate_bridge.md` §3 y §4), conversiones de
coordenadas (§2), captura de cursor, el ciclo de despacho de teclas
(`Keys`: atajos globales y por tab) y el `TabBar` que delega a cada módulo.
Cada tab vive en su propio archivo, todos en `MusicState/` (un solo dominio
consumidor, ver `01_CONVENCIONES.md`):

- `MusicStateTonalidad_common_logic.lua`
- `MusicStateRoles_common_logic.lua` y `MusicStateRoles_config.lua` (catálogo
  de roles, §2.3)
- `MusicStateArmonia_common_logic.lua`
- `MusicStateCues_common_logic.lua` (§2.2) y sus submódulos, que no son tabs:
  `MusicStateCuesModel_common_logic.lua` (modelo en memoria),
  `MusicStateCuesData_common_logic.lua` (codec de `cues_data`) y
  `MusicStateCuesEdit_common_logic.lua` (panel de edición)
- `MusicStateJson_common_logic.lua` (escape, formato numérico y decodificador
  JSON que respeta strings: lo usan el codec de cues, la lectura y el guardado
  de roles y la publicación de letras)
- `MusicStateLyricsTab_common_logic.lua` (la letra no vive en `H`: cache de
  lectura en `H._lyrics`, ver `musicstate_lyrics_helper.md` §6; el
  contenedor expone `helpers.Lyrics`)
- `MusicStateLyricsSync_common_logic.lua` (submódulo de la tab Lyrics: cola
  de tap-to-sync, ver `musicstate_lyrics_helper.md` §7). No es una tab
  propia: la tab lo invoca vía `helpers.LyricsSync.draw(ctx, S, H, helpers)`,
  con `S = H._lyrics`, y su estado vive en `S.sync`.
- `MusicStateLyricsEdit_common_logic.lua` (submódulo de la tab Lyrics: panel
  de edición de la fila seleccionada, ver `musicstate_lyrics_helper.md` §8).
  Tampoco es una tab propia: la tab lo invoca vía
  `helpers.LyricsEdit.draw(ctx, S, H, helpers)`, con `S = H._lyrics`, y su
  estado vive en `S.edit`.
- `MusicStateKeys_common_logic.lua` y `MusicStateKeys_config.lua` (despacho
  central de teclas y su config en datos; no son tabs). El contenedor los
  carga con `dofile`, expone `helpers.Keys` y llama a `Keys.begin_frame`,
  `Keys.set_tab` y `Keys.dispatch`.
- `Nik_MusicState_FocusHelper.lua`: one-shot para REAPER que lleva el foco
  del teclado al Helper (`musicstate_keys.md` §6).

Los módulos genéricos de ReaImGui que carga el contenedor viven en
`_Shared/` (ver `01_CONVENCIONES.md`): `ImGuiInputCommit`, `ImGuiHostFocus`
(foco ventana ↔ REAPER), `ImGuiConfirmModal` (ciclo de vida de un modal),
`ImGuiKeyCombo` (combo con teclado, `musicstate_keys_inputs.md` §5) e
`ImGuiButtonStyle` (estilo semántico de botones, §9).

Cada módulo de tab expone `M.draw(ctx, H, helpers)`. `H` es la tabla de
estado global, mutada in-place. `helpers` es una tabla de dependencias
armada **una sola vez** en el contenedor (no `dofile` repetido por módulo de
tab): funciones de conversión (`rowToTime`, `rowToQN`, `qnToRow`,
`getMaxBeats`), acceso a `RowInputs`/`InputCommit` (módulos compartidos, uno
en `MusicState/`, el otro en `_Shared/` por ser genérico de ReaImGui),
`Keys` (`Keys.consume`, `Keys.held`, `Keys.modal`, `Keys.input`,
`Keys.ring_*`: `musicstate_keys.md` y `musicstate_keys_inputs.md` §2 y §3),
`Modal` (modal de confirmación de `_Shared/`), `ButtonStyle` (estilo de
botones, §9), captura de cursor y `getSections()`.

## 2. Estado (`H`) y conversión de coordenadas

`H.harmony` es un array plano de filas `{measure, beat, hundredths, ...}`
(`H.cues` tiene otra forma: §2.2): la representación en memoria de Armonía
es **measure/beat/hundredths** (lo que el usuario tipea), no `qn_offset` (lo
que se publica). La conversión es explícita y en ambas direcciones,
resuelta una sola vez cada una:

- `nikMusicStateBeatToQnOffset(beat, hundredths, beat_unit_qn)`: hacia
  `qn_offset`, al guardar (`musicstate_bridge.md` §3). Redondea a la grilla
  de 0.25 QN.
- `nikMusicStateQnOffsetToBeat(qn_offset, beat_unit_qn)`: hacia
  `beat/hundredths`, al cargar (`musicstate_bridge.md` §4, vía
  `nikMusicStateLoadFromProjExtState`) y al reconstruir filas pegadas (§6).
  **Snapea a la grilla de 0.25 antes de hacer `floor()`:** sin el snap, el
  ruido de punto flotante acumulado (sumas de QN en un pegado) podía dejar
  un offset como `0.999999999996` en vez de `1.0` justo en un límite de
  beat; `floor()` lo mandaba al beat anterior, con `hundredths = 100`, y el
  clamp de `RowInputs` (0-99) lo fijaba en 99. Afecta a toda conversión
  QN→beat, no solo al pegado.
- `beat_unit_qn` (`4 / denominador` del compás) es el factor común a ambas
  conversiones; lo calcula `nikMusicStateBeatUnitQN(proj, measure)` leyendo
  `TimeMap_GetMeasureInfo`.

El parseo de `ProjExtState` al cargar es manual: `project_key` con patrones
simples (formato controlado por el propio Helper) y `harmony_data` con un
patrón no-greedy hasta el primer `]`. `project_roles` y `cues_data`, que
llevan texto libre, se leen con el decodificador de
`MusicStateJson_common_logic.lua`, que respeta los strings: un `]`, una
llave o una comilla escapada dentro de un texto no rompen la lectura. Al
guardar, ambas keys se escapan con el mismo módulo.

### 2.1 Tab Tonalidad

- **Modo:** dos `RadioButtonEx` exclusivos (Mayor, Menor) sobre
  `H.key.mode_idx` (0 = major, 1 = minor). No reciben el teclado: no están
  en el anillo de foco (`musicstate_keys_inputs.md` §9).
- **Tónica:** `KeyCombo` con las 12 tónicas del modo vigente
  (`TONICS_BY_MODE`). `H.key.tonic_idx` es el pitch class (0-11, 0 = C) y
  vale igual en las dos listas, así que cambiar de modo conserva la nota (Db
  mayor pasa a C# menor).
- **Grafías:** son las que fija el cliente (`MAJOR_USES_SHARPS` y
  `MINOR_USES_SHARPS` de `web/core/music-transpose.js`, ver
  `musicstate_client.md` §2.2): mayor C, Db, D, Eb, E, F, F#, G, Ab, A, Bb,
  B; menor C, C#, D, Eb, E, F, F#, G, G#, A, Bb, B. La tabla está duplicada
  en el Helper (Lua y JS son runtimes separados): si cambia en el cliente,
  actualizar `TONICS_BY_MODE`.
- **Carga:** `TONIC_NAME_TO_PC` acepta cualquier grafía publicada y la
  convierte a pitch class; al volver a publicar queda la canónica.
- **`H.key_set`:** la carga reinicia la tonalidad a C mayor y pone
  `key_set` en `true` solo si `project_key` existe con tónica y modo
  reconocidos; así no se arrastra la del proyecto anterior. Guardar y
  Publicar lo pone en `true`. Mientras es `false`, la tab avisa que no hay
  tonalidad publicada.

### 2.2 Tab Cues

Los cues viven en `H.cues`, una lista ordenada de cues
`{uid, qn, dur_qn, roles, text}`: `qn` es el QN absoluto de inicio,
redondeado a 3 decimales y sin grilla (sigue al mapa de tempo), y `dur_qn` la
duración en negras. Es un modelo de posición y duración, como las lyrics,
pero en `H` y no en eventos MIDI: los cues se solapan (roles distintos a la
vez) y el emparejamiento línea/fin de lyrics asume una sola línea vigente.

- **Modelo** (`MusicStateCuesModel_common_logic.lua`): la identidad es el
  `uid`, que asigna `insert` desde un contador de la lista (un contador de
  módulo se duplica, porque cada `dofile` crea su propia instancia). Toda
  mutación (`insert`, `delete`, `move`, `setText`, `setRoles`,
  `setDuration`) pasa por el módulo y devuelve su inversa, que es el punto de
  enganche del manager de Undo. También trae `filtered`, `activeAt` (puede
  devolver varios cues: los de roles distintos se solapan) y la conversión
  `qnToMeasure`/`measureToQn`, que redondea el QN antes de partirlo en
  compás y offset.
- **Persistencia** (`MusicStateCuesData_common_logic.lua`): `encode` y
  `decode` de `cues_data` (`musicstate_data_model.md` §4.4). Los cues en el
  formato anterior se leen sin migración. Si el texto no se puede leer, la
  carga deja la lista vacía y avisa en la línea de estado
  (`H.cues_load_error`); guardar en ese estado sobrescribe el dato.
- **Roles de un cue:** `todos` (`Model.ALL_ROLE`) es excluyente y una lista
  vacía cae en `todos`. El filtro "Ver" tiene su propia opción
  "(sin filtro)", que no es un rol; filtrar por un rol R muestra los cues de
  R más los dirigidos a `todos`.
- **Lista:** header fijo y body en un `BeginChild` con `NoNav` (§3), columnas
  Pos | Dur.(QN) | Roles | Texto (la última se estira), separadores grises
  de sección y `PushID(uid)` por fila. Los roles que no están en la lista de
  Roles se marcan en rojo, con tooltip. Se resaltan todos los cues activos en
  el cursor o en reproducción, sólido si el cursor coincide con el inicio; el
  scroll sigue al primero activo o, si no hay, al próximo.
- **Selección:** por `uid`. Un click selecciona o deselecciona, mueve el
  cursor y, con el checkbox "Seleccionar duracion al hacer click" (`ExtState`
  `cues_autoselect`), selecciona el rango de tiempo del cue. Esc deselecciona
  (override por tab, `cues.escape`). El estado de interfaz vive en
  `H._cues_ui` y se reinicia al cambiar de proyecto.
- **Alta:** `+ Cue en cursor` crea el cue en el cursor o, con una selección
  de tiempo, con su inicio y duración; va dirigido al rol filtrado o a
  `todos`, queda seleccionado y con el foco en el campo de texto.
- **Panel de edición** (`MusicStateCuesEdit_common_logic.lua`, submódulo: la
  tab lo invoca con `Edit.draw(ctx, S, H, helpers, tools)`, con
  `S = H._cues_ui` y estado en `S.edit`): alto fijo, widgets deshabilitados
  sin selección y línea de aviso siempre reservada. Texto con borrador y
  commit al perder el foco, por el `uid` del borrador; roles en un combo de
  checkboxes que no se cierra al marcar (el flag de `Selectable` se resuelve
  con un fallback por nombre, según la versión de ReaImGui); inicio con nudge
  de ±20 y ±100 ms y "Al cursor" (conserva la duración); duración con nudge
  sobre el fin, "Fin al cursor" y "Dur. = seleccion"; "Ir al inicio" y
  "Borrar cue" (sin confirmación). Con el checkbox activo, el rango de tiempo
  sigue al cue. Un cue editado de modo que deja de cumplir el filtro sigue
  seleccionado y editable aunque salga de la lista.

### 2.3 Tab Roles

Los roles del proyecto se tildan sobre un catálogo en
`MusicStateRoles_config.lua` (config en código, `01_CONVENCIONES.md`):
`bajo`, `bateria`, `guitarra`, `guitarra 2`, `teclado`, `teclado 2`, `voz`,
en singular y sin acentos. El id es el texto que se guarda y se publica, así
que cambiarlo desvincula los cues que ya lo usan. Cada entrada tiene
`default`: un proyecto sin roles guardados arranca con los `default` tildados
(todos menos `guitarra 2` y `teclado 2`). `H.roles` sigue siendo un array de
strings, ordenado según el catálogo, y `project_roles` no cambia de formato.

- Un rol con cues no se puede destildar ni quitar: el checkbox queda
  bloqueado, con el conteo y un tooltip.
- Un rol fuera del catálogo es la excepción (proyectos viejos con roles
  tipeados, casos puntuales): se muestra en "Fuera del catalogo" con
  `Quitar`, y se agrega con el campo "Agregar"; si el texto coincide con un
  id del catálogo, lo tilda.
- Un músico con varios sonidos es un solo rol (`teclado`); dos músicos del
  mismo instrumento se resuelven tildando `teclado 2`.

## 3. Sticky header sin romper Nav

Armonía tiene header fijo con scroll sin recuadros de foco fantasma ni doble
disparo de Space/Enter. El problema y la solución son genéricos de ReaImGui,
no específicos de esta feature: `08_REAIMGUI_PATTERNS.md` §1, con el código
base.

Aplicado en Armonía: `harmony_header` (fija) + `harmony_body`
(`BeginChild` con `WindowFlags_NoNav()`), columnas sincronizadas por
`setupHarmonyColumns(ctx)` (anchos fijos en `COLUMN_WIDTHS`).

## 4. Agrupado por sección, auto-scroll y highlight (tab Armonía)

- Las filas de `H.harmony` se agrupan por sección usando
  `helpers.getSections()` (cualquier marker cuenta, no filtra por
  nomenclatura). Cada fila va a la última sección con marker `<=` su tiempo
  (`helpers.rowToTime(row)`); sin marker anterior, al grupo `"Sin sección"`.
- Cada grupo se dibuja como `CollapsingHeader` + una tabla propia sin
  `ScrollY` (mismo `setupHarmonyColumns`, para no desalinearse del header
  fijo).
- Al mover el cursor de REAPER a otra sección, esa sección se auto-abre y
  hace scroll a la fila con tiempo más cercano al cursor dentro del grupo.
- La fila "activa" (última con tiempo `<=` cursor: la que suena por
  carry-over del acorde) se resalta con `TableSetBgColor`: sólido si el
  cursor coincide exacto (igualdad estricta measure/beat/hundredths), tenue
  si es carry-over. Sin parpadeo.

El agrupado dinámico (`CollapsingHeader` por sección) depende de IDs
estables y del manejo de `SetNextItemOpen` como flag consumible: patrón
genérico en `08_REAIMGUI_PATTERNS.md` §2. Acá el identificador estable es la
posición de la sección en la lista maestra de markers (nunca filtrada), con
`0` fijo para "Sin sección".

**`H.harmony` ordenado cronológicamente es una invariante:** el loop de
highlight corta con `break` en la primera fila posterior al cursor y
requiere ese orden. La mantiene `resortAndFocusRow` (§5), disparada al
agregar una fila y al terminar de editar el trío de posición de una
existente.

## 5. Edición en vivo: foco, reorden y validación

La detección de "terminó de editar" en los campos de posición
(Compás/Beat/Cent.) sigue el patrón genérico de `08_REAIMGUI_PATTERNS.md` §3
(transición de `active` entre frames, con valor congelado para todo lo que
no sea el propio input). Acá se aplica así:

- `H._armonia_active_row` guarda qué fila tenía foco el frame anterior; el
  reorden real corre recién cuando la fila pierde el foco.
- Mientras una fila sigue activa, el agrupado, el nearest-row del
  auto-scroll y el highlight usan un tiempo **congelado** (capturado al
  entrar en edición), no measure/beat/hundredths en vivo: sin esto, un solo
  dígito tipeado podía recolocar la fila en otro `CollapsingHeader` a mitad
  de edición y cortarle el foco.
- `resortAndFocusRow` ubica la fila por **identidad de tabla**, nunca por
  índice viejo, porque el índice es justo lo que el sort corre.
- El `PushID` de cada fila usa `row._uid` (campo interno, asignado al
  dibujar, no se publica), no el índice: un reorden no corre el ID de un
  input enfocado (`08_REAIMGUI_PATTERNS.md` §2). El tiempo congelado sigue
  haciendo falta: cambiar de grupo cambia el ID del widget, porque el
  `PushID` del grupo es parte del ID stack.
- Con las flechas, los campos de posición cambian de valor con el campo
  activo (`08_REAIMGUI_PATTERNS.md` §3, `musicstate_keys_inputs.md` §3):
  `drawPositionInputs` sigue devolviendo la fila como activa mientras un
  refoco (`Keys.ring_holds`) está pendiente, así que no se reordena ni se
  regrupa hasta salir del trío de posición.

**Validación de rango:** Beat mínimo 1, sin tope si `get_max_beats` no se
pasa; máximo real vía `helpers.getMaxBeats(measure)` cuando sí se pasa
(Armonía, el único consumidor). Hundredths siempre 0-99. Un mismo `clamp`
cubre tecleo directo y steppers +/-, porque `InputInt` no distingue el
origen del cambio en su valor de retorno. Efecto esperado: bajar el compás a
una métrica con menos beats puede bajar el valor de Beat solo. Alcance
deliberado: prevención en el input, sin auto-normalización ni rollover al
compás siguiente.

## 6. Selección y copiar/pegar (tab Armonía)

- **Selección:** columna checkbox, rango contiguo por dos clicks. Click en
  fila A arranca ancla; click en fila B completa el rango `[A..B]` por
  posición en `H.harmony` (cronológico); click en la misma fila cancela; con
  rango completo, click en cualquier fila descarta y arranca ancla nueva.
  `row.selected` es solo estado visual, no se publica.
- **Copiar** ("Copiar selección (N)"): arma un clipboard de
  `{delta_qn, chord}`, relativo en **QN absoluto** (no tiempo de reloj ni
  measure/beat crudo) a la fila cronológicamente más temprana de la
  selección: así la separación musical entre filas se preserva aunque origen
  y destino tengan tempo o compás distinto. Usa `helpers.rowToQN(row)`. El
  clipboard persiste hasta la próxima copia.
- **Pegar** ("Pegar en cursor (N)"): `helpers.qnToRow(cursor_qn + delta_qn)`
  reconstruye cada fila candidata (cae en rango válido sin clamp, por ser
  derivación directa de un tiempo real). Con colisión exacta contra filas
  existentes, un modal ofrece sobrescribir solo las filas puntuales
  colisionadas (Enter) o cancelar todo el pegado (Esc); ver
  `musicstate_keys.md` §5.

## 7. Cómo testear

**Colisión al pegar** (§6): pegar un bloque de filas sobre posiciones ya
ocupadas debe abrir el modal de conflicto y no pegar nada hasta resolver.

Pruebas de teclas (anillo de foco, Roles, combo, modales):
`musicstate_keys.md` §8 y `musicstate_keys_inputs.md` §8. El round-trip
completo de guardado y publicación (Helper → puente → cliente):
`musicstate_bridge.md` §6.

Modelo y codec de cues: `Tests-Debug/Nik_Test_CuesModel.lua` y
`Tests-Debug/Nik_Test_CuesData.lua`, de consola (imprimen `N ok, M fallas`)
y sin modificar el proyecto.

## 8. Pendientes

**Tab Tonalidad:**

- **"Sin definir" como valor real.** Guardar y Publicar siempre escribe
  `project_key`: en un proyecto sin tonalidad publica C mayor aunque nadie la
  haya elegido (la tab lo avisa, §2.1). Propuesta: un valor `-1`, con el
  combo vacío, ningún radio marcado y sin escribir `project_key` mientras
  siga así. Antes hay que ver cómo se comportan `Bridge.bridgeKey` y el
  cliente con `project_key` ausente.

**UX del Helper:**

- **Cues:**
  - Cola de tap-to-sync para cues: a evaluar con el uso. El modelo la soporta
    (identidad por `uid`, posición libre y `dur_qn` propio) y no necesita la
    reconciliación de Lyrics, porque `H` no pasa por el Undo de REAPER.
  - Manager de Undo del Helper, compartido por las tabs: usará las inversas
    que devuelven las operaciones del modelo. Hoy "Borrar cue" no pide
    confirmación.
- **Extracción de código común entre las tabs de lista (Lyrics, Cues y, si
  corresponde, Armonía),** como cambio aparte porque toca la tab Lyrics ya
  validada: la búsqueda de sección y el separador gris de sección
  (`findSectionIdx`); la selección y limpieza del rango de tiempo con el
  checkbox "Seleccionar duracion" y su `ExtState`; los botones de nudge, que
  devuelvan el delta sin mutar. A revisar contra `ImGuiInputCommit`: el
  borrador de `InputText` con commit al perder el foco. Se dejan duplicados
  el registro de Esc por tab y el cálculo de la fila activa (evento puntual
  en Lyrics, intervalos solapados en Cues). La lista de Armonía (agrupado con
  `CollapsingHeader`, copiar/pegar) queda fuera salvo que use alguna de estas
  piezas.
- **Recarga al cambiar de pestaña de proyecto:** el Helper no recarga sus
  datos al abrir una pestaña nueva sin guardar ni al cerrar la única pestaña;
  cambiar entre pestañas sí funciona. Hipótesis sin medir: el puntero del
  proyecto (`H.last_proj`) se reutiliza. Medir antes de tocar.
- Calibración cosmética del highlight de fila activa (colores hardcodeados a
  ojo) y de que los widgets de la fila no tapen el highlight de fondo.
- **Fuente centralizada del diccionario color/traducción de secciones**,
  compartida entre `web/config.js` (JS) y el Helper (Lua), que son runtimes
  separados sin puente directo. Serviría para colorear los
  `CollapsingHeader` de grupo según la sección. Dos opciones evaluadas: (A)
  módulo Lua en `_Shared/` como fuente canónica, con `config.js`
  manteniendo una copia derivada marcada como reflejo; (B) archivo de datos
  neutral (`.json`) parseado por ambos lados. Ojo con el path dev vs.
  deploy: en dev, `MusicState/` y `web/` son hermanas bajo
  `C:\dev\Rea-Nik\`; deployado vía ReaPack, `MusicState/` vive en
  `Scripts/Rea-Nik/MusicState` sin relación de ruta fija con `web/` (servida
  desde `reaper_www_root`): una ruta relativa tipo `../web/config.js` andaría
  en dev y se rompería en una PC de ensayo. Definir primero si el color de
  sección lo necesita el Helper en tiempo real o solo importa del lado web.

## 9. Estilo de botones

Los botones pasan por `_Shared/ImGuiButtonStyle_common_logic.lua`, que el
contenedor carga y expone como `helpers.ButtonStyle`. Los patrones genéricos
(pila de push/pop, tipos sin color, steppers) están en
`08_REAIMGUI_PATTERNS.md` §8.

| Tipo | Aspecto |
|---|---|
| `primary` | Lima `#B8FF6D`, texto negro; hovered y active derivados de la base |
| `neutral` | Colores default del tema |
| `danger` | Rojo `#A83232`, texto blanco; hovered y active derivados |
| `subtle` | Transparente hasta el hover o el clic |

Redondeo 4 en todos. `ButtonStyle.button(ctx, label, kind, opts)` devuelve
true con el clic. `opts` es un número (ancho fijo, negativo = rellenar) o una
tabla `{ w, pad, min_w, h }`; sin `opts`, tamaño nativo. `push` y `pop`
sirven para widgets que dibuja otra cosa. La paleta se ajusta en vivo con
`Tests-Debug/Nik_Test_ButtonStyle.lua`, que imprime la tabla lista para
pegar en el módulo.

`RowInputs.drawCursorButton(ctx, label, kind, opts)` aplica el estilo solo si
recibe `kind`; sin él dibuja el botón nativo. Los `InputInt` de Compás, Beat
y Cent. envuelven el widget con `subtle` (steppers sin fondo).

| Tab | Estado |
|---|---|
| Contenedor | `Guardar y Publicar`: primary |
| Tonalidad | Sin botones |
| Roles | `Agregar`: primary; `Quitar` (roles fuera del catálogo): danger |
| Armonía | `+ Agregar fila`: primary; `Borrar` y `Sobrescribir` (modal): danger; `Ir`, `Usar cursor`, `Copiar selección`, `Pegar en cursor` y `Cancelar` (modal): neutral |
| Cues | Sin estilo (tab y panel de edición) |
| Lyrics (tab, Sync y Edit) | Sin estilo |
