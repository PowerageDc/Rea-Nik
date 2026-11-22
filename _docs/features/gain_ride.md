# GainRide — riding de ganancia por nivel de audio

Crea los puntos del envelope **Volume (Pre-FX)** de un track a partir del nivel
real del audio de sus items, para que después se suban o bajen tramos con el
mouse (o se deje la corrección automática). Nació del flujo manual de emparejar
una voz antes del compresor con razor edits y rampas a mano.

Pensado para voces, pero el dominio no es específico de voz: lo vocal vive en
la config (clases y perfiles), no en el código.

Convenciones de nombres y de carpetas: `01_CONVENCIONES.md`. Patrones de los
paneles ReaImGui: `08_REAIMGUI_PATTERNS.md`.

## 1. Qué es y en qué estado está

| Etapa | Qué | Estado |
|---|---|---|
| 1 | Fuente de items y lectura de nivel (sonda) | Validada |
| 2 | Segmentación en piezas (silencios y cambios de nivel) | Validada |
| 3 | Escritura de puntos con rampas | Validada, en uso real (fuerza 0.4, shape 2) |
| 4a | Clase sibilante | Validada en un pasaje, calibración abierta |
| 4b | Clase plosivo | Validada de punta a punta, calibración abierta |
| 5 | Panel ReaImGui | Validado (ver sección 5) |

## 2. Flujo de datos

1. **Fuente** (`Source.resolve`): según el modo, junta items y los agrupa en
   tramos por track, en tiempo de proyecto.
2. **Análisis** (`Analysis.segment_levels`): una curva continua por tramo, una
   fila cada `window_ms` con nivel y rasgos espectrales.
3. **Segmentación** (`Segment.split`): corta la curva en piezas con clase
   (`voz`, `sib`, `plo`) y nivel propio.
4. **Plan** (`Apply.plan`): ganancia por pieza y lista de puntos con rampas.
5. **Escritura** (`Apply.write`): borra los puntos viejos del rango e inserta
   los nuevos en el envelope.

`GainRideRun_common_logic.lua` orquesta los pasos 2 a 5 para el ejecutable y
para el panel, en tres funciones: `Run.read` (la lectura de audio, que es la
parte lenta), `Run.build` (segmenta y agrupa por track) y `Run.write` (plan y
escritura por track). Quien llama decide el undo y la salida.

## 3. Inventario de archivos

| Archivo | Qué hace |
|---|---|
| `GainRide/GainRide_config.lua` | Todos los valores editables a mano (ver sección 4) |
| `GainRide/GainRideSource_common_logic.lua` | Modos de fuente, fusión de partes contiguas, nombre de track |
| `GainRide/GainRideAnalysis_common_logic.lua` | Lectura con audio accessor, RMS, pico, rasgos, compensación de ganancia |
| `GainRide/GainRideSegment_common_logic.lua` | Puerta con histéresis, clases, plosivos, cortes por nivel, regiones de vista previa |
| `GainRide/GainRideApply_common_logic.lua` | Ganancia por pieza, puntos y rampas, escritura en el envelope |
| `GainRide/GainRideRun_common_logic.lua` | Pipeline compartido: lectura, segmentación por track y escritura |
| `GainRide/GainRideParams_common_logic.lua` | Persistencia de los ajustes del panel en el proyecto y texto de la config |
| `GainRide/GainRideTips_common_logic.lua` | Textos de los tooltips del panel, por id de control |
| `GainRide/Nik_GainRide_Apply.lua` | Ejecutable: aplica la feature completa sobre la fuente de `apply.mode`, con la config |
| `GainRide/Nik_GainRide_Panel.lua` | Panel ReaImGui (ver sección 5) |
| `GainRide/Nik_GainRide_ClearPreview.lua` | Borra las regiones de vista previa (prefijo `GR_`) |
| `Tests-Debug/Nik_GainRide_ProbeLevels.lua` | Sonda de la etapa 1: imprime nivel por ventana y empalmes |
| `Tests-Debug/Nik_GainRide_ProbeSegments.lua` | Sonda de segmentación: crea regiones coloreadas por clase, imprime piezas y candidatos de plosivo |
| `Tests-Debug/Nik_GainRide_ProbeShapes.lua` | Sonda de formas de rampa: mide en un envelope real cómo interpola cada forma, con la tensión de Bézier |

El panel consume módulos de `_Shared/`: `ImGuiButtonStyle_common_logic.lua`
(botones por tipo), `ImGuiEditorFocus_common_logic.lua` (devuelve el foco a la
ventana principal tras interactuar) y, a través de este último,
`ImGuiHostFocus_common_logic.lua`.

## 4. Referencia de la config

Los valores reales están en `GainRide/GainRide_config.lua` (manda el archivo,
no esta tabla). `lf_hz` se probó con varios valores (ver sección 8).

**Globales**
- `probe_mode`: modo de fuente de la sonda de segmentación (`"selected"`, `"all"`, `"timesel"`).
- `merge_tolerance_ms` (1): partes que se tocan dentro de esta tolerancia, o se solapan, forman un solo tramo.
- `window_ms` (20), `sample_rate` (48000), `floor_db` (-120), `print_every_ms`: lectura y salida de la sonda. `sample_rate` es la frecuencia a la que el accessor entrega las muestras: coincide con la de la placa y de los proyectos.
- `lf_hz` (150): corte del filtro de un polo que define el rasgo `lf`.
- `preview_prefix` (`"GR_"`): prefijo de las regiones de vista previa.

**`seg` (segmentación)**
- `open_db` (-45) / `close_db` (-50): puerta con histéresis sobre el RMS.
- `min_gap_ms` (150): silencio mínimo para cortar. `min_len_ms` (60): duración mínima de una corrida.
- `smooth_ms` (60): promedio móvil del nivel para los cortes por nivel.
- `level_split` (true), `level_step_db` (4), `level_hold_ms` (60): corte cuando el nivel suavizado se aparta más de `level_step_db` del promedio de la pieza durante `level_hold_ms`.
- `classify` (true), `sib_hf_min` (0.3), `sib_hz_min` (3000), `class_min_ms` (60): clase `sib` si `hf` y `zc_hz` superan ambos umbrales; las ráfagas más cortas que `class_min_ms` se absorben en la vecina.
- `plosive` (true), `plo_lf_min` (0.5), `plo_rise_db` (12), `plo_pre_db` (-40), `plo_ms` (40): clase `plo` en una ventana con `lf` alto, subida brusca respecto de la anterior y ventana previa de nivel bajo; dura `plo_ms` desde el ataque.

**`apply`**
- `mode` (`"selected"`, `"all"`, `"timesel"`), `envelope` (`"Volume (Pre-FX)"`, nombre tal cual lo devuelve REAPER).
- `strength` (0 a 1): 0 deja solo "enganches" en 0 dB, 1 corrige todo el desvío.
- `max_down_db` (9) / `max_up_db` (3): topes del desvío corregible por pieza, antes de aplicar la fuerza.
- `ramp_down_ms` (30) / `ramp_up_ms` (120): rampas generales según el sentido del cambio de ganancia.
- `shape` / `tension`: forma de las rampas (0 lineal, 1 cuadrada, 2 slow start/end, 3 fast start, 4 fast end, 5 bezier). La tensión solo actúa en la forma 5.
- `keep_existing` (false): si es false se borran los puntos del rango antes de escribir.
- `classes.voz|sib|plo`: `target_db` (`"median"` o un número), `offset_db` (voz 0, sib -2, plo -3) y, opcionales, `ramp_down_ms` / `ramp_up_ms` propios (sib 10/40, plo 5/40).

## 5. El panel

`Nik_GainRide_Panel.lua`. Los parámetros se editan en memoria sobre una copia de
la config (`P`); ni el panel ni la persistencia modifican `GainRide_config.lua`.

### Flujo y caché

- **Analizar** lee el audio de la fuente (`Run.read`) y guarda las filas de
  nivel. Es bloqueante: el clic solo marca el pedido y la lectura corre el
  frame siguiente, para que se vea "Analizando...".
- Cualquier cambio de `seg` o `apply` re-segmenta y re-planifica sobre las filas
  en memoria (`refresh`, como máximo una vez cada 0,12 s). No relee audio.
- Los valores de la pestaña Lectura (`window_ms`, `lf_hz`) obligan a releer:
  el panel guarda con qué valores analizó y, si difieren, muestra un aviso y
  bloquea **Aplicar** hasta analizar de nuevo.
- **Aplicar** escribe con los mismos puntos que muestra la curva, en un solo
  paso de undo. Si algún item analizado se borró, pide analizar de nuevo.

### Layout

La ventana no debe tener scroll con la pestaña más alta. De ahí:
- Las pestañas están al final: cambiar de pestaña solo mueve el borde inferior,
  no los controles de arriba.
- Pestañas: Piezas, Detección, Ganancia, Por clase y Lectura. La Ganancia se
  parte de las ganancias por clase para que ninguna supere unas 10 filas.
- El resumen es el del track elegido, en dos líneas fijas bajo la curva; el
  aviso de "cambió la lectura" ocupa siempre su línea. Una línea que aparece y
  desaparece correría los sliders mientras se arrastran.

### Vista previa

- **Regiones** (casilla "Vista previa"): una región `GR_` por pieza, coloreada
  por clase. Se rehacen al mover cualquier parámetro. Destildar las borra.
- **Curva** (`DrawList`): carril de nivel y carril de ganancia sobre el mismo eje
  de tiempo, para el track elegido en el combo.
  - Nivel, fijo de -80 a 0 dB: curva RMS (máximo por píxel), piezas como barras
    en su nivel (mediana) coloreadas por clase, líneas en `open_db` y `close_db`.
  - Ganancia: los puntos de `Apply.plan`, los mismos que escribe Aplicar. El
    rango sale de fuerza, topes y offsets, no de los datos, para que no se mueva
    al ajustar otro parámetro.
  - Cursor de edición como línea vertical.
  - Encuadre: el tramo del track con un margen fijo de 0,5 s, o lo visible en el
    arrange ("Seguir el arrange", con `GetSet_ArrangeView2` dentro de un `pcall`:
    si falla, usa el tramo completo).
- **Formas de rampa:** el dibujo usa las fracciones medidas con
  `Nik_GainRide_ProbeShapes.lua` en un envelope con 12 dB de recorrido
  (`SHAPE_TABLES` y `BEZIER_TABLES` del panel). Las formas 0 y 1 se dibujan por
  fórmula. En Bézier se mezclan las tablas de tensión -1, 0 y +1; entre esos
  valores es una aproximación.

### Ajustes por proyecto

`GainRideParams_common_logic.lua` guarda los parámetros en el proyecto
(`ProjExtState`, sección `GainRide`, clave `params`), como un string Lua.
- **Qué:** fuente, `window_ms`, `lf_hz`, todo `seg` y `apply` salvo `apply.mode`
  y `apply.envelope`. Lo que el panel no edita sigue saliendo de la config: un
  cambio en `sample_rate` o en el nombre del envelope no queda pisado por un
  proyecto viejo.
- **Cuándo:** al soltar el mouse tras un cambio, no en cada paso del arrastre.
- **Carga:** parte de los valores de la config y superpone lo guardado solo en
  claves que existen hoy y con el mismo tipo. Una clave nueva en la config no
  rompe proyectos viejos.
- **Cambio de pestaña de proyecto:** el panel recarga los valores del proyecto
  activo (o los de la config si no tiene) y pide analizar de nuevo.
- **Restaurar** vuelve todo a los valores de la config y queda guardado.
- `Nik_GainRide_Apply.lua` no lee el proyecto: usa solo la config.

### Copiar a config

Copia al portapapeles el contenido completo de `GainRide_config.lua` con los
valores del panel, en el mismo orden y formato del archivo, para pegarlo encima.
Conserva de la config actual `probe_mode`, `apply.mode`, `apply.envelope` y las
claves que el panel no edita. Una clave nueva de la config que no esté en las
listas de orden se agrega al final de su bloque.

### Tooltips

Los textos viven en `GainRideTips_common_logic.lua`, por id de control (el mismo
que usa el panel en `##id`). Se muestran con demora, también sobre controles
deshabilitados, y no mientras se arrastra. `SetTooltip` no corta líneas: el
panel envuelve el texto a 60 caracteres.

### Foco

`ImGuiEditorFocus` con `reaper.GetMainHwnd`: tras soltar un control el teclado
vuelve a REAPER, salvo con un item activo o un popup abierto.

## 6. Decisiones de diseño y su motivo

- **Fuente flexible:** selected, all (tracks seleccionados; si no hay, los tracks de los items seleccionados) y time selection (items recortados a la selección). Razor edit quedó fuera de la primera versión.
- **Trabajo en tiempo de proyecto, no por item:** el envelope es del track. Un split con crossfade de 3 ms (el default del usuario) se detecta como solape de -3.0 ms y se fusiona; un corte limpio da +0.0 ms. En un solape manda la parte que empieza después.
- **Medir el audio crudo:** el accessor de take no incluye el Pre-FX vol, así que el análisis no se contamina con la propia automatización. Con `keep_existing = true` el análisis no tiene en cuenta los puntos que se conservan.
- **Tramo útil por silencios y por cambios de nivel:** la voz grabada es irregular de por sí. Un decrescendo natural se parte en varias piezas con `level_step_db` bajo.
- **Ganancia por pieza:** `fuerza × clamp(objetivo − nivel, −max_bajar, +max_subir) + offset`, con objetivo y offset de **su clase**. El objetivo `"median"` es relativo: con varios tramos o items, todos se llevan al mismo objetivo si se procesan **juntos** (por separado cada selección usa su propia mediana y quedan desparejas entre sí).
- **El offset no se escala con la fuerza:** si dice -2 dB son -2 dB. Con los offsets en 0, la fuerza 0 sigue dando solo enganches.
- **Rampas:** el cambio entre dos piezas termina justo donde empieza la siguiente (el análisis es offline, la bajada se anticipa). Con hueco ≥ rampa, la rampa va antes de la pieza; con hueco corto ocupa todo el hueco; con piezas pegadas se centra en el límite y se acota a la mitad de la rampa y a un cuarto de la pieza más corta. Usa las rampas de la clase de la pieza a la que llega el cambio.
- **Entrada y salida de 0 dB:** antes de la primera pieza hay un punto en 0 dB y otro después de la última, para no dejar la ganancia colgada.
- **Las piezas de todos los tramos de un track forman una sola secuencia**, así las rampas entre tramos vecinos no se pisan.
- **Puntos existentes:** por defecto se borran en `[inicio − margen, fin + margen]` de cada tramo (el margen es la rampa más larga). Decisión del usuario: los borra con deshacer disponible, con opción de conservarlos.
- **Vista previa con regiones, no markers:** muestran inicio y fin de cada pieza. Colores: naranja sib, azul voz, magenta plo. El prefijo `GR_` permite borrarlas sin tocar las propias.
- **Envelope oculto: avisar y no escribir.** El script y el panel nombran los tracks afectados y no tocan el envelope.
- **Un solo pipeline para el script y el panel** (`GainRideRun_common_logic.lua`): evita que la lógica de agrupado por track diverja entre los dos.
- **Escribir solo con botón:** la vista previa es siempre en memoria; el envelope solo cambia con **Aplicar**.

## 7. Aprendizajes técnicos

- **El tiempo del accessor de take es relativo al inicio del item** (`t_proyecto − item.pos`). Validado con un item recortado a la izquierda. `GetAudioAccessorEndTime` coincide con el largo del item.
- **El accessor ignora ganancia de item (`D_VOL`), volumen de take (`D_VOL` del take) y la envolvente de volumen del take.** Se compensan sumando `item_vol_db + take_vol_db` al nivel medido. La envolvente de take no se compensa (el usuario no las usa). Los fades no se probaron.
- **`GetTrackEnvelopeByName` devuelve el envelope aunque esté oculto:** solo da `nil` si nunca se creó. La visibilidad se lee del chunk (`GetEnvelopeStateChunk`): el primer número de la línea `VIS` es 1 si está visible y 0 si está oculto.
- **Las rampas interpolan en el valor del envelope, no en dB.** Con escalado de fader (modo 1) la diferencia en dB con una interpolación lineal es de unas décimas en 12 dB. Medido con `Nik_GainRide_ProbeShapes.lua`: la forma 2 equivale a un suavizado cúbico (3u²-2u³), la 3 arranca rápido y se aplana, la 4 casi no se mueve al principio y acelera al final, la 1 mantiene y salta al final.
- **La tensión solo actúa en la forma 5 (Bézier).** Con tensión positiva la rampa se queda cerca del valor inicial y sube hacia el final; con negativa sube enseguida.
- **La consola de REAPER descarta líneas viejas cuando se llena:** por eso `print_every_ms` es alto y la sonda limita a 40 piezas.
- **Rasgos por ventana** (en mono, `(L+R)/2`):
  - `hf`: energía de la señal diferenciada sobre la energía total; crece con los agudos. Referencia (medida a 44100 Hz): ~0.02 a 1 kHz, ~0.5 a 5 kHz. Voz vocal típica 0.02 a 0.2; sibilante > 0.5. Escala con 1/sr²: a 48000 Hz el mismo audio da ~16% menos, así que un umbral de 0.3 a 44100 Hz equivale a ~0.25 a 48000 Hz.
  - `zc_hz`: cruces por cero por segundo / 2, estimación de la frecuencia dominante. Voz < ~2000 Hz, sibilante > ~3000 Hz.
  - `lf`: energía bajo `lf_hz` (filtro de un polo) sobre la energía total.
- **El efecto de proximidad rompe `lf` como criterio único:** refuerza los graves en toda la voz. Una cola de vocal dio `lf` 0.63, más que el propio plosivo (0.58). Por eso el plosivo se define por subida brusca desde nivel bajo más `lf` alto.
- **El primer corte por nivel de una corrida puede quedar corto:** se fusiona hacia adelante con la pieza siguiente.
- **Un plosivo violento se corrige mejor con un pasa-altos que con automatización de volumen:** acá solo se baja su nivel en el envelope.
- El analizador de tipos del editor se queja si una función devuelve `nil, string` en error y una tabla en éxito en posiciones distintas: se resolvió devolviendo una sola tabla en éxito.

## 8. Calibración observada

- **Sibilantes** (pasaje de 7.829 s con 3 "s" claras): 4 detectadas, incluida una más sutil, sin falsos positivos ni zona gris, con los umbrales de partida.
- **Plosivo** (uno grabado con el teléfono): detectado con `lf` 0.52 (umbral 0.5, margen delgado), subida +18.1 dB (umbral 12) y nivel previo -44.1 dB (umbral -40). La pieza `plo` salió de 40 ms con `zc` 338 Hz y `lf` 0.58. Otro candidato (+6.8 dB, `lf` 0.40) se descartó correctamente.
- **Bombos de batería como reemplazo de plosivos:** detectó 3 y había varios más. El parámetro sensible fue `lf_hz`: con ~700/800 Hz detectó más, con 100 Hz dejó de ver 2. Subir `plo_rise_db` hacia 8, bajar `plo_lf_min` a 0.3 y poner `plo_ms` en 20 o 70 no cambió las piezas ni las detecciones.
  - Hipótesis (sin verificar): en esos eventos el `lf` a 150 Hz queda por debajo incluso de 0.3, y cambiar `lf_hz` mueve la escala del rasgo, algo que el umbral no alcanza a compensar. Por eso `lf_hz` y `plo_lf_min` van de la mano.
  - Hipótesis sobre `plo_ms`: si lo que queda de la pieza después del ataque es más corto que `class_min_ms`, se suma entero a la pieza `plo`, así que `plo_ms` no cambia nada en piezas cortas.
- **Estado:** la calibración sigue abierta; se afina con más material, ahora con el panel.

## 9. Pendientes

**Panel**
- **Presets dentro de la UI**, como los paneles de MidiGen: reemplazan el copiar y pegar de la config y permiten comparar A/B sin fricción. **Copiar a config** quedaría para promover un preset a defaults.
- **Lista de candidatos a plosivo** en el panel. La lógica de candidatos hoy está duplicada dentro de `Nik_GainRide_ProbeSegments.lua`: subirla a `GainRideSegment_common_logic.lua` para que la usen la sonda y el panel. Se pospone hasta tener más material con plosivos.
- **Modo En vivo** (reescribir el envelope al soltar un slider, un undo por soltada). No urgente.
- **Lectura sin bloquear la ventana**: pasarla a una coroutine con barra de progreso para tramos largos.
- **Aplicar no detecta items movidos o recortados después de Analizar**, solo borrados: comparar posición y largo guardados. Se resuelve volviendo a analizar.
- El resumen bajo la curva es solo del track elegido; no hay total por todos los tracks.

**Calibración y mejoras de detección**
- Afinar sibilantes con más material, en particular la zona gris (respiraciones, f, h, consonantes ruidosas), que no apareció en el pasaje de prueba.
- Afinar plosivos con una grabación de condenser con golpes de aire.
- Idea: volver `lf` relativo (respecto de la mediana del track o del tramo) en vez de absoluto, para que el efecto de proximidad no mueva los umbrales entre voces.
- Idea: nivel mínimo para la clase `sib`, para no marcar respiraciones.

**Cobertura y limitaciones**
- Los fades de los items no se compensan ni se probaron.
- Las envolventes de volumen del take no se compensan (el usuario no las usa).
- Con `keep_existing = true` el análisis ignora los puntos que se conservan, y el resultado puede sumar ganancias.
- Si el track no tiene visible el envelope, el script y el panel avisan y no escriben; no lo crean.
- Modo de fuente: el script lo toma de `apply.mode`. Quedan para el futuro wrappers por modo y el modo razor edit.
- Un plosivo violento sigue necesitando un pasa-altos.