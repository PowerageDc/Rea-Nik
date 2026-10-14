# Feature — MusicState: módulos visuales compartidos

Módulos y CSS que consumen más de una UI de MusicState (instrumentista y
cantante). Lo lee quien toca la fila de sección, la cabecera, el estado
sin señal, o crea una UI nueva sobre estos bloques. Timing, polls y
posición efectiva: `musicstate_sync.md`. Pantallas: `musicstate_instrumentista.md`,
`musicstate_cantante.md`.

## 1. Inventario

| Módulo | Aporta | Lo usan |
|---|---|---|
| `ms-base.css` | paleta, dividers, glifos de tonalidad, componentes de la fila de sección, `is-stale` | instrumentista, cantante |
| `ms-header.js` | `nikMsHeaderRender()`: nombre de canción, tonalidad y tempo | instrumentista, cantante |
| `ms-section-row.js` | `nikMsSectionRowRender(screenJumped)`: fila prev/actual/next con animación | instrumentista, cantante |
| `ms-stale.js` | `nikMsUpdateStaleIndicator(screenEl)`; política en `musicstate_sync.md` §9 | instrumentista, cantante |

Dependen de `ms-section.js`, `ms-tempo.js` y `ms-dispatch.js`
(`musicstate_sync.md`). `ms-beat.js` no es compartido: solo instrumentista.

## 2. Cabecera (`ms-header.js`)

- **IDs de DOM exigidos en el shell:** `msSongName`, `msTempo`,
  `msKeyTonicText`.
- Nombre de canción: `nikCurrentProjectName` sin `.rpp`. Sin `.rpp` (pestaña
  sin guardar) se muestra `U+00A0`: un espacio común colapsa con
  `white-space: nowrap` y la fila cambiaría de alto.
- Tempo: equivalente (tempo del mapa × playrate), redondeado, `NNN BPM`.
- Tonalidad: `♪` + tónica con alteración; sufijo `m` si es menor, nada si
  es mayor. Viene transpuesta (`nikMusicStateCurrentProjectKey()`).

## 3. Fila de sección (`ms-section-row.js`)

**IDs de DOM exigidos en el shell:** `msSectionRow`, `msSectionPrev`,
`msSection`, `msSectionNext`, `msSectionNextFill`.

**Contenido.** Previa, actual (color de familia de
`nikResolveMarkerDisplay()`) y próxima. Previa y próxima sin dato quedan
vacías, no `—`. El actual sin sección (cursor antes de la primera, tab
vacío) muestra `U+00A0`: el actual sostiene la altura de línea de la fila.
El `font-size` de `.ms-section-fill` debe coincidir con el de
`.ms-section-adj`.

**Estado y animación.** Triple prev/actual/next con identidad
`id|displayName` (los ids solos no sirven: proyectos distintos los
comparten). Por tick:

- Triple igual: no se anima. Si falta poco para la próxima sección
  (`NIK_MS_SECTION_PRELUDE_SEC` = 2 s, definida en `ms-section-row.js`) y hay reproducción, se arma el preludio
  de next (fill de `msSectionNextFill`).
- Avance de uno (`prevId === old.curId`, `curId === old.nextId`,
  `curId !== null`) y la UI no hizo jump en ese tick: cruce animado. FLIP
  con escala uniforme por alto y alineación por centros
  (`transform-origin: 50% 50%`; técnica en `01_CONVENCIONES.md`);
  `nikMsFlipTransform` devuelve `""` si algún rect mide alto 0. El prev
  saliente es un fantasma que se achica a `scale(0.7)` mientras se
  desvanece; el actual que pasa a prev transiciona color y opacidad.
- Cualquier otro caso (seek, retroceso, cambio de proyecto, lista de
  markers reemplazada): fade (`is-jumping`). Jumps consecutivos se
  fusionan si llegan antes de terminar el fade-out (150 ms).
- El preludio corre solo en reproducción.

**Orden de render.** La UI renderiza su contenido principal (tira de
acordes o reel de letra) **antes** que la fila de sección y le pasa su flag
de jump como `screenJumped` (`nikInstrumentistaChordLastRenderJumped`,
`nikCantanteReel.jumped`). Sin ese orden el flag llega un tick tarde.
Si no hay armonía cargada el flag de instrumentista queda en `false` y un
seek que cruce una sola sección se anima igual.

**Posición del contenedor.** `nikMsBuildGhost` posiciona el fantasma en
absoluto contra `#msSectionRow`: `ms-base.css` fija
`.ms-section-row { position: relative }` (el prompter lo pisa con
`absolute`). Con `static` el fantasma aparece arriba de la página.

## 4. Estado sin señal

`is-stale` (sobre `.ms-screen`, `ms-base.css`): atenúa el bloque superior
y la fila de sección, y muestra el cartel "SIN SEÑAL". Cuándo se marca y
cómo se recupera: `musicstate_sync.md` §9. El contenido principal (tira de
acordes, reel) queda fuera del atenuado cuando su fade de salto usa
`opacity`.

## 5. Reglas para animar y deduplicar render

- **Texto que cambia de posición y tamaño:** FLIP con escala uniforme y
  alineación por centros, nunca `scaleX`/`scaleY` por separado
  (`01_CONVENCIONES.md`). Un reel con posiciones absolutas y composición
  uniforme no usa FLIP (`musicstate_cantante.md` §4.1).
- **Keys de "último evento"** (dedupe de render): deben incluir todo lo que
  determina el render y resetearse cuando el consumidor deja de correr
  (barra de pulso, preludio, barrido de lyrics al detener el transporte);
  si no, el siguiente arranque cree que el evento ya pasó.
- **`null === null` en identidades:** un triple vacío coincide con el
  siguiente vacío y parece un "avance de uno". Un shift exige
  `curId !== null`.
- **Clonado de nodos con `id`:** regla general en `01_CONVENCIONES.md`.

## 6. Crear una UI nueva

Usar los ids de §2 y §3, cargar los módulos en el orden de
`musicstate_sync.md` §3 y respetar §3 (orden de render y `screenJumped`).
