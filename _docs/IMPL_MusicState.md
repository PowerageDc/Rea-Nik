# IMPL — MusicState (Metadata musical + Web Controller)

Documento transicional (ver convención en `01_CONVENCIONES.md` /
`00_CONTEXTO_GENERAL.md`: `IMPL_<name>.md` por feature, consolidado luego
en un doc de feature dedicado, en sesión aparte). No reemplaza el spec
original — lo complementa con las decisiones de implementación y los
resultados de tests reales corridos sobre el proyecto.

Spec de referencia (objetivo/arquitectura conceptual, sin editar):
`REAPER Musical Metadata & Web Controller — Specification.md`.

Dominio nuevo: `MusicState/` (siguiendo la convención de subcarpetas por
dominio de `01_CONVENCIONES.md`).

---

## 1. Decisión de fondo: sin scripts residentes

Preocupación inicial: que la capa de metadata musical implique un script
`defer()` corriendo siempre, incluso trabajando offline en la PC.

Resuelto por diseño, no por switch manual: todo el mecanismo es **one-shot**
(se dispara, escribe ExtState, termina) + **cálculo en el cliente JS** en
cada tick de poll normal. Nada corre del lado REAPER si nadie tiene la
página del control remoto/UI abierta — mismo patrón ya usado para
`tempo_map` (`Nik_Playrate_ReadTempoMap.lua`).

Trigger del one-shot: disparado por el cliente (HTTP a `/_/<command_id>`)
al conectar la UI, y a re-disparar cuando se detecta cambio de proyecto
(pendiente de implementar la detección — ver sección 6).

---

## 2. Gotcha confirmado: `GET/EXTSTATE` no lee `ProjExtState`

Test: `Nik_Tests_ExtStateProbe.lua` (`Tests-Debug/`). Escribe el mismo
valor en `SetProjExtState` y `SetExtState`, compara ambos vía endpoint
nativo:

```
GET/EXTSTATE/NikRemote/test_key        → devuelve el valor (ExtState global)
GET/EXTSTATE/NSAUDIOMUSIC/test_key     → key presente, SIN valor (ProjExtState)
```

**Conclusión:** el Web Control de REAPER solo lee `ExtState` global. Todo
dato que se guarde en `ProjExtState` (correcto por ser project-scoped,
persiste en el `.rpp`) necesita un script puente que lo copie a `ExtState`
global antes de que el cliente pueda leerlo.

---

## 3. Gotcha confirmado: Web Control escapa saltos de línea reales

Al publicar un JSON multilínea (Lua `[[...]]`) vía `SetExtState` y leerlo
por `GET/EXTSTATE`, REAPER devuelve los saltos de línea como `\n` **literal**
(barra invertida + n, dos caracteres) — no como salto real. Es el protocolo
línea-por-registro del Web Control (`EXTSTATE\t<ns>\t<key>\t<valor>`), no
un bug de `ExtState`.

**Regla:** cualquier valor que se publique para ser leído por este
mecanismo debe armarse **ya compacto en una sola línea** desde el script
Lua (sin whitespace/newlines), nunca confiar en que el cliente limpie el
escape. Mismo criterio que ya usan `tempo_map`/`timesig_map` (strings
planos).

---

## 4. Modelo de datos armónicos — cerrado

### 4.1. Namespace y puente

- `ProjExtState`: namespace `NSAUDIOMUSIC` (sin guion bajo tras NS),
  key `harmony_data` — donde el helper de carga (pendiente, ver sección 7)
  va a escribir.
- Puente a `ExtState` global: namespace `NikMusicState`, key `harmony_data`
  — lo que el cliente lee vía `GET/EXTSTATE/NikMusicState/harmony_data`.

### 4.2. Formato

JSON único (no keys por bar — evita N requests y descalza del patrón de
poll único ya existente), compacto en una sola línea. Array de eventos
por compás, indexado por número de compás (string, 1-indexed):

```json
{"12":[{"qn_offset":0.0,"chord":"Cmaj7"},{"qn_offset":2.5,"chord":"Dm7"}],"13":[{"qn_offset":0.0,"chord":"G7"},{"qn_offset":3.75,"chord":"Cmaj7"}]}
```

- `qn_offset`: negras (quarter notes) desde el downbeat del compás, grilla
  0.25 (= resolución de semicorchea siempre, independiente del compás).
- Se descartó el modelo `beat` + `sixteenth` (dependiente del denominador,
  requeriría tabla de conversión y validación de rango distinta por tipo
  de compás). `qn_offset` maneja simples, compuestos e irregulares
  (5/4, 7/8, 5/8...) sin caso especial.
- Duración de un compás en QN, para ubicar el próximo downbeat:
  `duracion_compas_QN = numerador * (4 / denominador)`.

### 4.3. Pendiente de spec, no bloqueante

Cambios de métrica a mitad de canción ya están cubiertos por el modelo
(cada compás resuelve su propia duración vía el `timesig_map`, sección 5).
No se identificaron casos sin cubrir.

---

## 5. `timesig_map` — implementado y testeado

Extensión de `Nik_Playrate_ReadTempoMap.lua` (mismo script, reusa el loop
de markers existente para no iterar dos veces). Nueva key `ExtState`:
`NikRemote/timesig_map`.

### Formato

```
measure1:num1:den1,measure2:num2:den2,...
```

`measure` es 1-indexed (la API de REAPER da `measurepos` 0-indexed —
confirmado con test, ver abajo — se suma `+1` en el script).

### Resultados de test (`Tests-Debug`, sample real de 243 markers)

- `GetTempoTimeSigMarker` devuelve `tnum=-1, tden=-1` en markers que
  **no** declaran cambio de time signature (son puramente de tempo).
  Filtro correcto para publicar una entrada: **`tnum ~= -1`** (la hipótesis
  inicial `tnum > 0` era incorrecta).
- `measurepos` es **0-indexed** (confirmado: `i=0` con `timepos=0.0000`
  da `measurepos=0`, que corresponde al compás 1 del ruler).
- `measurepos` es confiable y monotónico — se descartó pasar por
  `TimeMap2_timeToQN` + `TimeMap_QNToMeasures` para resolver el compás
  (innecesario, y el test inicial de esa función tenía además un bug de
  firma propio, no reproducir).
- Caso real encontrado en el propio proyecto de prueba: compás 125 en
  2/4 insertado en medio de una sección en 4/4 — valida el modelo con un
  caso real, no solo hipotético.
- Caso "proyecto sin ningún tempo marker": fallback ya contemplado
  (`GetProjectTimeSignature2` sobre el time signature global), mismo
  patrón que el fallback existente de `tempo_map`. No testeado en vivo
  todavía (sí se probó que un proyecto sin markers cae en el mensaje
  "sin markers" esperado, pero no específicamente el fallback de
  `timesig_map`).

### Estado del script

Ya modificado, deployado y validado por URL directa
(`GET/EXTSTATE/NikRemote/timesig_map`) devolviendo el formato esperado.

---

## 6. Detección de cambio de proyecto (cliente) — cerrado

Resultó estar **ya implementado** desde la sesión que cerró la sección 12
(`wwr-dispatch.js`, caso `EXTSTATE`/`NikRemote`/`active_project_name`,
dispara `nikMusicStateRequestAll()` igual que `nikPlayrateRequestTempoMap()`)
— lo que faltaba no era la detección en sí, sino que el bridge Lua no
limpiaba el puente al no encontrar dato. Ver sección 13.5 (Helper UI) para
el detalle completo del bug y el fix — se dejó documentado ahí en vez de
acá porque se encontró en el contexto de esa sesión, con los tests que lo
confirman.

**Validado con test real:** dos proyectos abiertos en tabs distintas de
REAPER (tonalidades distintas cargadas en cada uno), switch repetido entre
ambos con la pestaña del control remoto en foco — `GET/EXTSTATE/
NikMusicState/project_key` refleja siempre el proyecto activo correcto,
incluyendo el caso "proyecto sin dato guardado" (limpia a vacío, no hereda
el valor del proyecto anterior).

---

## 7. Script one-shot: `Nik_MusicState_PublishAll.lua`

(Renombrado desde `Nik_MusicState_PublishHarmony.lua` en la sesión que
cerró las secciones 10-11: pasó de publicar solo `harmony_data` a
publicar las 4 piezas de datos de la feature en la misma pasada —
`harmony_data`, `project_key`, `project_roles`, `cues_data` — porque
comparten el mismo trigger, sección 1. Sin costo de deploy: la feature
`MusicState` todavía no salió en ningún paquete ReaPack.)

**Nuevo**, en `MusicState/` (dominio nuevo). Simula los helpers de carga
(pendientes, sección 8.3 y sesión aparte para roles/cues) escribiendo
datos de prueba directo en `ProjExtState`, y hace el puente a `ExtState`
global — una key por dato.

Validado de punta a punta: `ProjExtState` → puente → `ExtState` global →
`GET/EXTSTATE/NikMusicState/harmony_data` → JSON compacto, válido, sin
`\n` residual, listo para `JSON.parse()` sin procesamiento extra del lado
cliente.

**Validado en REAPER** (los 4 `GET/EXTSTATE/NikMusicState/<key>` devuelven
el JSON esperado, sin `\n` residual, incluyendo `project_roles` — el único
array JSON en el nivel raíz de los 4 — y `cues_data` — el único con array
anidado dentro de objeto por rol). Sin casos borde encontrados en esta
prueba puntual.

**TODO explícito en el script:** reemplazar `sample_harmony` (hardcodeado)
por lectura real desde el helper de carga cuando exista (sección 8).

---

## 8. Próximos pasos

En orden sugerido, no bloqueante entre sí salvo donde se indique:

1. ~~`core/music-state.js` (cliente)~~ — **hecho, ver sección 12.**
2. ~~Detección de cambio de proyecto~~ — **hecho, ver sección 6 y 13.5**
   (resultó ser un bug de bridge, no una feature faltante).
3. **Helper UI** para cargar la metadata musical en `ProjExtState` sin
   editar el script a mano — reemplaza el TODO de
   `Nik_MusicState_PublishAll.lua`. **En progreso, ver sección 13** —
   diseño cerrado, pasos 1-3 de 7 implementados y validados (scaffold +
   captura de cursor, tabs Tonalidad/Roles, bridge reusable + guardado).
4. **UIs separadas por perfil** (no extensión del remote existente):
   coordinador (ya existe), cantantes (lyrics + datos básicos de la
   canción), instrumentistas (acordes pasados/próximos, indicaciones,
   potencialmente específicas por instrumento).
5. Consolidación: cuando el dominio `MusicState` + UIs por perfil estén
   en un estado cerrado, fusionar este documento en un doc de feature
   propio (o en `remote_control.md`), sesión dedicada aparte — mismo
   tratamiento que el resto de los `IMPL_*.md` pendientes de consolidar.

---

## 9. Archivos tocados en esta sesión

- **Nuevo:** `Tests-Debug/Nik_Tests_ExtStateProbe.lua`
- **Nuevo (test descartable, no integrado al repo salvo que se decida
  conservarlo):** prueba de `GetTempoTimeSigMarker` / sentinel `tnum=-1` /
  `measurepos` 0-indexed — corrida inline, no se guardó como archivo
  permanente.
- **Modificado:** `RemoteControl/Nik_Playrate_ReadTempoMap.lua` (agrega
  `timesig_map`).
- **Nuevo:** `MusicState/Nik_MusicState_PublishHarmony.lua`.
- **Nuevo → renombrado:** `MusicState/Nik_MusicState_PublishHarmony.lua`
  → `MusicState/Nik_MusicState_PublishAll.lua` (ver sección 7).
- **Nuevo:** `core/music-transpose.js`.
- **Nuevo:** `core/music-state.js`.
- **Modificado:** `core/state.js` (nueva variable `nikLastPositionBeatsStr`).
- **Modificado:** `core/wwr-dispatch.js` (cacheo de `tok[5]`, wiring de
  `NikMusicState/*` + `timesig_map`, trigger de `nikMusicStateRequestAll`).
- **Modificado:** `config.js` (Command ID de `musicStatePublishAll`).
- **Modificado:** `playrate.js` (pide `timesig_map` junto con `tempo_map`
  en `nikPlayrateRequestTempoMap` y `nikOpenPlayrateModal`).
- **Modificado:** HTML del control remoto (script tags de los 2 archivos
  nuevos).
- **Modificado:** `01_CONVENCIONES.md` (patrón nuevo: módulos JS de puro
  cálculo, wrapper de objeto único).
- **Nuevo:** `MusicState/Nik_MusicState_Helper.lua` (Helper UI, ver
  sección 13 — en progreso, pasos 1-3 de 7).
- **Nuevo:** `_Shared/MusicStateBridge_common_logic.lua` (bridge
  `ProjExtState` → `ExtState` extraído de `PublishAll`, consumido por
  ambos scripts).
- **Modificado:** `MusicState/Nik_MusicState_PublishAll.lua` (usa
  `MusicStateBridge_common_logic.lua` en vez de bridge inline; dejó de
  pisar `project_key`/`project_roles` con sample una vez que el Helper
  escribe datos reales para esas dos keys).

---

## 10. Transposición de tonalidad — decisiones (sesión nueva)

Extiende el modelo cerrado en la sección 4. No reabre nada de lo ya
decidido ahí (formato de `harmony_data`, namespace, puente).

### 10.1. Cálculo: 100% cliente, sin script residente nuevo

El delta de semitonos ya se lee del lado cliente (poll de ReaPitch
existente). No hace falta un one-shot adicional ni nada del lado REAPER:
el servidor sigue publicando acordes y tonalidad **sin transponer**, y el
cliente aplica el delta en cada tick — mismo patrón ya usado para el
backward-lookup de BPM contra `tempo_map`.

### 10.2. Nuevo dato: `project_key`

- `ProjExtState`: namespace `NSAUDIOMUSIC`, key `project_key`.
- Puente a `ExtState` global: namespace `NikMusicState`, key `project_key`.
- Formato: `{"tonic":"G","mode":"major"}` — mayor o menor únicamente, sin
  casos exóticos.

### 10.3. Parseo de acorde: raíz vs. calidad

Para transponer solo la fundamental sin tocar sufijos (`maj7`, `m7`,
`sus4`, `sus2`, `9`, `add9`, `dim`, `aug`, alteraciones), el cliente separa
el string de `harmony_data` en:

```
raíz (letra A-G + accidental opcional #/b) → se transpone
resto del string → se copia tal cual
```

Incluye desde el inicio soporte para bajo con slash (`C/E`): se parsea y
transpone también la nota de bajo, no queda para una iteración futura.

### 10.4. Enarmonía: por tonalidad resultante, no tabla fija

Se descartó una tabla fija de 12 posiciones (mismo criterio siempre,
sin importar la tonalidad). Se usa el criterio de círculo de quintas:
la tonalidad resultante (`project_key` + delta) determina si esa
transposición completa se escribe con sostenidos o bemoles, y ese criterio
se aplica de forma uniforme a todas las fundamentales de acordes de esa
transposición (incluyendo acordes no diatónicos a la tonalidad).

**Pendiente de implementar:** tabla de las 12 tonalidades mayores + 12
menores con su preferencia sostenidos/bemoles, y el módulo de
transposición en sí (parser de 10.3 + esta tabla + suma de delta).

### 10.5. Estado: implementado y testeado (consola), orden de carga pendiente

`core/music-transpose.js` escrito (wrapper `nikTranspose`, ver
`01_CONVENCIONES.md` → "Patrón de módulos JS de puro cálculo"). Validado
a mano en consola del browser (pegando el archivo completo): casos
`nikTranspose.chord("C/E", 1, false)` → `"Db/F"` y
`nikTranspose.key("F#", "major", 0)` → sostenidos, ambos correctos.

**Pendiente, no bloqueante:** todavía no está decidido si el control
remoto del coordinador (UI ya existente) necesita este módulo en su
primera iteración, o si queda reservado exclusivamente para las UIs de
instrumentista/cantante (sección 8, punto 4) — que podrían vivir en un
servidor/IP distinto al del coordinador (`192.168.x.x` por perfil,
arquitectura aún no cerrada). Esto define en qué HTML(s) se agrega el
`<script src="core/music-transpose.js">` y en qué orden respecto a
`state.js` — no se puede cerrar el order-of-load real hasta que se decida
la arquitectura de UIs por perfil.

---

## 11. Indicaciones por rol de intérprete — `cues_data` (sesión nueva)

Capa nueva, distinta de la armonía: no es "estado siempre vigente" como
un acorde, sino un evento con inicio y fin propio (aparece en la UI del
rol correspondiente, después se apaga).

### 11.1. Roles: lista configurable por proyecto, no atada a los stems

Se descartó usar los nombres de track (`Drums, Bass, Guitar, Piano, Other,
Vocals`, ver `01_CONVENCIONES.md`) como taxonomía de roles — el stem
`Other` varía de canción a canción (puede ser órgano, vientos, etc.), por
lo tanto el rol de intérprete tampoco es fijo. Se define como lista de
roles configurable por proyecto.

- `ProjExtState`: namespace `NSAUDIOMUSIC`, key `project_roles`.
- Puente a `ExtState` global: namespace `NikMusicState`, key `project_roles`.
- Formato: array de strings, ej. `["coordinador","cantantes",
  "guitarristas","bajistas","bateria","organo"]`.
- `"todos"` **no** forma parte de esta lista — es un valor reservado,
  implícito, siempre disponible como target de una indicación sin
  necesidad de configurarlo por proyecto.

### 11.2. Nuevo dato: `cues_data`

- `ProjExtState`: namespace `NSAUDIOMUSIC`, key `cues_data`.
- Puente a `ExtState` global: namespace `NikMusicState`, key `cues_data`.
- Formato, mismo criterio que `harmony_data` (keyed por compás,
  1-indexed, `qn_offset` con grilla 0.25):

```json
{"12":[{"qn_offset":0.0,"roles":["cantantes"],"text":"respirar","duration_qn":2.0}]}
```

- `roles`: array de strings — puede targetear más de un rol a la vez
  (ej. `["guitarristas","bajistas"]`), o `["todos"]`.
- `duration_qn`: duración de la indicación en negras desde `qn_offset`.
  **Apagado por duración explícita**, fijada al crear la indicación —
  se descartaron las alternativas "hasta la próxima indicación del mismo
  rol" y "hasta el siguiente marker/sección". Puede cruzar un límite de
  compás sin caso especial: el cliente ya maneja posición absoluta en QN
  (mismo mecanismo que usa para `tempo_map`/`timesig_map`), no hace falta
  acotar la indicación al compás en que empieza.

### 11.3. Impacto en pendientes ya anotados (sección 8, este documento)

- **Helper UI** (punto 3 de la sección 8 original): además de cargar
  `harmony_data`, va a necesitar cargar `project_key`, `project_roles` y
  `cues_data`.
- **UIs separadas por perfil** (punto 4 de la sección 8 original): cada
  UI de instrumentista filtra `cues_data` por su propio rol + `"todos"`.
  
---

## 12. Capa cliente JS — implementada y validada (sesión nueva)

### 12.1. `core/music-transpose.js`

Wrapper `nikTranspose` (primer caso del patrón "módulos JS de puro
cálculo", ver `01_CONVENCIONES.md`). Transpone tonalidad y acordes
(incluyendo bajo con slash, `C/E`), con grafía sostenidos/bemoles resuelta
por círculo de quintas sobre la tonalidad **resultante**, no una tabla
fija — mismo criterio aplicado de forma uniforme a toda fundamental de esa
transposición, incluyendo acordes no diatónicos.

Validado en consola: `nikTranspose.chord("C/E", 1, false)` → `"Db/F"`;
`nikTranspose.key("F#", "major", 0)` → sostenidos (caso de empate
enarmónico resuelto a mano). Validado también end-to-end vía
`nikReaPitchLastSemitone` real (sección 12.4).

### 12.2. `core/music-state.js`

Patrón: variables/funciones sueltas en global scope, prefijo
`nikMusicState*` (no wrapper de objeto — a diferencia de
`music-transpose.js`, este módulo tiene estado propio cacheado, no es
puro cálculo).

Resuelve, a partir de `nikLastPositionBeatsStr` (compás/beat crudo,
cacheado en cada TRANSPORT) + `NikRemote/timesig_map` +
`NikMusicState/*`:

- **Posición actual** (`nikMusicStateCurrentPos`): compás + `qn_offset`
  dentro del compás. Fórmula confirmada con test manual en REAPER (2/4 y
  6/8): el beat de `tok[5]` está en unidades del **denominador** del
  compás, no siempre negras — `(beatIndex - 1 + hundredths/100) *
  (4/denominador)`.
- **Aplanado genérico** (`nikMusicStateFlattenBarKeyed`): sirve para
  `harmony_data` y `cues_data` por igual (ambos keyed por compás),
  ordenado por `(bar, qn_offset)` — no hace falta QN absoluto para
  ordenar, el número de compás ya es monótono.
- **Acorde vigente/próximo/ventana** (`nikMusicStateCurrentChord`,
  `nikMusicStateNextChord`, `nikMusicStateChordWindow`): backward-lookup
  sobre el array aplanado, con **carry-over** (compás sin entrada propia
  hereda el último acorde conocido) y soporte para el sentinel `chord:
  null` (silencio explícito, corta el carry-over) — aunque el sentinel en
  sí no se probó todavía con datos reales, solo el carry-over normal.
  `nikMusicStateChordWindow(lookBack, lookForward)` es la base para el
  prompter futuro (lyrics) — navegación por cantidad de eventos, sin
  límite fijo de 1.
- **Indicaciones por rol** (`nikMusicStateActiveCues`): filtra por rango
  `[inicio, inicio+duration_qn)` en **QN absoluto**
  (`nikMusicStateBarStartQn`, acumulando duración de compases previos vía
  `timesig_map`) — necesario porque `duration_qn` puede cruzar un límite
  de compás. `"todos"` matchea siempre, sin estar en `project_roles`
  (reservado, sección 11.1).
- **Transposición al leer** (`nikMusicStateTransposeChordIfNeeded`,
  `nikMusicStateCurrentProjectKey`): se aplica en el momento de la
  consulta usando el delta vigente de `nikReaPitchLastSemitone`, nunca
  sobre el array cacheado — un cambio de semitonos en caliente no obliga
  a re-aplanar nada.
- **Trigger** (`nikMusicStateRequestAll`): mismo criterio que
  `nikPlayrateRequestTempoMap` — on-connect/on-project-change, no vive en
  el poll de fondo (namespace `NikMusicState` es aparte de
  `NIK_SLOW_POLL`).

### 12.3. Wiring

- `config.js`: Command ID real registrado para
  `NIK_LUA_COMMANDS.musicStatePublishAll` (`Nik_MusicState_PublishAll.lua`).
- `playrate.js`: `nikPlayrateRequestTempoMap()` y `nikOpenPlayrateModal()`
  ahora piden también `NikRemote/timesig_map` en la misma request que
  `tempo_map` — antes solo se pedía `tempo_map`, aunque el script Lua ya
  publicaba los dos (gap encontrado en esta sesión, no era un bug del
  script sino del lado que lo consume).
- `wwr-dispatch.js`: wiring de los 4 setters de `NikMusicState` +
  `NikRemote/timesig_map`, y disparo de `nikMusicStateRequestAll()` en el
  mismo punto donde ya se dispara `nikPlayrateRequestTempoMap()` (cambio
  de proyecto).
- `state.js`: nueva variable `nikLastPositionBeatsStr`, cacheada
  incondicionalmente en cada TRANSPORT (a diferencia de
  `statusPosition[0]`, que solo recibe `tok[5]` cuando
  `nikPositionDisplayMode == "measures"`).
- HTML del control remoto: `core/music-transpose.js` y
  `core/music-state.js` agregados antes de `core/wwr-dispatch.js`
  (después de `core/state.js`).

### 12.4. Validación en vivo — metodología y resultados

**Metodología de test manual** (repetible para features futuras de este
tipo): posicionar el playhead a mano vía el campo de posición de REAPER
(doble click en la barra de transporte, tipear `compás.beat.centésimas`),
leer `GET/EXTSTATE/<ns>/<key>` o `GET/TRANSPORT` por URL directa en el
navegador, y/o consultar las funciones JS ya cacheadas desde la consola
del navegador en la página real del control remoto.

**Resultados:**
- Los 4 `GET/EXTSTATE/NikMusicState/<key>` devuelven JSON válido, sin
  `\n` residual (incluyendo `project_roles`, array en el nivel raíz, y
  `cues_data`, con array anidado dentro de objeto por rol).
- Carry-over de acorde confirmado (compases sin entrada propia heredan el
  último conocido; antes del primer evento, `null`).
- Cruce de compás en `cues_data` confirmado en dos métricas reales del
  proyecto: en 4/4, una cue de `duration_qn: 2.0` corta a mitad del mismo
  compás (beat 3); en 2/4 (mismo `duration_qn`), corta justo en el
  downbeat del compás siguiente — comportamiento esperado, ya que 2 QN
  representan una fracción de compás distinta según el denominador.
- Transposición de acorde y de tonalidad confirmadas end-to-end contra
  `nikReaPitchLastSemitone` real (no solo `nikTranspose` aislado).
- Sin bugs de código encontrados en esta ronda — los resultados
  inesperados durante la sesión fueron todos error de playhead
  desalineado entre pasos de test, no de lógica.

**No probado todavía:** el sentinel `chord: null` (carry-over "apagado")
con datos reales — el sample hardcodeado no lo incluye.

---

## 13. Helper UI — `Nik_MusicState_Helper.lua` (sesión nueva, en progreso)

Panel nativo ReaImGui (mismo criterio que `Nik_ReaPitchBus_Knob.lua`),
alcance completo desde el arranque: las 4 piezas de datos (`harmony_data`,
`project_key`, `project_roles`, `cues_data`) en la misma iteración —no se
achicó a solo armonía como sugería el punto 3 original de la sección 8.

### 13.1. Estructura de datos en memoria

Arrays planos editables (no keyed-por-compás como el storage final) —
más simple para tablas ReaImGui por fila. La conversión al JSON keyed
por compás (formato ya cerrado en sección 4.2) se hace recién al guardar,
del lado Lua — el Helper arma el JSON, no asume que el cliente lo
reconstruya.

### 13.2. Layout: 4 tabs + captura de posición por cursor

`ImGui.BeginTabBar`: Tonalidad, Roles, Armonía, Cues. Readout de posición
del cursor de edición (compás + beat.centésimas) siempre visible arriba de
los tabs, recalculado cada frame vía `nikMusicStateCaptureCursorPosition()`
(sección 13.3). Botón "Usar cursor" por fila en Armonía/Cues (pendiente,
pasos 4-5) llena Compás+Beat automático — el usuario solo tipea
acorde/texto/roles.

**Navegación (Opción A, cerrada):** botones dedicados ◀▶ Compás / ◀▶
Marker moviendo el cursor de edición vía API — no atajos de teclado
(Opción B, descartada para esta iteración: requeriría confirmar que
ReaImGui captura teclas antes que el keyset global del usuario, y los
Command IDs de las acciones nativas correspondientes — sin testear,
no se asume). Pendiente de implementar, paso 6.

### 13.3. Captura de posición del cursor — validado con test real

Función `nikMusicStateCaptureCursorPosition()`, combina
`TimeMap2_timeToQN` + `TimeMap_QNToMeasures` + `TimeMap_GetMeasureInfo`.

**Gotcha confirmado con test real** (cursor en compás 8, 2/4→4/4,
posición 8.2.45 según transport de REAPER):
- `TimeMap_QNToMeasures(proj, qn)` devuelve `measure` **1-indexed**
  (coincide con el compás que muestra el ruler) — 3 retornos:
  `measure, qn_start, qn_end`.
- `TimeMap_GetMeasureInfo(proj, measure)` espera `measure` **0-indexed**
  — mismo patrón ya documentado para `measurepos` en la sección 5, pero
  confirmado acá como aplicable también a esta función (no se asume que
  se extiende a toda la API sin testear cada caso). Hay que restar 1 al
  valor devuelto por `QNToMeasures` antes de pasarlo a `GetMeasureInfo`.
- Fórmula de conversión QN↔beat.hundredths (ya validada del lado cliente,
  sección 12.2) confirmada también en esta dirección (posición → QN):
  compás 8, beat 2.45, denominador 4 → `qn_offset` esperado 1.45,
  calculado 1.445422 (diferencia = redondeo del display a centésimas).

Testeado y funcionando en 4/4, 2/4, y 6/8.

### 13.4. Bridge reusable — `_Shared/MusicStateBridge_common_logic.lua`

Extraído de `Nik_MusicState_PublishAll.lua` (que antes tenía el puente
`ProjExtState → ExtState` inline). Expone `bridgeKey(proj, key)` y
`bridgeAll(proj)`. Consumido por `PublishAll` y por el botón "Guardar y
Publicar" del Helper — un solo lugar de verdad para el puente, criterio
de `01_CONVENCIONES.md` sobre cuándo un módulo entra a `_Shared/`.

### 13.5. Gotcha crítico encontrado y corregido: bridge no limpiaba `ExtState` al fallar

**Síntoma:** un proyecto sin `project_key` guardado en `ProjExtState`
(tab nuevo sin datos, o proyecto que nunca se abrió con el Helper) reflejaba
en `GET/EXTSTATE/NikMusicState/project_key` el valor de **otro** proyecto
—el último que sí tuvo dato publicado exitosamente, sin relación con el
proyecto activo real.

**Causa:** `bridgeKey()` en su versión original, al no encontrar dato en
`ProjExtState` (`retval == 0`), simplemente no hacía nada — `return false,
nil` sin tocar `ExtState`. Como `ExtState` es un store **global** (a
diferencia de `ProjExtState`, que es por-proyecto), "no escribir nada" no
significa "vacío" — deja lo que haya quedado del último proyecto que sí
escribió ahí. Este bug también explica el caso reportado inicialmente
como "cambio de proyecto no se detecta" (sección 6) — la detección
funcionaba, el dato que traía estaba corrompido por herencia del proyecto
anterior.

**Fix:** `bridgeKey()` ahora llama `reaper.DeleteExtState(...)`
explícitamente cuando no hay dato en `ProjExtState`, en vez de dejar el
puente intacto.

**Validado con test real:** proyecto con dato guardado (recuerda entre
aperturas), proyecto sin `ProjExtState` (limpia a vacío), tab unsaved
(limpia a vacío), edición vía Helper en un proyecto → refleja correcto en
la URL de consulta. Los 4 casos correctos.

**Principio general (aplica a cualquier bridge similar futuro):** un
bridge hacia un store global nunca debe asumir que "no escribir" equivale
a "vacío" — tiene que manejar el caso ausente explícitamente.

### 13.6. Recarga automática al cambiar de project tab

El panel detecta cambio de proyecto activo comparando `reaper.
EnumProjects(-1)` (puntero) contra el último valor cacheado, en cada
frame del loop — no hay callback nativo de REAPER para "tab switch" en
ReaScript estándar, se resuelve por comparación continua (aceptable acá
porque el loop ya corre a frame rate mientras el panel está abierto,
distinto de un poll de fondo). Al detectar cambio, recarga `H` completo
desde `ProjExtState` del proyecto nuevo — **descarta sin avisar** cualquier
cambio no guardado en el proyecto anterior (default más seguro elegido a
propósito; un "¿guardar antes de cambiar?" queda pendiente, no bloqueante).
Mismo mecanismo resuelve gratis la carga inicial al abrir el panel (arranca
en `nil`, distinto a cualquier proyecto real).

### 13.7. Gotchas de ReaImGui encontrados en esta sesión

- **`ImGui_PushFont` requiere tamaño explícito como tercer argumento**
  en la versión de ReaImGui que trae REAPER 7.79 (`ctx, font, size`) —
  firma distinta a versiones más viejas documentadas en ejemplos online.
- **`ImGuiInputTextFlags_EnterReturnsTrue` cambia la semántica completa
  del valor de retorno**, no solo agrega Enter como trigger extra: sin la
  flag, `InputText` sincroniza el buffer devuelto en cada tecla; **con**
  la flag, solo sincroniza en el momento del Enter. Cualquier flujo que
  dependa del buffer fuera de ese instante (ej. un botón "Agregar" aparte)
  queda roto — el widget muestra el texto tipeado (estado interno propio),
  pero la variable Lua nunca se actualiza hasta el Enter.
- **`IsItemActive(ctx) and IsKeyPressed(...)` no detecta Enter en un
  InputText**: el ítem se desactiva en el mismo frame en que se presiona
  Enter, entonces para cuando se evalúa `IsItemActive` ya es `false`.
  `IsItemDeactivatedAfterEdit(ctx)` es el patrón correcto — dispara con
  Enter y también con cualquier pérdida de foco habiendo editado (Tab,
  click afuera), no distingue la causa. **Pendiente, no bloqueante:**
  hacer estricto el trigger de "Agregar" en Roles para que distinga Enter
  real de cualquier deactivation.

### 13.8. Tonalidad: elegir grafía explícita, no derivar por círculo de quintas

A diferencia de la transposición de acordes (sección 10.4, donde sí aplica
círculo de quintas porque la grafía se **calcula**), `project_key` es dato
de entrada directo — el usuario ya sabe si la canción está en Db o C#
(mismo semitono, tonalidades distintas en notación real). El combo de
tónica expone las 17 grafías posibles (12 naturales/sostenidos + 5
alternativas bemol) como opciones de texto explícitas, no un criterio
automático.

### 13.9. Pendiente — pasos 4 a 7

4. Tab Armonía: tabla + botón "Usar cursor" por fila.
5. Tab Cues: tabla + "Usar cursor" + "Capturar inicio/fin" para
   `duration_qn` + checkboxes de roles (contra la lista del tab Roles).
6. Navegación (Opción A, sección 13.2): botones ◀▶ Compás / ◀▶ Marker.
7. Carga inicial ya resuelta como side-effect de 13.6 — este punto del
   plan original queda absorbido, no hace falta paso aparte.

**Pendiente aparte, no bloqueante:** revisar por qué
`Nik_MusicState_PublishAll.lua` da la impresión de correr más seguido de
lo esperado para ser one-shot (mencionado en sesión, no investigado
todavía — sospecha: el trigger se dispara más seguido de lo pensado, no
que haya un loop residente real).