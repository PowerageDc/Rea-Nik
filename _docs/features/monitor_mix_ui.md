# Feature — Monitor Mix: interfaz web

Interfaz del baterista: lista filtrada de tracks con fader y mute de send
por fila, sobre el segundo Web Control. Lo lee quien toca el shell, el
render, los faders, el mute o el slider. Ruteo, filtro, config y contrato
de la lista (`monitor.js`): `monitor_mix.md`. Módulos visuales compartidos:
`musicstate_shared_ui.md`. Polls, ganchos de `ms-dispatch.js` y ciclo de
proyecto: `musicstate_sync.md`.

## 1. Qué muestra

- Header (título, tonalidad y tempo), fila de secciones y estado sin señal:
  los módulos compartidos tal cual (`nikMsHeaderRender`,
  `nikMsSectionRowRender(false)`, `nikMsUpdateStaleIndicator`), con los ids
  de DOM que exige `musicstate_shared_ui.md` §2 y §3. Se llaman en cada
  render; el flag de salto es `false` porque no hay contenido principal
  que renderizar antes.
- Toolbar fija: par de salida resuelto, bus y botón Actualizar.
- Dos áreas según `role`: Click (todo lo que tiene `role` `click`) y
  Música (el resto). Su disposición depende del espacio disponible y tiene
  tres layouts (§14): `dock` (vertical con alto suficiente), `inline` (un
  solo scroll, vertical con poco alto) y `side` (apaisado, tiras
  verticales). Los avisos según el `status` de la lista
  (`monitor_mix.md` §5) van en el stage.
- Layout `dock`: Click en un **dock fijo** bajo la toolbar y Música en el
  stage, que ocupa lo que sobra y **scrollea solo él**. Filas con sliders
  horizontales (sin conflicto scroll/arrastre y con blancos táctiles
  grandes), mute y chip de paneo por track. Cada área tiene título y
  divider fijos y scrollea solo su lista (§11, §12). Header, toolbar, dock
  y footer quedan fijos.
- Footer: reserva su altura (`msCueBand`) para las cues, pero no está
  cableado (§9); cuando falta alto se cede (§14).
- Solo se ve la lista filtrada; ningún control de playback.
- Botón Actualizar: vuelve a disparar el publish, para cambios de
  estructura dentro del mismo proyecto (tracks nuevos o reordenados). Se
  deshabilita 1,5 s tras el toque.

## 2. Archivos y carga

Shell: `web/nsaudio_monitor.html`. En `web/musicstate-ui/monitor/`:

| Archivo | Rol |
|---|---|
| `monitor.js` | datos, sin DOM (`monitor_mix.md` §5) |
| `mm-fader.js` | curva dB ↔ posición (`nikMmFader`) |
| `mm-slider.js` | slider propio (§7) |
| `monitor-app.js` | bootstrap, lista, faders, mute y reparto de alto (§14) |
| `monitor.css` | estilos propios |

Carga `ms-base.css` y `cantante.css` (clases `cn-*`); `monitor.css` solo
pisa lo que difiere (dock, stage scrolleable, toolbar, filas, fade, layouts, 
popup de paneo). El layout base depende de `cantante.css`: `.cn-screen` es
una columna flex de `100dvh` y `.cn-stage` ocupa lo que sobra
(`flex: 1 1 0; min-height: 0`). El shell envuelve los dos grupos en
`#mmMixer` (`#mmClickDock` y `#mmMusicGroup`, que contiene
`#mmMusicTitle` y el stage) y suma `#mmPanPopup` (fuera de
`.ms-screen`). Esa estructura es la que permite los tres layouts de §14.
Orden de scripts: el de `musicstate_sync.md` §3, y después `monitor.js`, 
`mm-fader.js`, `core/vertical-fader.js`, `mm-slider.js` y `monitor-app.js`. 
De `vertical-fader.js` solo se usa `nikVFaderCheckDoubleTap`; el slider 
no es el de `nikCreateVerticalFader` (el nombre "vertical" es histórico: 
el de Monitor Mix sirve a las dos orientaciones, §7).

## 3. Bootstrap

- Polls y pedidos: `musicstate_sync.md` §8 y §10. No activa
  `NIK_MS_LYRICS_ENABLED`.
- El publish lo dispara `nikMsHandleProjectSwitch` al detectar el primer
  `active_project_name` (arranca en `null`), así que `nikMonitorInit` no
  lo pide.
- **Dedupe:** `nikMmSetList` ignora un texto crudo idéntico al anterior;
  `nikMmListRevision` solo sube con contenido nuevo.
- **Render:** solo si cambió `nikMmListRevision`. Cada render cierra el
  popup de paneo, vacía el dock y la lista, los reconstruye y recalcula
  el alto del dock y los fades (§11).

## 4. Lectura en vivo

Un `wwr_req_recur` de 200 ms con los `GET/TRACK/x/SEND/y` encadenados de
la lista (formato de la línea `SEND`: `monitor_mix.md` §4).
`nikMmRearmLive` cancela el string viejo (por string exacto) y registra el
nuevo al cambiar la lista, y descarta `nikMmSendState`. Estos pedidos no
aparecen como entradas propias en la pestaña de red del navegador (solo
los `TRANSPORT`): REAPER responde y los valores llegan.

## 5. Curva y escritura de volumen

Tramos lineales en dB entre puntos (`nikMmFader.POINTS`):

| Slider | dB |
|---|---|
| 0 % | -60 |
| 25 % | -40 |
| 50 % | -24 |
| 75 % | -12 |
| 100 % | 0 |

- **Lectura:** `dB = 20 × log10(vol)`; con `vol` 0 se toma el piso. Una
  ganancia mayor a 0 dB (puesta a mano en REAPER) se muestra en el tope.
- **Escritura:** lineal a 4 decimales (`10^(dB/20)`), dB redondeado a
  pasos de 0,5. Mientras se arrastra, `SET/.../VOL/<v>` sin sufijo con
  coalescing (el primer valor inmediato y luego uno cada 60 ms como
  máximo, siempre el último); al soltar (`change`), `.../VOL/<v>e`.
- El slider al 0 % escribe 0,001 (-60 dB): no es silencio, el silencio es
  el mute del send.
- **Doble tap:** sobre el thumb, vuelve a `default_db` (o -12 si falta).

## 6. Mute

`SET/.../MUTE/-1` (alterna) con actualización optimista: al tocar, la M y
la fila se pintan al instante y la fila ignora el feed 500 ms
(`NIK_MM_MUTE_LOCK_MS`); después el feed (`flags & 8`) confirma o
corrige. El evento es `click`, no `pointerdown`, para que un scroll que
arranca sobre el botón no mutee sin querer.

## 7. Slider propio (`mm-slider.js`)

Reemplaza al `<input type="range">` nativo: con ese, un scroll vertical
sobre el slider movía el volumen antes de saber si era un scroll, y
`touch-action: pan-y` no alcanzaba. El slider propio decide la intención
antes de escribir.

`div` con `pointer events`; mismo contrato que `nikCreateVerticalFader`
más `isActive()`. El valor nunca se escribe en el down: solo al soltar un
tap o al confirmarse el gesto a lo largo del slider.

**Orientación.** La define la clase `is-vertical` del contenedor, que el
módulo lee al empezar cada gesto (no la deduce de la caja: un flex puede
estirar un slider vertical hasta que parezca horizontal). La pone o quita
`nikMonitorFitLayout` en todos los sliders del mixer según el layout
(§14); el popup de paneo queda siempre horizontal. En vertical el mínimo
queda abajo y el `touch-action` pasa de `pan-y` a `pan-x`.

**Pintado.** `paint()` no escribe `left` ni `width`: fija cuatro variables
en el contenedor (`--mm-sl-pos`, `--mm-sl-a`, `--mm-sl-len`,
`--mm-sl-mark`) y el CSS las aplica a `left`/`width` o a
`bottom`/`height` según la orientación. Rotar el celular no obliga a
repintar desde JS.

**Ejes.** El gesto se decide como "a lo largo" del slider (mueve el valor)
o "transversal" (se cede al scroll). En horizontal el transversal es el
vertical, que scrollea el stage; en vertical es el horizontal, que
scrollea las tiras.

- **Sobre la línea:** tap (hasta 350 ms, sin superar 8 px) salta al valor
  y hace commit; un hold más largo sin mover no hace nada; movimiento a lo
  largo arrastra, y el thumb sigue al dedo.
- **Sobre el thumb** (zona táctil de ±22 px): arrastra desde el valor
  actual, sin salto (umbral de eje de 4 px). Solo aquí aplica el doble
  tap.
- **Movimiento transversal:** se cede el gesto al scroll y no se escribe
  nada. Con el gesto a lo largo confirmado, un `touchmove` no pasivo evita
  que una deriva transversal del dedo lo convierta en scroll. Con mouse no
  hay scroll táctil que ceder: el gesto cuenta siempre como a lo largo.
- **`pointercancel`** en pleno arrastre: cierra con commit del valor
  actual.
- **Control fino:** durante el arrastre, alejar el dedo en sentido
  transversal al eje reduce la sensibilidad, para ajustar el valor de a
  décimas con un fader corto. Hay una zona muerta de `FINE_DEAD_THUMBS`
  (1) thumbs, y más allá la sensibilidad baja de forma continua:
  `1 / (1 + exceso / (FINE_SPAN_THUMBS × thumb))`, con piso `FINE_MIN`
  (0,08). Las distancias se miden en múltiplos del thumb, no en píxeles
  fijos. El arrastre acumula desplazamientos por la sensibilidad vigente
  (solo el primer movimiento toma la posición absoluta del dedo), así que
  cambiar de sensibilidad no hace saltar el valor y volver al carril
  retoma 1:1. El acumulado no se recorta en los extremos: pasarse y volver
  no mueve el valor hasta que el dedo regresa. Mientras la sensibilidad es
  menor a 1, el contenedor lleva la clase `is-fine` (anillo en el thumb).
  El tap sobre la línea no pasa por acá.
- Las constantes están arriba del archivo (`NIK_MM_SLIDER`): umbrales de
  eje, tiempo de tap, zona del thumb y control fino.
- **`fillFrom`** (opcional): valor desde el que parte el relleno, para
  sliders bipolares. Con él el relleno va del origen al thumb y se dibuja
  una marca fija en el origen (`.mm-sl-mark`). Sin él, el relleno parte
  del mínimo (extremo izquierdo, o inferior en vertical): los sliders de
  volumen no cambian.

**Guarda de arrastre:** tras cada escritura la fila ignora el feed durante
400 ms, y mientras haya arrastre confirmado (`isActive()`) no lo sigue, 
para que no pise el valor mientras se toca.

## 8. Aspecto

Línea, relleno y thumb propios con las variables de `monitor.css`. El dock
de Click define su propio acento (`--mm-accent`, `#3fb37f`): título, borde
inferior de 2 px, relleno y thumb, para distinguirlo de un vistazo de la
música. La fila muteada se atenúa aplicando `opacity` al slider 
completo: aplicarla a cada pieza dejaba ver el relleno a través del thumb.

## 9. Pendientes

- **Cues en el footer:** cablear `msCueBand` con las cues activas
  (`nikMusicStateActiveCues`, `musicstate_client.md` §1.4). Reserva su
  altura salvo que falte alto (§14); al cablearla, decidir si las cues
  cuentan como contenido que no se cede.
- **Cambio entre pestañas sin guardar:** de la tab 3 (sin guardar, con
  track del Stem Bus, un hijo y bus de monitoreo) a una tab vacía, la UI
  queda mostrando la lista de la tab 3 hasta tocar Actualizar. Pasar de la
  tab 1 a la 2 no lo reproduce; de la 2 a la 3 sí. Hipótesis sin
  confirmar: dos pestañas sin guardar no se distinguen para el cliente
  (mismo `active_project_name` y firma de markers, ver
  `nikMsHandleProjectSwitch`). Para confirmarlo, leer
  `nikCurrentProjectName` y `nikMsMarkersSig` en la consola de cada tab.
  No bloqueante; resolverlo o aceptarlo tras la prueba en sala.
- **Validar en sala:** la UI en el celular del baterista con el par de
  salida real, y ajustar las constantes de `NIK_MM_SLIDER` (incluido el
  control fino) y el piso de escala de filas (§14).
- **Mensaje de `no_pair`:** la UI muestra el mismo aviso ("no hay par
  adicional") para las tres causas de `no_pair`: dispositivo sin salidas,
  master sin hardware output y falta de un par alineado libre. Depende de
  que el publish informe el motivo (`monitor_mix.md` §9). Con el motivo
  disponible, mostrar un texto distinto por causa.
- **Pantalla apagada en el celular del baterista:** el bus de monitoreo ya
  no depende de que la UI esté despierta (`monitor_mix.md` §5), pero falta
  verificar que al reactivar la pantalla la UI refresque la lista con el
  proyecto activo sin tocar Actualizar.
- `monitor.css` depende de `cantante.css` (clases `cn-*`): evaluar
  extraer el layout común a un archivo compartido.
- **Franja inferior blanca en iPhone vertical:** la hipótesis era la banda
  que reserva `msCueBand`; ahora esa banda se cede cuando falta alto
  (§14), pero no se verificó en iPhone si la franja desapareció.
- **Indicador de "hay más" en `side`:** las tiras scrollean en horizontal y
  el fade de borde (§11) solo cubre el eje vertical (en `side` está
  desactivado), así que nada indica que hay más tiras a los costados.
- **Tira corta en apaisado:** con la barra de URL de Chrome móvil el fader
  queda corto. El control fino (§7) compensa la precisión. Si hiciera falta
  más largo, la opción es compactar la tira (M y dB, o M y chip de paneo, en
  una misma fila), a costa de ancho de tira (`--mm-strip-w`, §14).
- **Pantalla completa en el celular:** botón con la Fullscreen API y/o
  `manifest` para ocultar la barra de URL en Chrome móvil. No existe en
  iPhone Safari. Falta verificar cómo se porta Chrome con una página HTTP
  en la LAN (la instalación PWA completa exige HTTPS).
- **Mantener el celular despierto sin Fully Kiosk:** la Screen Wake Lock
  API exige HTTPS. Alternativas: video oculto en loop (NoSleep.js, con un
  tap inicial), el flag de Chrome "Insecure origins treated as secure" en
  cada celular, o HTTPS vía proxy delante de REAPER.
- **Slider genérico:** mover `mm-slider.js` a `shared/` con nombres y
  clases genéricos (hoy `nikMm*` y `.mm-sl-*`) para reutilizarlo en otras
  UIs. Implica renombrar y actualizar CSS y shell.
- **Fade en iOS Safari:** verificar que la máscara (§11) no parpadee con
  el scroll por inercia.
- **Indicador de "hay más" (pill con contador):** no implementado; evaluar
  solo si fade y snap no alcanzan.
- **Paneo con salida mono:** el chip se oculta si `pair >= 1024` (§12).
  Probar con un par mono real y decidir si la regla se queda.

## 10. Para retomar en otra sesión

Adjuntar: este doc, `monitor_mix.md`, `musicstate_shared_ui.md`,
`musicstate_sync.md`, `nsaudio_monitor.html` y los de `monitor/`
(`monitor.js`, `mm-fader.js`, `mm-slider.js`, `monitor-app.js`,
`monitor.css`), más `cantante.css` y `ms-base.css` (layout y variables de
las que depende). El reparto de alto y los layouts (§14) viven en
`monitor-app.js` y `monitor.css`. Para tocar la lógica de datos, además
`ms-dispatch.js` y `config.js`. Para las cues del footer, `musicstate_client.md` y
`musicstate_instrumentista.md` o `musicstate_cantante.md`, según cuál se
tome de modelo.

## 11. Dock de Click y listas con scroll

Click y Música son áreas separadas, cada una con título fijo y su propia
lista con scroll: al bajar por la música el click no desaparece. Esta
sección describe el layout `dock`; `inline` y `side`, en §14.

```
header (canción, tonalidad, tempo)
fila de sección
toolbar (salida · Actualizar)
┌ CLICK ─────────────────────┐  dock: título fijo, cuerpo con scroll
│ filas (se ven 2 completas) │
└────────────────────────────┘  borde inferior de 2 px, acento
MÚSICA                            título fijo, hermano del stage
  stage: scrollea solo él
footer (cues)
```

**Estructura.** `#mmMixer` contiene `#mmClickDock` (título +
`#mmClickBody`) y `#mmMusicGroup` (`#mmMusicTitle` + `#mmStage`). El
título de Música es hermano del stage, no hijo de su scroll ni
`position: sticky`. Toolbar y dock son `flex: none`; el grupo de Música y
el stage son `flex: 1 1 0`: se quedan con lo que sobra, así que no hay
cálculo manual de alturas. `nikMonitorRowsBuild(tracks)` arma solo filas (mismos
ids `mmSl_*` / `mmDb_*` en ambas áreas). Sin tracks click el dock se oculta
del todo; sin tracks de música, su título; con un aviso (`status` distinto
de `ok`) quedan ocultos los dos títulos y el dock, y el aviso va en el
stage.

**Alto del dock.** `nikMonitorDockFit` mide el alto real de las primeras
`NIK_MM_CLICK_VISIBLE_ROWS` filas (2) y lo fija como `max-height` del
cuerpo, de modo que se ven exactamente esas filas completas. Con ese
número de filas o menos no hay tope. Se recalcula al renderizar y en
`resize` (cubre la rotación) y como parte del reparto de alto (§14), que
lo anula en `inline` y `side`. No hay alturas estimadas: todas las filas
miden igual porque la primera conserva su `border-top` transparente (el
divider visible es el del título).

**Títulos y gap.** `.mm-section-title` es `flex: none`, alineado a la
izquierda, con su divider como `border-bottom`. El gap entre el dock y el
título de Música es `--mm-area-gap` (= `--cn-gap`, escala con el viewport)
como `margin-bottom` del dock: sin dock no queda gap huérfano.

**Snap.** En el layout `dock`, `scroll-snap-type: y mandatory` en el cuerpo del 
dock y en el stage; cada `.mm-row` es `scroll-snap-align: start`. En reposo 
siempre queda una fila completa bajo el título. Límite conocido, aceptado: al
llegar al final de la lista de música, la primera fila visible puede
quedar cerca del divider (no hay más recorrido para alinear; corregirlo
exigiría espacio vacío al final o recortar el stage a filas enteras).

**Fade de borde.** Indica que hay más contenido en esa dirección, ya que
las scrollbars de móvil no se ven en reposo. Es una `mask-image` sobre el
propio scroller (`.mm-stage`, `.mm-area-body`): el borde se funde con el
fondo real y no intercepta toques. `nikMonitorFadeUpdate` pone
`has-more-up` / `has-more-down` según `scrollTop` y `scrollHeight`, al
scrollear (pasivo), al renderizar y en `resize`. Tamaño: `--mm-fade-size`.
En `inline` también cubre a `#mmMixer` (solo el borde inferior, para no
difuminar el título pegado); en `side` está desactivado (§9).

## 12. Paneo por track

Escritura y lectura del paneo del send (escala, signo y sufijo
verificados): `monitor_mix.md` §4.

- **Flag:** `NIK_MM_PAN_ENABLED` (`monitor-app.js`, encendido). Apagado no
  hay chips ni popup.
- **Chip:** `.mm-pan-chip` en la cabecera de cada fila (`.mm-row-head`), a
  la derecha del nombre, Click incluido. Muestra `C`, `L 30` o `R 30`
  (porcentaje entero, acotado a ±100 aunque REAPER tenga más) y toma el
  acento si no está centrado. Se oculta si el par de salida es una sola
  salida física (`pair >= 1024`, `nikMonitorPanVisible`).
- **Popup:** un único panel centrado (`#mmPanPopup`, fondo
  `.mm-pan-backdrop`) reutilizado por todas las filas: nombre del track,
  valor (`Centro` o `50% L`) y un `mm-slider` bipolar (-100 a 100, paso 5,
  `fillFrom: 0`, marca fija en el centro). Toma el acento de la fila, así
  que el de Click sale verde. Se cierra tocando afuera o al redibujar la
  lista, y al cerrar envía lo que haya quedado pendiente.
- **Doble toque:** sobre el thumb centra y escribe `PAN/0`
  (`defaultValue: 0`). La `key` del doble tap incluye el track
  (`mm:pan:<track>_<send>`) y se actualiza al abrir: un toque en un track y
  otro en otro no cuentan como doble tap.
- **Escritura:** `nikMmSetSendPan` (`monitor.js`): `valor / 100`, tope ±1,
  sin sufijo `e` (REAPER lo ignora). Mismo coalescing que el volumen
  (`NIK_MM_WRITE_MS`); el commit cancela lo pendiente y manda el último.
- **Lectura:** en `nikMonitorLiveRender`, con firma propia por fila
  (`panSig`) y guarda propia (`panLockUntil`, `NIK_MM_LOCK_MS`), que no
  actúa mientras se arrastra el popup de esa fila. Corre antes de las
  guardas del volumen: el chip sigue al feed aunque la fila esté muteada.
  Si el popup está abierto en esa fila, mueve también el slider.

## 13. Constantes ajustables

| Constante | Dónde | Qué controla |
|---|---|---|
| `NIK_MM_CLICK_VISIBLE_ROWS` | `monitor-app.js` | Filas de Click visibles sin scrollear (§11) |
| `--mm-fade-size` | `monitor.css` | Tamaño del fade de borde (§11) |
| `--mm-area-gap` | `monitor.css` (`.mm-click-dock`) | Gap entre el dock y Música (§11) |
| `NIK_MM_PAN_ENABLED` | `monitor-app.js` | Enciende o apaga el paneo (§12) |
| `NIK_MM_WRITE_MS`, `NIK_MM_LOCK_MS`, `NIK_MM_MUTE_LOCK_MS` | `monitor-app.js` | Coalescing y guardas de volumen, paneo y mute (§5, §6, §12) |
| `NIK_MM_SLIDER` | `mm-slider.js` | Umbrales de eje, tap, zona del thumb y control fino (`FINE_DEAD_THUMBS`, `FINE_SPAN_THUMBS`, `FINE_MIN`) (§7) |
| `--mm-accent` | `monitor.css` | Color de acento del dock y de los sliders (§8) |
| `NIK_MM_MIN_STAGE_ROWS` | `monitor-app.js` | Filas de Música que el stage debe poder mostrar antes de ceder (§14) |
| `NIK_MM_SHED_MAX` | `monitor-app.js` | Niveles de cesión de elementos fijos (§14) |
| `NIK_MM_SIDE_QUERY` | `monitor-app.js` | Media query que activa el layout `side` (§14) |
| `--mm-row-scale` | `monitor-app.js` fija, `monitor.css` consume | Escala de las filas (§14) |
| `--mm-strip-w` | `monitor.css` (layout `side`) | Ancho de una tira (§14) |
| `--mm-fade-size` en `#mmMixer` | `monitor.css` | Fade inferior del layout `inline` (§11, §14) |

## 14. Reparto de alto y layouts

`--u` es `min(1vw, 1dvh)`: todo escala con el lado corto del viewport. Por
eso el alto disponible, medido en unidades `u`, depende solo de la
proporción de pantalla: ~220 u en un celular largo en vertical, ~50 u en
una ventana baja o en apaisado. Header, fila de sección, toolbar, dock y
títulos suman más que eso, y sin reparto el stage desaparece. El problema
es siempre el mismo en desktop, celular chico y apaisado.

`nikMonitorFitLayout` (`monitor-app.js`) decide el layout **midiendo**, no
con breakpoints en píxeles. Corre al renderizar la lista (también cuando
hay un aviso: sin filas vuelve a escala 1 y sin cesión) y en `resize`, que
cubre la rotación y los cambios de `dvh` por la barra de URL. El estado
queda en dos atributos de `.ms-screen`:

| Atributo | Valores |
|---|---|
| `data-mm-layout` | ausente = `dock`; `inline`; `side` |
| `data-mm-shed` | ausente = 0; `1`; `2` |

```
dock (vertical, alto sobra)   inline (vertical, poco alto)   side (apaisado)

header                        header                         header ·· toolbar
fila de sección               toolbar                        ┌─────┬──────────┐
toolbar                       ┌ un solo scroll ┐             │CLICK│ MÚSICA   │
┌ CLICK (scroll propio) ┐     │ CLICK          │             │tiras│ tiras →  │
MÚSICA                        │ MÚSICA         │             └─────┴──────────┘
  stage (scroll propio)       └────────────────┘
footer (cues)
```

**Escala de filas.** `--mm-row-scale` (de 1 al piso) multiplica solo las
filas: `--mm-ru` = `--u × --mm-row-scale` en `#mmMixer`, y padding,
tipografía, slider, mute, chip y dB de la fila usan `--mm-ru`. El resto de
los elementos fijos sigue en `--u`. El popup de paneo está fuera del mixer
y fija `--mm-ru: var(--u)`, así que no se escala.

**Cesión de elementos fijos** (`data-mm-shed`): nivel 1 oculta la banda de
cues y su divider; nivel 2 oculta además la fila de sección y su divider.
Header y toolbar no se ceden nunca. Al ocultarse con `display: none`, los
módulos compartidos siguen renderizando sobre nodos ocultos sin errores
(`musicstate_shared_ui.md` §3).

**Orden de decisión (layouts vertical).** Para cada nivel de cesión (0, 1,
2), `nikMonitorFitSolve` parte de escala 1 y busca la escala que hace
entrar el dock y las filas mínimas de Música. Si la escala necesaria no
baja del piso, ese nivel alcanza y termina; si no, pasa al siguiente nivel
y resuelve de nuevo desde 1. Si ningún nivel alcanza, pasa a `inline` con
el nivel 2 y la escala en el piso. Cada medición parte de cero, así que al
volver a tener alto no queda nada pegado.

- **Cálculo.** `nikMonitorFitRatio` mide el alto real de una fila y la
  parte fija del mixer (todo lo que está sobre el stage menos las filas del
  dock). La escala que cabe es
  `(alto del mixer − parte fija) / ((filas de dock + filas mínimas) × alto de fila)`.
  Las filas de dock son las visibles (`min(filas de Click,
  NIK_MM_CLICK_VISIBLE_ROWS)`) y las mínimas de Música son
  `min(filas de Música, NIK_MM_MIN_STAGE_ROWS)`. Como los bordes de 1 px no
  escalan, la relación no es exactamente lineal: se corrige midiendo de
  nuevo, hasta 4 veces. Sin filas no hay nada que medir (escala 1).
- **Piso.** `NIK_MM_SLIDER.THUMB_PX` dividido por el alto del slider a
  escala 1 (como mucho 1): la zona del slider nunca queda más baja que su
  thumb. Sin `NIK_MM_SLIDER` o sin slider el piso es 1: no se escala y solo
  se cede.
- **Sin dock de una fila.** Se descartó un escalón intermedio con una sola
  fila de Click visible: un scroll de una fila es difícil de apuntar, y con
  poco alto los dos scrolls anidados (dock y stage) exigen un gesto muy
  preciso. Se pasa del dock de 2 filas directo a `inline`.

**`inline`.** Un solo scroller, `#mmMixer`, con el grupo Click y el grupo
Música uno detrás del otro. Dock y stage pasan a `overflow: visible` y sin
tope de alto (`nikMonitorDockFree` anula `nikMonitorDockFit`). Los títulos
son `position: sticky` dentro de su grupo: el de Música desplaza al de
Click al llegar. El Click deja de verse al bajar por Música: es la pérdida
aceptada a cambio de que todo sea alcanzable. Sin snap. El fade es solo
inferior, porque el de arriba difuminaría el título pegado; el dock
conserva su borde inferior verde como separador de grupos.

**`side` (apaisado).** Se activa con `NIK_MM_SIDE_QUERY`
(`(min-aspect-ratio: 1/1)`, la misma condición que el header de una fila
de `cantante.css`), que el JS lee con `matchMedia`: una sola fuente de
verdad. No hay medición: escala 1 y cesión nivel 2 fijas, porque en
apaisado sobra ancho y falta alto. `nikMonitorFitLayout` pone la clase
`is-vertical` en todos los sliders del mixer (la quita en los otros
layouts); rotar no reconstruye el DOM.

- **Cromo en el eje largo.** `.ms-screen` pasa a grid: header y toolbar
  comparten la primera fila (nombre y datos de la canción juntos a la
  izquierda; salida y Actualizar a la derecha) y el mixer ocupa la segunda
  a todo el ancho, con un divider fino arriba.
- **Grupos.** El Click queda a la izquierda (tope del 35 % del ancho, borde
  derecho con acento) y Música a la derecha. Cada grupo scrollea en
  horizontal con snap en x.
- **Tira.** Cada `.mm-row` es una columna de ancho `--mm-strip-w` (22
  unidades): el ancho de 9 caracteres a la tipografía de la tira (la
  palabra más larga de nombres típicos como `Guitarras`, `Hammond` o
  `Eléctrica`) más padding. El DOM de la fila no cambia: `.mm-row-head` y
  `.mm-row-ctl` pasan a `display: contents` y `order` reordena: nombre (2
  líneas como máximo, se parte por palabras y una palabra muy larga por
  caracteres), chip de paneo, dB, fader (`flex: 1`, todo el alto que
  sobra) y mute al fondo, a ancho completo.
- **Gesto.** El fader tiene `touch-action: pan-x`: un swipe transversal
  (horizontal) scrollea las tiras, y arrastrar a lo largo mueve el valor
  (§7), con el control fino para ajustar con un fader corto.
- **Sin fade** de borde: pendiente en §9.

**Funciones** (`monitor-app.js`): `nikMonitorFitLayout` (orquesta),
`nikMonitorFitSolve` (escala de un nivel), `nikMonitorFitRatio` (medición),
`nikMonitorFitApply` (aplica atributos y escala), `nikMonitorIsSide` (la
media query) y `nikMonitorDockFree` (inline o side).
