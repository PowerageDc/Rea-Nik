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
| Medición del escenario (renglones por línea, slots que entran, foco con tope) | Hecho en `cantante.js` (`nikCantanteMeasure`, `nikCantanteComputeLayout`); verificado en vertical y horizontal con letras reales (§4.2). El caso con tope en horizontal no se observó todavía |
| Reel de letra (nodos por posición, animación de ancla, estados, barrido de proximidad, crossfade en seek) | Funcionando y validado en dev. Pendientes: afinar (ver §6, punto 1), gap y distribución vertical (§6, punto 2) |
| Banda de cues | Altura reservada (1 renglón), sin cablear (§6) |
| Validación en iPhone (comportamiento de `100dvh` con la barra de Safari) | Pendiente, en sala |

## 2. Archivos y módulos consumidos

- `nsaudio_cantante.html` — shell: columna de bloques y orden de carga.
- `musicstate-ui/cantante/cantante.css` — layout propio del perfil.
- `musicstate-ui/cantante/cantante.js` — bootstrap, polls, render loop, offset superior, medición, layout y render del reel, estados de línea, barrido de proximidad y panel de debug temporal (oculto salvo con `?debug=1`).

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

## 4. Decisiones de diseño del reel (implementado salvo la ancla alternativa de §4.5 y la barra para pausas largas de §4.6)

### 4.1 Composición única y tope de 2 renglones

- Tope de **2 renglones** por línea. Sin ellipsis: una línea cortada que pasa a
  2 renglones al subir de rol se vería como un salto.
- Todas las líneas se componen con **el mismo ancho y el mismo corte de
  renglones**; el rol (actual, siguiente, anterior) se expresa solo con `scale`
  y `opacity`. Una línea que sube de rol nunca se reacomoda: solo se agranda.
- La escala de cada rol es el **cociente de `font-size` respecto de `cur`**
  (`NIK_CANTANTE_ROLES`). **No hay FLIP**: como las posiciones son absolutas,
  calculadas por JS, y la composición es uniforme, alcanza con una
  `transition` de CSS sobre `transform`, `opacity` y color. La convención FLIP
  de `01_CONVENCIONES.md` (escala por alto de rects) no aplica a este reel.
- `scale` no cambia la caja de layout, así que las posiciones son absolutas con
  `translateY` calculado por JS.
- **Nodos:** uno `.cn-lyric` por **posición** de línea, reusado al cambiar de
  rol (solo cambian `transform`, `opacity` y color, `--cn-lyric-anim`, 450 ms).
  `transform-origin: 50% 0`, con `y` y `h` del layout como tope y alto
  visuales. Nodo nuevo: fade-in en su lugar. Nodo que sale: fade-out y se quita
  a los 600 ms. Cambio de medición: se recrea todo sin animar. Se redibuja solo
  cuando cambia el layout cacheado, nunca por frame.
- Red de seguridad: si una línea mide más de 2 renglones con el tamaño de su rol,
  se le baja el tamaño por pasos al asignarla al slot (no por frame).

### 4.2 Cantidad de slots según los renglones de cada línea

No hay un número fijo de slots. Se agregan en orden de prioridad (actual,
siguiente 1, anterior 1, siguiente 2, anterior 2) mientras la suma de alturas
(alto natural de la línea, 1 o 2 renglones, por la escala de su rol) entre en el
escenario; los que no entran no se dibujan. Se recalcula al cambiar la línea
asignada y en `resize` / `orientationchange`, nunca por frame.

**Foco:** el objetivo es el centro de la pantalla, limitado al rango que el escenario permite.

**Implementación (paso 3c, `cantante.js` y `cantante.css`):**

- **Medidor:** nodo oculto `.cn-measurer` dentro del escenario, con el ancho
  del escenario y la fuente del rol "actual" (`--cn-lyric-size` 6.5u,
  `--cn-lyric-weight` 500, `--cn-lyric-lh` 1.25). Mide **una sola vez** al
  tamaño base (coherente con §4.1): renglones = `round(offsetHeight / alto
  de "M")`. Se remide si cambia el array de líneas, su cantidad,
  `lyrics_version`, `resize`, `orientationchange` o `document.fonts.ready`.
  Con alto 0 (pestaña oculta) reintenta en el tick siguiente.
- **Roles:** `NIK_CANTANTE_ROLES` guarda `scale` y `opacity` en reposo por rol
  (cur 1.00/1.00, next1 0.78/0.70, prev1 0.62/0.35, next2 0.62/0.45, prev2
  0.50/0.20). Valores iniciales, sin calibrar.
- **Slots:** prioridad estricta (`NIK_CANTANTE_SLOT_ORDER`): se corta en el
  primero que no entra. Los inexistentes (antes de la primera línea o después
  de la última) no ocupan lugar ni cortan la cuenta. **Gap proporcional:** el
  mínimo es `--cn-lyric-gap` (1.5u; el medidor lo lee resuelto en px por
  `getComputedStyle`) y el espacio que sobra del escenario se reparte entre
  los gaps hasta un tope de `NIK_CANTANTE_GAP_MAX` veces el mínimo (hoy 4).
  Depende de cuántos slots entran, así que cambia un poco entre anclas.
- **Ancla:** `cur0` (§4.3), convertida a **posición** en
  `nikMusicStateLyricsLines` con un mapa `index -> posición` armado al medir.
  `-1` en intro.
- **Foco:** centro del viewport (`window.innerHeight / 2`) en coordenadas del
  escenario. Si el centro de `cur` no cabe, la pila se desplaza hasta el tope
  del escenario. **Intro** (sin `cur0`): la pila se arma con un `cur`
  **fantasma** en la posición -1 (no se dibuja pero ocupa su lugar), así la
  línea 0 es `next1` y al empezar la pila sube igual que en cualquier cambio de
  línea. Las versiones anteriores (pila de siguientes centrada; misma
  geometría que `cur` solo con opacidad) hacían que las líneas bajaran o
  quedaran quietas al empezar. `y` y `h` de cada slot son tope y alto
  **visuales** (ya escalados).
- **Cache:** el layout se recalcula solo si cambia el ancla o la medición
  (`epoch`), nunca por frame.
- **Verificado:** slots por prioridad, ausencia de `prev*` en la primera línea
  y de `next*` en la última, caída de slots al agrandar la fuente, y
  actualización de los números al rotar. En los proyectos probados
  `index` coincide con la posición (observado, no garantizado por el contrato).

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
| Intro (sin línea vigente) | — (`cur` fantasma, §4.2) | pila de "próximas"; la primera se anuncia con el barrido (§4.6) |
| Cantando | 100%, color pleno | "próxima", ~70% |
| Terminada (`ended0`) | se apaga hacia el nivel de "anterior" | sin cambio propio: el aviso es el barrido (§4.6) |
| Carry-over (sin marcador de fin) | se mantiene (gold) hasta que la pila sube | el barrido (§4.6) |

**Criterio implementado:** el color activo (`--cn-lyric-active-color`, hoy
`--ms-chord-color`, gold) significa solo "se está cantando ahora". La actual
se apaga únicamente con `ended0`. La ventana de lectura (`curL`) no la toca:
la primera versión la apagaba y coloreaba `next1` al abrirse la ventana
(~1,4 s antes), y eso se leía como "ya empezó la siguiente". Por eso el estado
"armada" visual de `next1` se reemplazó por el barrido de §4.6 (color en
`--cn-lyric-armed-color`, hoy blanco). `nikCantanteIsArmed()` sigue calculando
el flag (fórmula de §4.3) pero ya no tiene efecto visual: candidato a limpiar.

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

- El tiempo restante sale de `nikMusicStateLyricsNextDistance(0)` (QN, con lead
  0 para que termine justo cuando `cur0` cambia). `ms-tempo.js` no traía la
  conversión: `nikCantanteSweepRemainingSec()` hace
  `qn * 60 / bpm / playrate`, con `nikMsTempoAt(nikMsEffectivePosSeconds())` y
  `nikTransportPlayRate`.
- Se cancela al detener, en seek y al cambiar de línea; resetear también la
  clave de dedupe (gotcha de `musicstate_instrumentista.md` §8).
- Pausas largas (instrumental de varios segundos): el barrido final no cubre
  toda la espera. Una barra fina de progreso como la de acordes queda fuera de
  la v1; se decide viendo cómo se siente en sala.

**Implementación (`nikCantanteSweepTick`, en el render loop):**

- Hijo `.cn-sweep` en cada nodo (copia del texto en el color de armada,
  recortada con `clip-path`); hereda escala y posición del rol. Se anima solo
  el de `next1`.
- `NIK_CANTANTE_PRELUDE_S` (2.0 s, a calibrar): tramo final en que arranca.
  `NIK_CANTANTE_SWEEP_DIR`: `"up"` (abajo hacia arriba) o `"right"` (default)
  (gris contra blanco casi no se distingue en vertical).
- Si arranca tarde (seek dentro de la ventana), parte de la fracción que
  corresponde. En pausa queda congelado. Se resincroniza si el fin previsto se
  desvía más de 400 ms; se cancela al cambiar la línea o salir de la ventana.
- El overlay se quita de golpe cuando la línea pasa a `cur`, mientras el color
  del nodo transiciona a gold.
- Limitaciones: un cambio de tempo dentro de la ventana deja la duración
  aproximada; el cambio de playrate **durante** la reproducción no se probó
  (parado y luego play, sí). El efecto visual del barrido queda por mejorar.

### 4.7 Conexión inestable y "Sin señal"

Se reutiliza todo lo compartido: la posición interpolada y compensada de
`ms-dispatch.js` / `nikMsEffectivePosSeconds()` y `ms-stale.js`. El reel
sigue extrapolando (hasta 8 s) como los acordes; con `is-stale` se atenúan
cabecera y sección. Un seek o cambio de proyecto hace fade (`is-jumping`); un
avance de ±1 línea se anima (`transition`, sin FLIP: §4.1). Es la misma
política de `musicstate_instrumentista.md` §4.6 y §7.

**Implementación del salto:** es un cambio de ancla de más de 1 línea, en
cualquier dirección. Los nodos viejos se desvanecen y los nuevos entran en su
lugar (crossfade, sin deslizar la pila). El reel publica
`nikCantanteReel.jumped` (verdadero solo en el tick del salto) y se lo pasa a
`nikMsSectionRowRender`. Una remedición (rotación, letra nueva) no cuenta como
salto: recrea todo sin animar.

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
- **Jump de otra capa:** `cantante.js` le pasa a `nikMsSectionRowRender` el
  flag `nikCantanteReel.jumped`. El reel debe renderizarse **antes** que la
  fila de sección para que el flag llegue en el mismo tick.
- **Variable CSS cambiada a mano:** no dispara ningún evento, así que el
  medidor no se entera. En pruebas, después de tocar `--cn-lyric-size` desde
  DevTools hay que llamar `nikCantanteMarkMeasureDirty()` (o provocar un
  `resize`).
- **`next*` de la última línea:** desaparecen cuando `cur0` llega a ella, no
  por el lead. Los slots usan solo `cur0` (lead 0); con `cur0 = #68`,
  `curL = #69` y `ended0 = true` el ancla sigue en #68 y `next1` existe.
  `nikMusicStateLyricsNextDistance()` devuelve `null` sin línea siguiente
  (`proxima (QN)` queda en blanco en el panel de debug).
- **Transiciones con nodos nuevos y barrido:** un nodo nuevo se crea con
  `opacity: 0` y posición final y hace un `offsetWidth` (flush) antes de
  fijar la opacidad destino; el barrido hace lo mismo con su `clip-path`. Sin
  el flush no hay transición.
- **Lead del panel de debug:** la letra del panel usa el lead por defecto
  (`curL`) y los slots solo `cur0`; el panel cambia de línea antes que la
  pila. Es esperado.

## 6. Pendientes, en orden

1. **Afinar el reel:** quitar el `outline` del escenario y el panel de debug
   (hoy detrás de `?debug=1`); probar `NIK_CANTANTE_ANCHOR_ON_END` (§4.5);
   implementar la red de seguridad de más de 2 renglones (§4.1, hoy solo se
   cuenta en el debug); limpiar `nikCantanteIsArmed` y el `refCenter === null`
   que quedó sin uso; probar el cambio de playrate durante la reproducción;
   mejorar el efecto del barrido (§4.6); ver el caso con tope en horizontal
   (§4.2).
2. **Gap y distribución vertical:** con `NIK_CANTANTE_GAP_MAX = 4` en vertical
   sobra espacio. Subirlo a 8 mejora vertical, pero en horizontal desplaza la
   línea central y `prev2` queda pegado a la sección actual. A resolver
   combinando más slots en vertical (`next3`/`prev3`), otro manejo del gap en
   horizontal y un espacio mínimo en blanco arriba y abajo de `prev2`/`next2`.
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
