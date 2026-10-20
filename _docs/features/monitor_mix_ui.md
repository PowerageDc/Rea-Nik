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
- Stage con la lista: sliders horizontales (sin conflicto scroll/arrastre
  y con blancos táctiles grandes), mute por track. Se separa en dos
  secciones según `role`: Música (todo lo que no es `click`) y Click. Más
  avisos según el `status` de la lista (`monitor_mix.md` §5).
- El stage se dimensiona según el viewport y **scrollea solo él**; header
  y footer quedan fijos.
- Footer: reserva su altura (`msCueBand`) para las cues, pero no está
  cableado (§9).
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
| `monitor-app.js` | bootstrap, lista, faders y mute |
| `monitor.css` | estilos propios |

Carga `ms-base.css` y `cantante.css` (clases `cn-*`); `monitor.css` solo
pisa lo que difiere (stage scrolleable, toolbar, filas). Orden de scripts:
el de `musicstate_sync.md` §3, y después `monitor.js`, `mm-fader.js`,
`core/vertical-fader.js`, `mm-slider.js` y `monitor-app.js`. De
`vertical-fader.js` solo se usa `nikVFaderCheckDoubleTap`; el slider no es
el de `nikCreateVerticalFader` (el nombre "vertical" es histórico: el de
Monitor Mix es horizontal).

## 3. Bootstrap

- Polls y pedidos: `musicstate_sync.md` §8 y §10. No activa
  `NIK_MS_LYRICS_ENABLED`.
- El publish lo dispara `nikMsHandleProjectSwitch` al detectar el primer
  `active_project_name` (arranca en `null`), así que `nikMonitorInit` no
  lo pide.
- **Dedupe:** `nikMmSetList` ignora un texto crudo idéntico al anterior;
  `nikMmListRevision` solo sube con contenido nuevo.
- **Render:** solo si cambió `nikMmListRevision`.

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

`div` con `touch-action: pan-y` y `pointer events`; mismo contrato que
`nikCreateVerticalFader` más `isActive()`. El valor nunca se escribe en el
down: solo al soltar un tap o al confirmarse el eje horizontal.

- **Sobre la línea:** tap (hasta 350 ms, sin superar 8 px) salta al valor
  y hace commit; un hold más largo sin mover no hace nada; movimiento
  horizontal arrastra, y el thumb sigue al dedo.
- **Sobre el thumb** (zona táctil de ±22 px): arrastra desde el valor
  actual, sin salto (umbral de eje de 4 px). Solo aquí aplica el doble
  tap.
- **Movimiento vertical:** se cede el gesto al scroll del stage y no se
  escribe nada. Con el eje horizontal confirmado, un `touchmove` no pasivo
  evita que una deriva vertical del dedo lo convierta en scroll.
- **`pointercancel`** en pleno arrastre: cierra con commit del valor
  actual.
- Las constantes están arriba del archivo (`NIK_MM_SLIDER`): umbrales de
  eje, tiempo de tap, zona del thumb.

**Guarda de arrastre:** tras cada escritura la fila ignora el feed durante
400 ms, y mientras haya arrastre horizontal confirmado (`isActive()`) no
lo sigue, para que no pise el valor mientras se toca.

## 8. Aspecto

Línea, relleno y thumb propios con las variables de `monitor.css`. La
sección Click usa otro color de acento (`--mm-accent`, `#3fb37f`) para
distinguirla de un vistazo. La fila muteada se atenúa aplicando `opacity`
al slider completo: aplicarla a cada pieza dejaba ver el relleno a través
del thumb.

## 9. Pendientes

- **Cues en el footer:** cablear `msCueBand` con las cues activas
  (`nikMusicStateActiveCues`, `musicstate_client.md` §1.4); hoy solo
  reserva altura.
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
  salida real, y ajustar las constantes de `NIK_MM_SLIDER`.
- **Mensaje de `no_pair`:** la UI muestra el mismo aviso ("no hay par
  adicional") para las tres causas de `no_pair`: dispositivo sin salidas,
  master sin hardware output y falta de un par alineado libre. Depende de
  que el publish informe el motivo (`monitor_mix.md` §9). Con el motivo
  disponible, mostrar un texto distinto por causa.
- **Sin probar:** un tercero moviendo el mismo send mientras el baterista
  no lo toca (el fader debería seguirlo).
- `monitor.css` depende de `cantante.css` (clases `cn-*`): evaluar
  extraer el layout común a un archivo compartido.

## 10. Para retomar en otra sesión

Adjuntar: este doc, `monitor_mix.md`, `musicstate_shared_ui.md`,
`musicstate_sync.md`, `nsaudio_monitor.html` y los de `monitor/`
(`monitor.js`, `mm-fader.js`, `mm-slider.js`, `monitor-app.js`,
`monitor.css`). Para tocar la lógica de datos, además `ms-dispatch.js` y
`config.js`. Para las cues del footer, `musicstate_client.md` y
`musicstate_instrumentista.md` o `musicstate_cantante.md`, según cuál se
tome de modelo.
