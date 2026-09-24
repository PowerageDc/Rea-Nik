# Feature — MusicState: Helper (ReaImGui)

`Nik_MusicState_Helper.lua`: panel nativo, único proceso residente de la
feature, y única fuente de verdad de las cinco keys que se publican (ver
`musicstate_data_model.md` §2 y §4 para el formato de cada una).

Este doc describe **cómo está hecho hoy**, no cómo se llegó ahí.

Panel nativo ReaImGui, único proceso residente de la feature (corre
mientras el usuario lo tiene abierto, vía `reaper.defer(loop)`). Es la
única fuente de verdad de las cinco keys: no hay otro lugar donde se
generen o editen.

## 1. Contenedor y módulos de tab

El contenedor (`Nik_MusicState_Helper.lua`) quedó reducido a: contexto y
fuente ImGui, detección de cambio de proyecto, carga/guardado
`ProjExtState ↔ H` (`musicstate_bridge.md` §3-4), conversiones de
coordenadas (§2),
captura de cursor, atajos de teclado globales (Space, Enter, flechas para
compás/marker anterior-siguiente) y el `TabBar` que delega a cada módulo.
Cada tab vive en su propio archivo, todos en `MusicState/` (un solo
dominio consumidor, ver `01_CONVENCIONES.md`):

- `MusicStateTonalidad_common_logic.lua`
- `MusicStateRoles_common_logic.lua`
- `MusicStateArmonia_common_logic.lua`
- `MusicStateCues_common_logic.lua`

Cada uno expone `M.draw(ctx, H, helpers)`. `H` es la tabla de estado
global, mutada in-place. `helpers` es una tabla de dependencias armada
**una sola vez** en el contenedor (no `dofile` repetido por módulo de
tab): funciones de conversión (`rowToTime`, `rowToQN`, `qnToRow`,
`getMaxBeats`), acceso a `RowInputs`/`InputCommit` (módulos compartidos,
uno en `MusicState/`, el otro en `_Shared/` por ser genérico de ReaImGui,
ver `01_CONVENCIONES.md`), captura de cursor y
`getSections()`.

## 2. Estado (`H`) y conversión de coordenadas

`H.harmony` y `H.cues` son arrays planos de filas
`{measure, beat, hundredths, ...}` — la representación en memoria del
Helper es **measure/beat/hundredths** (lo que el usuario tipea), no
`qn_offset` (lo que se publica). La conversión es explícita y en ambas
direcciones, resuelta una sola vez cada una:

- `nikMusicStateBeatToQnOffset(beat, hundredths, beat_unit_qn)`: hacia
  `qn_offset`, al guardar (`musicstate_bridge.md` §3). Redondea a la
grilla de 0.25 QN.
- `nikMusicStateQnOffsetToBeat(qn_offset, beat_unit_qn)`: hacia
  `beat/hundredths`, al cargar (`musicstate_bridge.md` §4 vía
  `nikMusicStateLoadFromProjExtState`) y al reconstruir filas pegadas (§5). **Snapea a la grilla de 0.25
  antes de hacer `floor()`.** Sin ese snap, ruido de punto flotante
  acumulado (sumas de QN en un pegado) podía dejar un offset como
  `0.999999999996` en vez de `1.0` justo en un límite de beat: `floor()`
  lo mandaba al beat anterior, con el resto (casi un beat entero)
  redondeando a `hundredths = 100`, y el clamp de `RowInputs` (0-99) lo
  pisaba a 99 de forma permanente en cuanto la fila se renderizaba una
  vez. Bug real, confirmado con filas de origen distinto colapsando en la
  misma posición corrupta. Afecta a toda conversión QN→beat, no solo al
  pegado.
- `beat_unit_qn` (`4 / denominador` del compás) es el factor común a
  ambas conversiones; lo calcula `nikMusicStateBeatUnitQN(proj, measure)`
  leyendo `TimeMap_GetMeasureInfo`.

El parseo de `ProjExtState` al cargar es manual, sin librería JSON:
`project_key`/`project_roles` con patrones simples (formato controlado
por el propio Helper), `harmony_data` con un patrón no-greedy hasta el
primer `]`. `cues_data` necesita balance de corchetes/llaves
(`%b[]`/`%b{}`, nativo de Lua) porque el array `roles` anidado dentro de
cada evento rompe el patrón simple de `harmony_data`.

## 3. Sticky header sin romper Nav

Armonía tiene header fijo con scroll sin recuadros de foco fantasma ni
doble disparo de Space/Enter. El problema y la solución son genéricos de
ReaImGui, no específicos de esta feature — documentados en
`08_REAIMGUI_PATTERNS.md` §1, con el código base.

Aplicado hoy: `harmony_header` (fija) + `harmony_body` (`BeginChild` con
`WindowFlags_NoNav()`), columnas sincronizadas por `setupHarmonyColumns(ctx)`
(anchos fijos en `COLUMN_WIDTHS`). Cues todavía no lo tiene (pendiente,
§8); al agregarlo, previsiblemente comparte el mismo bug si se le pone
`ScrollY` directo.

## 4. Agrupado por sección, auto-scroll y highlight (tab Armonía)

- Las filas de `H.harmony` se agrupan por sección usando
  `helpers.getSections()` (cualquier marker cuenta, no filtra por
  nomenclatura). Cada fila va a la última sección con marker `<=` su
  tiempo (`helpers.rowToTime(row)`); sin marker anterior, al grupo
  `"Sin sección"`.
- Cada grupo se dibuja como `CollapsingHeader` + una tabla propia sin
  `ScrollY` (mismo `setupHarmonyColumns`, para no desalinearse del header
  fijo).
- Al mover el cursor de REAPER a otra sección, esa sección se auto-abre y
  hace scroll a la fila con tiempo más cercano al cursor dentro del
  grupo.
- La fila "activa" (última con tiempo `<=` cursor — la que suena por
  carry-over del acorde) se resalta con `TableSetBgColor`: sólido si el
  cursor coincide exacto (igualdad estricta measure/beat/hundredths),
  tenue si es carry-over. Sin parpadeo.

El agrupado dinámico de grupos (`CollapsingHeader` por sección) depende
de IDs estables y del manejo de `SetNextItemOpen` como flag consumible —
patrón genérico, documentado en `08_REAIMGUI_PATTERNS.md` §2. Acá el
identificador estable es la posición de la sección en la lista maestra
de markers (nunca filtrada), con `0` fijo para "Sin sección".

**`H.harmony` ordenado cronológicamente es una invariante activa**, no un
supuesto: el loop de highlight corta con `break` en la primera fila
posterior al cursor, y requiere ese orden. La mantiene
`resortAndFocusRow` (§5), disparada al agregar una fila y al terminar
de editar el trío de posición de una existente.

## 5. Edición en vivo: foco, reorden y validación

La detección de "terminó de editar" en los campos de posición
(Compás/Beat/Cent.) sigue el patrón genérico de `08_REAIMGUI_PATTERNS.md`
§3 (transición de `active` entre frames, con valor congelado para todo
lo que no sea el propio input). Acá se aplica así:

- `H._armonia_active_row` guarda qué fila tenía foco el frame anterior;
  el reorden real corre recién cuando la fila pierde el foco.
- Mientras una fila sigue activa, el agrupado, el nearest-row del
  auto-scroll y el highlight usan un tiempo **congelado** (capturado al
  entrar en edición), no measure/beat/hundredths en vivo — sin esto, un
  solo dígito tipeado podía recolocar la fila en otro
  `CollapsingHeader` a mitad de edición y cortarle el foco (confirmado:
  solo fallaba si la fila editada no era la primera de su grupo).
- `resortAndFocusRow` ubica la fila por **identidad de tabla**, nunca por
  índice viejo, porque el índice es justo lo que el sort corre.

**Validación de rango:** Beat mínimo 1, sin tope si `get_max_beats` no se
pasa (Cues no lo pasa todavía, ver pendientes); máximo real vía
`helpers.getMaxBeats(measure)` cuando sí se pasa (Armonía). Hundredths
siempre 0-99. Un mismo `clamp` cubre tecleo directo y steppers +/-, porque
`InputInt` no distingue el origen del cambio en su valor de retorno.
Efecto esperado, no bug: bajar el compás a una métrica con menos beats
puede bajar el valor de Beat solo. Alcance deliberado: prevención en el
input, sin auto-normalización/rollover al compás siguiente.

## 6. Selección y copiar/pegar (tab Armonía)

- **Selección:** columna checkbox, rango contiguo por dos clicks. Click
  en fila A arranca ancla; click en fila B completa el rango `[A..B]` por
  posición en `H.harmony` (cronológico); click en la misma fila cancela;
  con rango completo, click en cualquier fila descarta y arranca ancla
  nueva. `row.selected` es solo estado visual, no se publica.
- **Copiar** ("Copiar selección (N)"): arma un clipboard de
  `{delta_qn, chord}`, relativo en **QN absoluto** (no tiempo de reloj ni
  measure/beat crudo) a la fila cronológicamente más temprana de la
  selección — así la separación musical entre filas se preserva aunque
  origen y destino tengan tempo o compás distinto. Usa
  `helpers.rowToQN(row)`. El clipboard persiste hasta la próxima copia.
- **Pegar** ("Pegar en cursor (N)"): `helpers.qnToRow(cursor_qn +
  delta_qn)` reconstruye cada fila candidata (cae en rango válido sin
  clamp, por ser derivación directa de un tiempo real). Con colisión
  exacta contra filas existentes, un modal ofrece sobrescribir solo las
  filas puntuales colisionadas o cancelar todo el pegado.

## 7. Glitch conocido, sin resolver

Hay un glitch preexistente de Enter en la tab Roles, confirmado que ya
ocurría antes del refactor de modularización (no lo introdujo). Sin
investigar todavía.


## 8. Cómo testear

**Colisión al pegar** (§6): pegar un bloque de filas sobre posiciones ya
ocupadas debe abrir el modal de conflicto y no pegar nada hasta
resolver.

El round-trip completo de guardado y publicación (Helper → puente →
cliente) está en `musicstate_bridge.md` §6, porque ejercita ambas capas
juntas.

## 9. Pendientes

**Bugs confirmados, sin corregir:**

- **Header `@provides` desactualizado.** `Nik_MusicState_Helper.lua`
  todavía lista `../_Shared/MusicStateBridge_common_logic.lua` y
  `../_Shared/MusicStateRowInputs_common_logic.lua`, pero ambos módulos
  se movieron a `MusicState/` (§1) y los `dofile` ya apuntan ahí. Un
  paquete de ReaPack armado hoy buscaría esos dos archivos en la ruta
  vieja. Corregir el header para que coincida con la ubicación real.
- **Oferta de grafías del Helper.** El Helper ofrece 17 tónicas (incluidas
  ambas grafías de los enarmónicos). Como el círculo de quintas siempre
  fuerza una sola grafía por tonalidad resultante
  (`musicstate_client.md` §2.2), tiene sentido que el selector ofrezca
  solo las que el cliente va a respetar, para no mostrar una opción que
  después se reescribe. Depende de que se resuelva primero el bug de
  grafía con delta 0 (`musicstate_client.md` §4).

**UX del Helper (de `WIP-MusicState_HelperUI.md`, archivado):**

- Aplicar el patrón de sticky header (§3) a la tab Cues; hoy no lo tiene,
  y previsiblemente comparte el mismo bug de Nav si se le agrega
  `ScrollY` directo.
- `drawPositionInputs` en Cues todavía usa la firma vieja (sin
  `get_max_beats`): compatible hacia atrás, pero sin tope de Beat hasta
  actualizar ese call site.
- Extraer un módulo compartido de "lista posicionada" (Armonía + Cues) a
  `_Shared/`, recién cuando Cues tenga su propia versión de agrupado/
  auto-scroll/selección/copiar-pegar — para generalizar sobre dos
  implementaciones reales, no adivinar la abstracción de antemano.
- En Cues, botón "Usar selección de tiempo" para `duration_qn` (vía
  `GetSet_LoopTimeRange`).
- Calibración cosmética del highlight de fila activa (colores hardcodeados
  a ojo) y de que los widgets de la fila no tapen el highlight de fondo.
- Fuente centralizada del diccionario color/traducción de secciones,
  compartida entre `web/config.js` (JS) y el Helper (Lua) — hoy son
  runtimes separados sin puente directo. Serviría para colorear los
  `CollapsingHeader` de grupo según la sección. Dos opciones evaluadas,
  ninguna implementada: (A) módulo Lua en `_Shared/` como fuente canónica,
  con `config.js` manteniendo una copia derivada marcada como reflejo; (B)
  archivo de datos neutral (`.json`) parseado por ambos lados. Ojo con el
  path dev vs. deploy: en dev, `MusicState/` y `web/` son hermanas bajo
  `C:\dev\Rea-Nik\`; deployado vía ReaPack, `MusicState/` vive en
  `Scripts/Rea-Nik/MusicState` sin relación de ruta fija con `web/`
  (servida desde `reaper_www_root`) — una ruta relativa tipo
  `../web/config.js` andaría en dev y se rompería en una PC de ensayo.
  Definir primero si el color de sección lo necesita el Helper en tiempo
  real o solo importa del lado web, antes de elegir A o B.

El glitch de Enter en la tab Roles ya está anotado en §7, no se repite
acá.
