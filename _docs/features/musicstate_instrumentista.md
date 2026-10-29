# Feature — MusicState: UI de instrumentista (prompter)

Pantalla de celular standalone (no es parte del control remoto general)
que muestra casi en tiempo real: acorde actual y vecinos, sección (con la
previa y la próxima), tonalidad, tempo, nombre de canción e indicaciones
(`cues`) filtradas por rol. Pensada para mirarse de reojo mientras se
toca; no requiere interacción táctil. Cubre instrumentistas en general
(guitarra, teclados, bajo, etc.).

Fuera de este doc: timing, polls, ancla, ciclo de proyecto
(`musicstate_sync.md`); módulos compartidos con cantante
(`musicstate_shared_ui.md`); consultas y transposición
(`musicstate_client.md`); formato de datos (`musicstate_data_model.md`);
pruebas (`musicstate_testing.md`). Convenciones generales en
`01_CONVENCIONES.md`.

Los músicos se conectan por Wi-Fi al servidor web embebido de REAPER
(`reaper_www_root`). Red de la sala: `07_RED_SALA_ENSAYO.md`.

## 1. Archivos propios

```
web/
├── nsaudio_prompter.html                  shell
├── nsaudio_musicstate_test.html           panel de debug crudo (diagnóstico)
└── musicstate-ui/
    ├── shared/ms-beat.js                  pulso por compás + distancia al próximo evento de armonía
    └── instrumentista/
        ├── instrumentista.js              bootstrap de polls + render
        └── instrumentista.css             estilos del perfil
```

Orden de carga y módulos compartidos: `musicstate_sync.md` §3 (esta UI
carga `ms-beat.js`). El shell llama `nikInstrumentistaInit()` (polls y
pedidos on-demand, sin IDs de DOM) y
`nikInstrumentistaStartRenderLoop(50)`.

## 2. Pantalla

Layout vertical estático. De arriba hacia abajo:

- **Bloque superior:** nombre de canción; fila con rol, tempo y tonalidad
  (formatos: `musicstate_shared_ui.md` §2).
- **Fila de sección:** previa, actual y próxima, animada
  (`musicstate_shared_ui.md` §3). El render de la tira de acordes corre
  **antes** y le pasa `nikInstrumentistaChordLastRenderJumped`.
- **Tira de acordes:** 5 slots (offsets -2..2,
  `nikMusicStateChordWindow(2,2)`), jerarquía tipográfica decreciente
  desde el actual.
- **Indicador de pulso:** debajo de la tira (§3).
- **Banda de cue:** visible solo si hay indicación activa para el rol;
  varias cues activas se unen con ` · `.

**Animación de la tira** (`nikInstrumentistaShiftChordSlots`, técnica
FLIP de `01_CONVENCIONES.md`; anima solo `transform`/`opacity`):

- Estructura igual: se actualiza el texto en el lugar (cambio de
  transposición en caliente).
- Ventana desplazada ±1: se reetiquetan los `data-offset` de los nodos
  existentes; entran/salen por offsets fantasma ±3.
- Cualquier otro caso (salto de posición): se reconstruye con fade
  (`is-jumping`).

**Rol.** Vive en `localStorage` (`nikInstrumentistaRole`), por
dispositivo (el eje es "de quién es este celular", no el proyecto, por eso
no se usa `tab-ui-memory.js`). `"todos"` es válido siempre; sin rol se
muestra `(sin rol)`. Para filtrar cues, `"todos"` o sin rol equivalen a no
filtrar. No hay selector en la UI: se setea por consola con
`nikInstrumentistaSetRole("...")`.

**Landscape.** Activo por proporción de viewport
(`@media (min-aspect-ratio: 1/1)`, no por `orientation`), solo CSS: mismo
HTML y JS, misma tira de 5 slots. `.ms-top-block { display: contents; }`
permite ubicar por separado nombre de canción y fila rol/tempo/tonalidad.
Variables recalibradas para el alto disponible: `--chord-h`,
`--chord-divider-gap`, `--ms-song-to-divider-gap`,
`--ms-divider-to-row-gap`, `--chord-beat-gap` y los tamaños de fuente de
nombre de canción, fila terciaria y tonalidad. Confirmado en Moto Edge 20
Lite (~969×539 con la barra del navegador oculta).
`--chord-divider-gap: clamp(36px, 3vh, 20px)` tiene el mínimo por encima
del máximo: vale siempre 36px (no escala con el alto).

## 3. Indicador de pulso

Puntos por pulso del compás vigente + barra de progreso hacia el próximo
evento de armonía. Cálculo puro en `ms-beat.js` (`nikBeat`, wrapper de
objeto único, `01_CONVENCIONES.md`); detección de cruce y DOM en
`nikInstrumentistaRenderBeat()`, desde el mismo render loop de 50 ms.

**Dos posiciones efectivas distintas:**

- **Dots:** `nikBeat.currentPos()`, misma fórmula que
  `nikMusicStateCurrentPos()` pero con `nikBeat.LATENCY_SEC` (0.4) en vez
  de `nikMusicStateLookaheadSec` (valores en `musicstate_sync.md` §6).
  `LATENCY_SEC` es empírico (iguala la sensación de sincronía contra la
  tira y el audio), no una latencia medida. Hoy coincide con el lookahead.
- **Barra:** `nikMusicStateCurrentPos()` sin modificar: debe coincidir con
  el instante exacto en que la tira shiftea.

**Pulsos por compás** (`nikBeat.pulsesInBar(num, den)`): simple (den=4)
un pulso por unidad del denominador; compuesto (den=8, num múltiplo de 3,
num>3) agrupa de a 3 corcheas (6/8→2, 12/8→4). No cubre den=2 ni den=8 no
compuesto (3/8): sin confirmar contra un caso real. El timesig map se
relee en cada render (`nikMusicStateTimesigAt(bar)`) para seguir cambios de
compás a mitad de canción (4/4→2/4→4/4).

**Key de pulso** (`nikInstrumentistaBeatLastKey`): `compás_pulso_cantidad`.
Incluir la cantidad reconstruye los dots cuando cambia la métrica con el
cursor quieto (ej.: tab cuyo compás 1 es 2/4 con el anterior en 4/4).

**Fill de la barra (una vez por evento):** `RenderBeat` compara la key del
evento de armonía vigente (`bar_qn_offset`, igual que
`nikInstrumentistaChordKey` de la tira) contra la última vista. Al cruzar,
`nikBeat.secUntilNextChordEvent()` calcula la duración **una sola vez**
(`beats restantes × 60 / bpm / playrate`; recalcular por render provocaría
tirones porque cada ancla nueva corrige la estimación) y
`nikInstrumentistaStartChordRing()` dispara una transición CSS
(`transform: scaleX()`). Tras un acorde anticipado no hay evento virtual
en el tiempo 1 del compás siguiente (`musicstate_client.md` §1.2): la
barra cruza el barline sin reiniciarse y llena hasta el próximo evento o
carry.

**Gate de `stopped`:** los dots no animan en el tiempo; la barra sí.
`RenderBeat` corta y resetea la barra
(`nikInstrumentistaResetBeatProgress()`, sin transición) apenas
`nikMusicStateIsPlaying()` es falso, antes de mirar el evento, y pone
`nikInstrumentistaChordEventLastKey` en `null` (si no, al reanudar sobre el
mismo evento la barra no arranca hasta el siguiente). Regla general en
`musicstate_shared_ui.md` §5. Los dots desfasados con mapas de tempo
extensos: `musicstate_sync.md` §14.

## 4. Globales propias

Prefijo `nikInstrumentista*` en `instrumentista.js` (estado propio, no
wrapper). El contrato de las globales compartidas está en
`musicstate_sync.md` §12.

| Nombre | Rol |
|---|---|
| `nikInstrumentistaBeatLastKey` | key del último pulso marcado (§3) |
| `nikInstrumentistaChordEventLastKey` | key del evento de armonía vigente; `null` al detener |
| `nikInstrumentistaBeatDotCount` | dots dibujados; se repuebla solo si cambia (4↔2) |
| `nikInstrumentistaBeatProgressFilling` | la barra está en un fill (para resetear al detener) |
| `nikInstrumentistaChordLastRenderJumped` | `true` si en este tick la tira hizo jump; lo consume la fila de sección |
| `nikInstrumentistaResetSectionFill()` | resetea sin transición el fill de preludio de next |
| `nikInstrumentistaSetRole(role)` / `nikInstrumentistaRole` | rol (§2) |
| `nikBeat.LATENCY_SEC` | latencia del pulso (§3) |

## 5. Pendientes

Ninguno bloqueante.

- Selector de rol en la UI.
- Extraer la tira de acordes (`nikInstrumentistaRenderChordStrip`,
  `ShiftChordSlots` y su estado) a `shared/`: la usaría el control remoto
  y, a futuro, la UI de cantante si el cantante también toca. A resolver:
  ids de DOM fijos y el flag `ChordLastRenderJumped`.
- Landscape: validar en pantallas más chicas que la probada (no se pudo
  emular un viewport landscape más chico en DevTools).
- Cantidad de slots de acorde en vertical, a validar en dispositivo real.
- Opcional: tira de 4 slots para landscape (`anterior · ACTUAL · próximo1
  · próximo2`, con debounce de 150–200 ms si implica cambios de estructura
  por JS).
- Pulsos para den=2 y den=8 no compuesto (§3).
- Acorde anticipado seguido de un evento propio en el compás siguiente,
  más allá del tiempo 1 (ej. `G` en 2:3.5 y `Am` en 4:3.0): los compases 3
  y 4 quedan sin marca de `G` en la tira. El 3 por la supresión del carry
  tras el anticipo, y el 4 porque el carry solo se inserta en compases
  intermedios sin evento, no en uno con evento propio. Los pulsos y la
  barra de progreso indican la situación. Workaround: escribir el `G`
  como evento explícito en `qn_offset` 0 del compás donde se lo quiera
  ver. Decidir tras usarlo en un ensayo; el cambio de fondo sería
  insertar carry en el offset 0 de compases cuyo primer evento es
  posterior, lo que también afecta casos sin anticipo.
- Limpieza de datos al cerrar un proyecto o tab "sin guardar": no se pudo
  reproducir tras los cambios del cambio de proyecto (`musicstate_sync.md`
  §11). Cerrar el ítem si no reaparece. El literal de REAPER para un
  proyecto sin guardar es `"(sin guardar)"` (REAPER en español); el
  criterio de nombre vacío no depende de él (se basa en `.rpp`).

Timing, lookahead, datos parciales al cambiar de proyecto y demás
pendientes del motor: `musicstate_sync.md` §14.

**Fuera de alcance:** exploración manual con scroll táctil de acordes
pasados o futuros; lo declarado fuera de alcance en `SPEC` §18 (Regions,
escalas, roman numerals, edición de armonía desde el celular). El perfil
de coordinador hoy es el control remoto general; el Helper
(`musicstate_helper.md`) es el panel de carga, no una UI de coordinador.
