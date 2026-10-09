# Feature — MusicState: UI de cantante (layout, módulos y decisiones)

**Doc en construcción.** Es el punto de entrada de la UI de cantante
(`musicstate-ui/cantante/`), paralelo a `musicstate_instrumentista.md`. Lo que
**no** vive acá: el contrato de datos de la letra y su estado general están en
`musicstate_lyrics.md`; la API de consultas, en `musicstate_client.md` §1.6;
el modelo de datos, en `musicstate_data_model.md` §4.7.

## 1. Estado

| Pieza | Estado |
|---|---|
| Módulos compartidos extraídos del prompter (`ms-stale.js`, `ms-section-row.js`, `ms-header.js`, `ms-base.css`) | Hecho; prompter verificado sin cambios de comportamiento |
| Shell estático y layout (`nsaudio_cantante.html`, `cantante.css`) | Hecho; validado en DevTools (modo dispositivo) y en Android (Fully Kiosk y Chrome con barra de direcciones) |
| Cabecera (nombre, tonalidad transpuesta, tempo) y fila de sección | Funcionando en cantante |
| Medición del escenario (cuántos slots entran, foco) | Pendiente (paso 3c, §4.2) |
| Reel de letra (estados, FLIP, barrido de proximidad) | Pendiente (paso 4, §4) |
| Banda de cues | Altura reservada (1 renglón), sin cablear (§6) |
| Validación en iPhone (comportamiento de `100dvh` con la barra de Safari) | Pendiente, en sala |

## 2. Archivos y módulos consumidos

- `nsaudio_cantante.html` — shell: columna de bloques y orden de carga.
- `musicstate-ui/cantante/cantante.css` — layout propio del perfil.
- `musicstate-ui/cantante/cantante.js` — bootstrap, polls, render loop, offset superior y panel de debug temporal.

Del código compartido consume:

| Módulo | Aporta | Lo usa también |
|---|---|---|
| `ms-base.css` | Paleta, dividers, glifos de tonalidad, componentes de la fila de sección, `is-stale` | instrumentista |
| `ms-header.js` | `nikMsHeaderRender()` (nombre, tonalidad, tempo) | instrumentista |
| `ms-section-row.js` | `nikMsSectionRowRender(screenJumped)`: fila prev/actual/next con FLIP, preludio y jump | instrumentista |
| `ms-stale.js` | `nikMsUpdateStaleIndicator(screenEl)`: clase `is-stale` y tope de `g_wwr_errcnt` | instrumentista |
| `ms-section.js`, `ms-tempo.js`, `ms-dispatch.js`, `core/music-state.js` | Posición efectiva, secciones, tempo, polls, consultas de lyrics | instrumentista |

Orden de carga del shell: `main.js`, `config.js`, `config.local.js` (opcional),
`core/utils.js`, `markers/markers.js`, `core/music-transpose.js`,
`core/music-state.js`, `ms-tempo.js`, `ms-section.js`, `ms-section-row.js`,
`ms-header.js`, `ms-stale.js`, `ms-dispatch.js`, `cantante.js`. (`ms-beat.js`
no se carga: el pulso depende de cómo se sienta el preludio de la línea.)

El poll lento de cantante pide `active_project_name`, `reapitch_semitone`
(solo para la tonalidad transpuesta; la letra no se transpone), `playrate` y
`lyrics_version`.

## 3. Layout

Por qué no se reusó el layout del prompter: ahí `.ms-screen` mide `100vh` y todo
va absoluto anclado a `top: 50%`. En iOS Safari `100vh` es el viewport grande
(sin descontar la barra), así que el 50% cae por debajo del centro visible
(hipótesis, pendiente de validar en iPhone). Además los bloques absolutos no se
conocen entre sí y los gaps mezclan px fijos con unidades de viewport.

Cantante es una **columna en flujo** que llena el viewport visible:

```
[offset superior]   safe-area + --cn-top-offset
nombre de canción
─── divider
tonalidad | tempo
─── divider
sección prev / actual / next
ESCENARIO           (flex 1 1 0: todo lo que sobra)
─── divider
banda de cues       (altura reservada siempre: 1 renglón)
```

- **Unidad `--u`:** ~1% del lado corto del viewport visible
  (`min(1vw, 1dvh)`, con `1vmin` de fallback vía `@supports`). Fuentes y gaps
  salen de `calc(var(--u) * n)`; no hay px sueltos.
- **Alto:** `100vh` con `100dvh` encima (descuenta la barra dinámica) y
  `viewport-fit=cover` con safe areas en los paddings.
- **Dividers:** elementos del flujo, nunca absolutos; su espacio es `--cn-gap`
  a ambos lados.
- **Offset superior:** `?top=24` (px, tope 200) separa el título de la barra del
  navegador; se guarda en `localStorage` del dispositivo; `?top=0` lo borra.
  Lo aplica `nikCantanteApplyTopOffset()`.
- **Landscape** (`min-aspect-ratio: 1/1`): nombre a la izquierda y
  tonalidad | tempo a la derecha en una sola fila; se oculta el divider
  intermedio.
- **Sección:** prev y next más chicos que en el prompter (3.4u contra 6u de la
  actual) para no distraer. El `font-size` de `.ms-section-fill` debe coincidir
  con el de `.ms-section-adj`.
- **Cues con altura reservada:** si el bloque creciera o colapsara a mitad de
  canción, el escenario cambiaría de tamaño y la letra saltaría. Hoy 1 renglón;
  no está analizado qué pasa con un cue muy largo ni con dos cues a la vez.
- El `outline` punteado del escenario es temporal (validación del layout).

Medidas verificadas del escenario (ancho × alto en px): 393×852 → 362×646
(rotado 821×257); 375×667 → 345×469 (rotado 637×245). En landscape el escenario
mide ~250 px de alto: ahí es donde la medición de §4.2 decide.

## 4. Decisiones de diseño del reel (acordadas, sin implementar)

### 4.1 Composición única y tope de 2 renglones

- Tope de **2 renglones** por línea. Sin ellipsis: una línea cortada que pasa a
  2 renglones al subir de rol se vería como un salto.
- Todas las líneas se componen con **el mismo ancho y el mismo corte de
  renglones**; el rol (actual, siguiente, anterior) se expresa solo con `scale`
  y `opacity`. Una línea que sube de rol nunca se reacomoda: solo se agranda.
- La escala del FLIP sale del **cociente de `font-size` entre roles**, no del alto
  de los rects. Esto difiere de la regla de `01_CONVENCIONES.md` (escala por
  alto de rects): con 1 o 2 renglones el alto ya no sigue solo al `font-size`.
  Al implementar, ampliar esa convención.
- `scale` no cambia la caja de layout, así que las posiciones son absolutas con
  `translateY` calculado por JS.
- Red de seguridad: si una línea mide más de 2 renglones con el tamaño de su rol,
  se le baja el tamaño por pasos al asignarla al slot (no por frame).

### 4.2 Cantidad de slots según los renglones de cada línea

No hay un número fijo de slots. Se agregan en orden de prioridad (actual,
siguiente 1, anterior 1, siguiente 2, anterior 2) mientras la suma de alturas
(alto natural de la línea, 1 o 2 renglones, por la escala de su rol) entre en el
escenario; los que no entran no se dibujan. Se recalcula al cambiar la línea
asignada y en `resize` / `orientationchange`, nunca por frame.

**Foco:** el objetivo es el centro de la pantalla, limitado al rango que el
escenario permite.

### 4.3 Dos posiciones (problema del lead)

`CurrentLyric()` y `LyricEnded()` aplican el lead (1,0 s extra más 0,4 s de
lookahead) a todo, incluido el marcador de fin: con los valores por defecto la
línea se apagaría ~1,4 s antes de que el cantante termine. El lead sirve para
leer el inicio de la siguiente, no para acortar la actual. Se leen dos
posiciones, sin tocar la capa cliente:

- `cur0 = CurrentLyric(0)` y `ended0 = LyricEnded(0)`: lo que se está cantando.
- `curL = CurrentLyric()` (lead por defecto): si la siguiente ya entró en su
  ventana de lectura.

`armada = ended0 || curL.index > cur0.index`.

### 4.4 Estados de la línea

| Momento | Actual | Siguiente 1 |
|---|---|---|
| Intro (sin línea vigente) | — | primeras 2 o 3 como "próximas"; la primera pasa a armada cuando `curL` deja de ser `null` |
| Cantando | 100%, color pleno | "próxima", ~70% |
| Armada (`ended0` o ventana de lectura abierta) | se apaga hacia el nivel de "anterior" | acento + opacidad alta, sin llegar a 100% |
| Carry-over (sin marcador de fin) | se mantiene | pasa a armada solo por la ventana de lectura |

El cambio próxima → armada es solo `opacity` y color: no necesita FLIP.

### 4.5 Ancla de la columna

Por defecto el ancla es la línea cantada (`cur0`): la columna se mueve cuando
empieza la siguiente; en el silencio la actual se apaga sin moverse. La
alternativa es que el ancla avance al aparecer el marcador de fin
(`anclaIdx = ended0 ? cur0.index + 1 : cur0.index`): en carry-over se comporta
igual que la primera. Queda como constante `NIK_CANTANTE_ANCHOR_ON_END`
(default `false`) para probarlo con una canción real.

### 4.6 Indicador de proximidad de la línea siguiente

Barrido de color con `clip-path` (de abajo hacia arriba, como `next` en la fila
de sección) sobre la línea armada, que termina cuando debe empezar a
cantarse. Arranca solo en el tramo final (un `PRELUDE` propio de lyrics, a
calibrar, del orden del lead) y es una única `transition` de CSS con duración
igual a los segundos restantes.

- El tiempo restante sale de `nikMusicStateLyricsNextDistance()` (QN),
  convertido a segundos con el BPM vigente y el playrate; verificar si
  `ms-tempo.js` ya tiene la conversión.
- Se cancela al detener, en seek y al cambiar de línea; resetear también la
  clave de dedupe (gotcha de `musicstate_instrumentista.md` §8).
- Pausas largas (instrumental de varios segundos): el barrido final no cubre
  toda la espera. Una barra fina de progreso como la de acordes queda fuera de
  la v1; se decide viendo cómo se siente en sala.

### 4.7 Conexión inestable y "Sin señal"

Se reutiliza todo lo compartido: la posición interpolada y compensada de
`ms-dispatch.js` / `nikMsEffectivePosSeconds()` y `ms-stale.js`. El reel
sigue extrapolando (hasta 8 s) como los acordes; con `is-stale` se atenúan
cabecera y sección. Un seek o cambio de proyecto hace fade (`is-jumping`); un
avance de ±1 línea hace FLIP. Es la misma política de
`musicstate_instrumentista.md` §4.6 y §7.

## 5. Gotchas verificados

- **Fantasma de la fila de sección:** `nikMsBuildGhost` posiciona el clon en
  absoluto contra `#msSectionRow`; si la fila es `static`, el clon aparece
  arriba de la página, detrás del título. `ms-base.css` fija
  `.ms-section-row { position: relative }` (el prompter lo pisa con `absolute`).
- **`--u` y `dvh`:** una custom property no hace fallback si el valor es inválido
  en tiempo de cómputo; por eso el valor con `dvh` va dentro de `@supports`.
- **Tempo por defecto:** un proyecto sin marcadores de tempo muestra 120 BPM
  (el default de REAPER); `nikMsTempoAt` no distingue ese caso. Preexistente,
  también en el prompter.
- **Jump de otra capa:** hoy `cantante.js` llama
  `nikMsSectionRowRender(false)`. Cuando exista el reel, pasarle su flag de
  jump del tick, igual que instrumentista con la tira de acordes.

## 6. Pendientes, en orden

1. **Paso 3c:** medición del escenario (§4.2): alto natural por línea, slots que
   entran, foco con tope.
2. **Paso 4:** reel de letra: estados (§4.4), FLIP (§4.1), ancla (§4.5) y barrido
   (§4.6). Quitar el `outline` del escenario y el panel de debug.
3. **Cues en cantante:** decidir si ve todos los cues o solo los dirigidos a su
   rol, y si el render de cues de `instrumentista.js` se extrae a un módulo
   compartido; definir qué pasa con cues largos o simultáneos.
4. **Validar en iPhone** (en sala): comportamiento de `100dvh` con la barra de
   Safari y safe areas.
5. **Calibrar el lead** y el `PRELUDE` con una letra real.
6. Evaluar la barra de progreso para pausas largas (§4.6).
7. Extraer la tira de acordes a `shared/` (ver `musicstate_instrumentista.md`
   §11); la usaría esta UI en una v2 o v3 si el cantante también toca.
8. Rol en la fila de metadata (hoy solo tonalidad | tempo).

## 7. Para retomar en otra sesión

Pasar: este doc y `musicstate_lyrics.md`; `musicstate_client.md` §1.6;
`cantante.js`, `cantante.css` y `nsaudio_cantante.html`; y, para la técnica
FLIP, `ms-section-row.js` (`nikMsSectionRowShift`) y
`nikInstrumentistaShiftChordSlots` de `instrumentista.js`. No hace falta el
resto de `instrumentista.js` ni su CSS.
