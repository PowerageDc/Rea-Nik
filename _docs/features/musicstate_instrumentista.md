# Feature — UI de Instrumentista (MusicState)

Doc de diseño, cerrado como cimiento antes de implementación. Primera de
las UIs separadas por perfil planteadas en `IMPL_MusicState.md` (sección
8, punto 4). Perfil cubierto acá: instrumentistas en general (guitarras,
teclados, bajo, etc.) — no cantantes ni panel coordinador/Helper, que
quedan como perfiles futuros con el mismo esquema de archivos.

Convenciones generales (nomenclatura de scripts, estructura de carpetas,
modo de trabajo) en `01_CONVENCIONES.md` y `00_CONTEXTO_GENERAL.md` —
este doc no las duplica, solo agrega lo específico del perfil.

## 1. Objetivo

Pantalla de celular para instrumentista, standalone (no parte del
control remoto general), que muestra en tiempo real: acorde actual y
próximo(s), sección actual de la canción, tonalidad, tempo, nombre de
canción e indicaciones (`cues`) filtradas por el rol del instrumentista.
Pensada para mirarse de reojo mientras se toca — no para interacción
táctil continua.

Fuente de verdad de los datos musicales: `IMPL_MusicState.md` (sección
cerrada, no re-abierta acá salvo lo puntual que se detalla en §2).

## 2. Fuentes de datos y reuso

Todos los datos necesarios ya están resueltos del lado REAPER/cliente —
**no hace falta ningún script Lua nuevo** para esta UI. Se resuelve
enteramente consumiendo mecanismos ya existentes.

| Dato | Fuente | Notas |
|---|---|---|
| Acorde actual / próximo | `nikMusicStateCurrentChord` / `nikMusicStateNextChord` / `nikMusicStateChordWindow` (`core/music-state.js`) | Reuso directo |
| Transposición en vivo | `nikMusicStateTransposeChordIfNeeded` + `nikTranspose` (`core/music-transpose.js`) | Necesita que `ms-dispatch.js` escuche también la key de semitonos de ReaPitch (hoy publicada vía `Nik_RemoteState_Poll`, `NIK_SLOW_POLL`) |
| Tonalidad | `nikMusicStateCurrentProjectKey` | Formato `{tonic, mode}` |
| Indicaciones por rol | `nikMusicStateActiveCues` | Soporta `"todos"` + rol específico |
| Sección actual | `g_markers` (global nativo de `main.js`, **sin** Lua propio) + mismo criterio que `nikMarkerBrowserFindCurrentId(pos)` ("último marker con posición `<=` actual") | Ordenar `g_markers` una vez por conexión/cambio de proyecto, no depender del ciclo de vida del popup de markers |
| Nombre/color de sección | `nikResolveMarkerDisplay()` (`markers/markers.js`) | Reuso directo — mismo sistema de color por familia, ya auditado WCAG AA, usado en popup y transporte |
| Tempo vigente | Mismo patrón que `nikPlayrateTempoAt(positionSeconds)` (`modals/playrate/playrate.js`): lookup "último tempo con `pos <=` posición actual" sobre `tempo_map` | **No** se reusa el archivo (mezcla DOM del popup) — se **duplica la función pura** en `ms-tempo.js`. Deuda de duplicación controlada, candidato a extraer a módulo compartido si `playrate.js` se refactoriza |
| Nombre de canción | Nombre de proyecto activo, mismo handler `active_project_name` que ya escucha `wwr-dispatch.js` en control remoto | Recortar `.rpp` del lado cliente (`replace(/\.rpp$/i, "")`); no confirmado el string exacto que reporta REAPER para proyecto sin guardar — no debería romper el replace, pero no asumir que siempre hay extensión |

Todos los triggers son **on-demand** (boot, conexión, cambio de
proyecto/tab) o van colgados del poll rápido de `TRANSPORT` ya
existente (10ms) para los valores derivados de posición — mismo
principio ya aplicado en Playrate: nada nuevo entra al loop rápido del
lado Lua, el costo extra es cliente (lookup sobre arrays en memoria).

## 3. Arquitectura de archivos

```
reaper_www_root/
├── nsaudio_remote_control.html              ← existente, sin tocar
├── nsaudio_musicstate_instrumentista.html   ← shell nuevo
├── config.js                                 ← reusado tal cual
├── config.local.js                           ← reusado tal cual, IMPRESCINDIBLE:
│                                                sin este script los Command IDs
│                                                _RS de config.js quedan con el
│                                                default (de otra PC) y fallan en
│                                                silencio, sin error en consola
├── core/ , markers/ , modals/                ← existentes, sin tocar
└── musicstate-ui/
    ├── shared/
    │   ├── ms-dispatch.js    ← dispatcher propio y chico (TRANSPORT,
    │   │                        EXTSTATE de NikMusicState/*, tempo_map,
    │   │                        timesig_map, semitono ReaPitch,
    │   │                        active_project_name)
    │   ├── ms-tempo.js       ← lookup de tempo puro (portado de playrate.js)
    │   └── ms-section.js     ← sección actual sobre g_markers
    └── instrumentista/
        ├── instrumentista.js   ← lógica de UI del perfil (layout switch, render)
        └── instrumentista.css  ← estilos propios del perfil
```

### Decisión clave: dispatcher propio, no reuso de `wwr-dispatch.js`

`wwr-dispatch.js` tiene `case`s sin guard `if (elemento) {...}` en
algunos puntos (gotcha ya confirmado en el dominio de markers) — asume
que ciertos IDs del DOM de control remoto existen. Esta UI no tiene
faders/tracks/tabs, así que reusarlo completo arriesga fallos silenciosos.
Se optó por un dispatcher dedicado y más chico, que solo atiende lo que
la tabla de §2 necesita.

### Reuso confirmado tal cual (sin fork)

`core/music-state.js`, `core/music-transpose.js`, `markers/markers.js`,
`config.js` (Command IDs, fuente única — no forkear para evitar
divergencia con control remoto), `core/utils.js` (`nikLerpColor` —
dependencia real de `markers.js`, no listada en la primera pasada de este
doc; confirmada al integrar `ms-section.js`).

## 4. Selector de rol

- Poblado desde `project_roles` (+ `"todos"` implícito, ver
  `IMPL_MusicState.md` §11).
- **Persistencia local** (`localStorage`, por dispositivo — no
  `tab-ui-memory.js`, que es por proyecto/tab de REAPER). El eje acá es
  "de quién es este celular", algo que no cambia entre proyectos.
- Editable en cualquier momento; el último valor seleccionado pisa el
  storage.

## 5. Modelo de datos en pantalla / jerarquía visual

- **Primario**: acorde actual.
- **Secundario**: sección actual (destacada con el color categorizado
  de `nikResolveMarkerDisplay()`, sin inventar paleta nueva), próximo(s)
  acorde(s) con **jerarquía tipográfica decreciente** por cercanía (no
  espaciado proporcional al tiempo — más simple de leer de un vistazo).
- **Terciaria, fila 1**: rol / tonalidad / tempo. Tonalidad compacta
  (raíz + modo abreviado, ej. `G maj`, con ícono de referencia
  adelante) — evita ambigüedad con notación de acorde (puede coincidir
  literalmente, ej. tonalidad `G` + acorde `G` en la progresión).
- **Terciaria, fila 2**: nombre de canción (chico, tenue, ancho
  completo, `text-overflow: ellipsis`). Separado de la fila 1 a
  propósito — es un dato de consulta ocasional (útil cuando el
  coordinador cambia de proyecto en ensayo), no debe competir por
  espacio ni prioridad con rol/tonalidad/tempo.
- **Banda de cue**: condicional — solo ocupa espacio si hay una
  indicación activa para el rol seleccionado.

Modo de refresco: automático a medida que avanza la posición, sin
gesto táctil de scroll (quien toca no puede interactuar con el celular
en vivo).

## 6. Layouts

Conmutación por **proporción de viewport** (ancho/alto, no
`orientation` de dispositivo — más robusto ante tablet o ventana de
escritorio) con **debounce 150–200ms** antes de conmutar, para evitar
flicker si el celular queda en ángulo intermedio (ej. apoyado en un
atril).

### Vertical (portrait)

Columna única: fila terciaria 1 → fila terciaria 2 (canción) → sección
(badge coloreado) → acorde actual (grande) → próximo → banda de cue
condicional.

**Pendiente de verificar contra dispositivo real** (ej. iPhone): si
entra holgado un acorde previo y/o un segundo próximo en tamaño chico,
mismo criterio que horizontal. Slots armados como bloques
independientes en CSS (mostrar/ocultar sin rehacer layout) para decidir
esto empíricamente en implementación.

### Horizontal (landscape)

Fila única de 4 slots: `anterior · ACTUAL · próximo1 · próximo2`,
tamaño decreciente desde el centro. Banda terciaria arriba (más ancho
disponible, no debería apretarse). Banda de cue condicional abajo.

**A confirmar en implementación**: si conviene mantener las dos filas
de banda terciaria igual que en vertical (consistencia) o aprovechar
el ancho extra para una sola fila con los 4 datos (rol/tonalidad/
tempo/canción).

## 7. Fuera de alcance de esta primera versión

- Modo de exploración manual (scroll táctil de acordes pasados/futuros
  sin estar en reproducción) — posible extensión futura, no el modo
  principal.
- Perfiles de cantante y coordinador/Helper — mismo esquema de
  archivos (`musicstate-ui/<perfil>/`), a diseñar en sesiones propias.
- Todo lo ya declarado fuera de alcance en `SPEC` §18 / cerrado en
  `IMPL_MusicState.md` (Regions, escalas, roman numerals, lyrics, edición
  de armonía desde el celular, múltiples acordes por beat más allá de
  lo ya soportado por `nikMusicStateChordWindow`).

## 8. Pendientes explícitos (no bloqueantes)

- Cantidad final de slots de acorde en layout vertical — contra
  dispositivo real.
- String exacto reportado por REAPER para proyecto sin guardar (afecta
  el recorte de `.rpp` del nombre de canción, caso borde no confirmado).
- Estructura final de banda terciaria en horizontal (una fila vs. dos).
- Extraer `ms-tempo.js` a módulo compartido con `playrate.js` si ese
  archivo se refactoriza en el futuro (hoy: duplicación controlada).
- **RESUELTO** (ver sección 9): `harmony_data`/`project_key`/
  `project_roles`/`cues_data` ahora se refrescan solos, automático, vía
  `publish_version` (contador puenteado igual que las otras 4 keys) —
  sin necesidad de gesto de UI.
- Gesto de refresh manual para `tempo_map`/`timesig_map` (mapa de tempo/
  compás) editados en vivo mientras la UI ya está abierta, sin cambio de
  proyecto de por medio — a diferencia de las 4 keys de arriba, estos dos
  no pasan por el Bridge/Helper (vienen de
  `Nik_Playrate_ReadTempoMap.lua`), así que `publish_version` no los
  cubre. Playrate resuelve esto reusando la apertura del popup como
  gancho; esta UI no tiene popup (pantalla completa), sigue faltando
  decidir qué gesto lo dispara — caso de borde chico (editar time
  signature markers en vivo durante un ensayo es raro), no bloqueante.
- Semitono `"mixed"` del Stem Bus (ReaPitch): el manejo está escrito
  (mismo sentinel que `reapitch.js`) pero no probado contra datos reales
  — solo se vio `"none"` y valores numéricos en sesión.
- Mitigación de carrera en `nikMsResetProjectState`/re-pedido on-demand
  (ver sección 9): si el bug de datos colgados de un proyecto anterior
  reaparece pese al debounce de 400ms, hace falta un token de generación
  — deliberadamente no implementado todavía, ver sección 9 para el
  detalle.

## 9. Estado de implementación — `shared/` (dispatcher, tempo, sección)

Sesión de implementación + validación contra REAPER real. Los 3 archivos
de `musicstate-ui/shared/` (ver arquitectura, sección 3) están escritos y
probados end-to-end con una herramienta de test dedicada
(`nsaudio_musicstate_test.html`, en la raíz de `reaper_www_root/` junto a
`nsaudio_remote_control.html` — panel de debug crudo, no es parte de la
UI final, se mantiene como herramienta de diagnóstico reusable para
futuras sesiones de este perfil o de otros perfiles del mismo esquema).

### Decisiones/fixes que salieron en el camino (no previstos en el diseño original)

- **Reset de estado por-proyecto** (`nikMsResetProjectState()`, en
  `ms-dispatch.js`): al detectar cambio de `active_project_name`, se
  limpia todo el estado cacheado por-proyecto (armonía, cues, tonalidad,
  roles, tempo map, markers, semitono) ANTES de re-pedirlo. Necesario
  porque el puente Lua no tiene nada que puentear si el proyecto nuevo no
  tiene `ProjExtState` propio (ej. pestaña "sin guardar") — sin este
  reset, quedaban colgados los valores del proyecto anterior.
- **Mitigación de carrera**: además del pedido inmediato al detectar
  cambio de proyecto, se repite el mismo pedido 400ms después
  (`window.setTimeout`). Causa raíz: una respuesta on-demand rezagada del
  proyecto anterior puede llegar DESPUÉS del reset y repoblar con datos
  viejos — el protocolo no etiqueta las respuestas con a qué proyecto
  correspondían. La mitigación asume orden de llegada FIFO del server de
  REAPER (no confirmado formalmente) — barata y suficiente por ahora, no
  bloqueante. Si reaparece el bug de datos colgados pese a esto, la
  solución robusta (no implementada) es un token de generación por
  cambio de proyecto.
- **Fix en `Nik_MusicState_PublishAll.lua`** (fuera de esta UI, pero
  descubierto por ella): el script seguía escribiendo `sample_harmony`/
  `sample_cues` hardcodeados sobre `ProjExtState` en cada corrida,
  pisando los datos reales que el Helper ya había guardado — TODO viejo
  de la sección 7 del `IMPL_MusicState.md`, nunca cerrado del todo (sí se
  había cerrado para `project_key`/`project_roles`, no para
  `harmony_data`/`cues_data`). El script quedó reducido a un wrapper de
  `Bridge.bridgeAll(proj)`, sin generar ni escribir ningún dato — el
  Helper es la única fuente de verdad de las 4 keys.

### Validado en sesión contra REAPER real

`TRANSPORT` en vivo, reset/cambio de proyecto (incluido el caso de
pestaña "sin guardar"), semitono ReaPitch numérico + transposición de
acordes, tempo map (BPM vigente por posición), markers → sección actual
+ color de familia (incluida cadena `x2`/`x3...`, confirmada con
proyecto real — los hex cambian correctamente eslabón a eslabón),
armonía (acorde actual/próximo), tonalidad, roles del proyecto, cues
(con y sin filtro de rol, sentinel `"todos"` confirmado).

### No probado explícitamente (no bloqueante, ver sección 8)

Semitono `"mixed"`; refresco en caliente de `harmony_data`/`project_key`
tras editarlos en el Helper sin recargar la página (se asume igual a
`cues_data`, que sí se confirmó sin refresco automático, por compartir
el mismo mecanismo on-demand — no verificado explícito).

### Actualización — refresco automático vía `publish_version`

Implementado y confirmado en REAPER real, sesión posterior a la
validación inicial de arriba: `Nik_MusicState_Helper.lua` incrementa un
contador (`H.publish_version`, cargado desde `ProjExtState` con default
`0`) en cada `nikMusicStateSaveAndPublish()`, lo guarda y lo puentea
igual que las otras 4 keys (`publish_version` sumado a
`Bridge.KEYS` en `MusicStateBridge_common_logic.lua` —
`Nik_MusicState_PublishAll.lua` no necesitó ningún cambio, ya itera
`Bridge.KEYS` genérico). Del lado cliente, `ms-dispatch.js` cachea el
último valor visto (`nikMsLastKnownPublishVersion`, reseteado a `null`
en cada cambio de proyecto para que la comparación nunca cruce entre
proyectos distintos) y dispara `nikMusicStateRequestAll()` solo cuando
cambia estando en el mismo proyecto — no en la primera vez que se ve un
valor tras cambiar de proyecto (ese caso ya lo cubre el reset de
proyecto por su cuenta). Resuelve, de forma automática y sin gesto de
UI, el pendiente de "harmony_data/project_key/project_roles/cues_data no
se refrescan solos" que había quedado abierto en la sección 8 — sí queda
pendiente el caso análogo para `tempo_map`/`timesig_map` (ver sección 8,
no cubierto por este mecanismo).

**Pendiente de sync de doc, no bloqueante**: `IMPL_MusicState.md`
secciones 10-11 listan las 4 keys de `Bridge.KEYS` sin `publish_version`
— desactualizado desde este cambio, a consolidar en sesión aparte (ver
convención de `00_CONTEXTO_GENERAL.md`).
