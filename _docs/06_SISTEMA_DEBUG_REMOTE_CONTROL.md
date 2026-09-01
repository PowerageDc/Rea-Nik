# Sistema de Debug — Control Remoto Web

Spec de diseño para reemplazar el debug quirúrgico manual (sprinkle de
`console.log` agregados a mano, cazados uno por uno antes de cada commit)
por un mecanismo centralizado, permanente en el código, con toggle por
categoría y sin costo cuando está apagado.

**Origen:** sesión de debug del bug de memoria de UI por tab
(`core/tab-ui-memory.js` + colisión de `id` en templates clonados,
`core/wwr-dispatch.js`) — ver `remote_control.md`. El proceso manual
funcionó pero no escala: cada sesión de debug repite el mismo ciclo
(agregar logs → testear → transcribir logs a mano → cazar cada línea para
sacarla antes de commitear). Este doc formaliza un reemplazo, a implementar
en fases separadas (una por sesión).

Alcance: específico de `RemoteControl/` (control remoto web, HTML/JS/Lua
de soporte). No aplica a paneles nativos ReaImGui (`ReaPitchBus/`,
`StemFragment/`) salvo que en el futuro se decida generalizar — no
bloqueante hoy.

---

## Objetivos de diseño

- **Los logs quedan en el código para siempre.** Nada de agregar/sacar
  líneas por sesión de debug — se agrega una vez, se prende/apaga.
- **Apagado por default, costo ~cero cuando está apagado.** No debe haber
  razón para no dejar logging permanente en rutas calientes (poll de
  10ms, dispatch de tracks).
- **Categorizado por módulo/dominio**, no un firehose global — activar
  solo lo que se está debugueando en ese momento.
- **Persistente entre reloads** (no se pierde el toggle al refrescar la
  página o reconectar).
- **Utilizable sin devtools** — el caso real que motiva esto es debuguear
  en el celular corriendo Fully Kiosk Browser, donde no hay consola a
  mano.
- **No romper el patrón de scripts clásicos** (`window.nikAlgo`, sin
  `type="module"` — ver `remote_control.md` § Arquitectura de archivos).

---

## Fase 1 — Logger centralizado (`core/nik-log.js`)

Base de todo lo demás. Módulo nuevo, cargado después de `core/state.js` y
antes de `core/wwr-dispatch.js` (mismo orden de dependencia que
`tab-ui-memory.js`).

### API

```javascript
nikLog(category, ...args);          // log condicionado por categoría activa
nikLogError(category, ...args);     // siempre visible, independiente del toggle (errores reales)

nikDebug.enable(category);          // activa una categoría (o "all")
nikDebug.disable(category);         // desactiva una categoría (o "all")
nikDebug.list();                    // categorías conocidas + estado on/off
```

`nikLog` internamente hace `console.log("[nik:" + category + "]", ...args)`
solo si la categoría está activa. `nikLogError` no depende del toggle —
errores reales (catch, respuesta inesperada del feed) siempre visibles,
no hay razón para silenciarlos.

### Categorías iniciales (mapeadas a módulos existentes)

| Categoría | Módulo | Qué cubre |
|---|---|---|
| `dispatch` | `core/wwr-dispatch.js` | Parseo del feed, creación/remoción de shells de track |
| `tabMemory` | `core/tab-ui-memory.js` | Save/restore de UI por proyecto |
| `faders` | `core/faders.js` | Arrastre de faders, doble-tap reset |
| `render` | `core/tracks-render.js` | Animación expandir/colapsar (`hitbox()`) |
| `markers` | `markers/markers.js` | Parseo/color de nombres de marker |
| `init` | `core/init.js` | Bootstrapping, watchdog de proyecto desconectado |
| `modal` | `modals/*/*.js` | Común a todos los popups (o subcategorías `modal:tracksvis`, etc. si hace falta granularidad) |

Lista abierta — sumar categoría nueva es agregar una fila acá y usar el
string correspondiente en `nikLog()`, sin tocar el resto del mecanismo
(mismo espíritu que `nikTabUiMemory` en la Fase de memoria de UI).

### Persistencia

`localStorage.setItem("nikDebugCategories", JSON.stringify([...]))` —
sobrevive reload/reconexión. Se lee una sola vez al cargar `nik-log.js`.

### Activación

Desde la consola (desktop, mientras hay devtools):
```javascript
nikDebug.enable("tabMemory")
```

### Migración de los `console.log` existentes

Este mismo bug de memoria de UI dejó, antes de la limpieza final, un set
conocido de puntos de instrumentación (`SAVE`, `RESTORE`, `SHELL CREADO`,
`POBLADO`, `REMOVIENDO`, `CAMBIO DETECTADO`) — buen primer caso de uso
real para migrar a `nikLog("dispatch", ...)` / `nikLog("tabMemory", ...)`
al implementar esta fase, en vez de quedar como referencia solamente
teórica.

### Entregable de esta fase
- `core/nik-log.js` nuevo.
- `nsaudio_remote_control.html` — un `<script src="core/nik-log.js">` más,
  en el orden correcto.
- Migrar los puntos de instrumentación ya identificados en
  `wwr-dispatch.js`/`tab-ui-memory.js` como primer caso de uso.

---

## Fase 2 — Overlay on-screen para mobile

Encima del logger de la Fase 1, sin cambiarlo — se le suma un sink visual
además de `console.log`.

### Mecanismo

- `nikLog()` empuja cada línea a un buffer circular en memoria (últimas
  ~200 líneas, `Array` con `shift()` al superar el límite) — corre
  siempre, esté o no visible el overlay, para no perder las líneas
  previas al momento en que se abre.
- Overlay (`<div id="nikDebugOverlay">`, oculto por default vía CSS)
  pinta el buffer cuando está visible, con auto-scroll al final.
- Activación: gesto discreto que no interfiera con el uso normal en
  ensayo — candidato: long-press (ej. 1.5s) sobre el logo/header del
  remoto, o un ítem nuevo en el popup de opciones ya existente
  (`modals/`). A definir en el momento de implementar, según qué se
  sienta menos invasivo probado en mano.
- Botón **Copiar** dentro del overlay: `navigator.clipboard.writeText()`
  con el buffer completo — pegar directo en un mensaje/chat, sin cable ni
  red especial.
- Botón **Categorías**: checkboxes para `nikDebug.enable/disable` sin
  tocar código ni depender de la consola — necesario en mobile, donde no
  hay forma de tipear en la consola del navegador.

### Consideración de performance
El buffer circular debe tener costo fijo (no recorrer todo el array en
cada push) — usar índice circular o `shift()` simple dado que 200
elementos es un volumen trivial para `Array.shift()`.

### Entregable de esta fase
- `core/nik-log.js` — sumar buffer circular + hook de push, independiente
  del toggle de consola (el buffer se llena igual, sirve de historial aún
  con categoría desactivada en consola).
- Overlay nuevo (HTML + CSS + JS, ubicación candidata:
  `modals/debug-overlay/` para seguir el patrón de popups existente, o
  inline en `core/nik-log.js` si el overlay es simple — decidir en el
  momento según tamaño real).
- Gesto de activación + checkboxes de categoría.

---

## Fase 3 — Remote debugging real vía Fully Kiosk

No es desarrollo propio — es investigar y documentar un camino que puede
ya estar disponible en la app.

### A confirmar
Fully Kiosk Browser corre sobre un WebView de Android. Varias versiones
exponen una opción de **remote debugging del WebView**
(configuración avanzada → Remote Admin / WebView debugging, el nombre
exacto depende de la versión instalada). Si está disponible:

1. Activar la opción en Fully Kiosk (celular).
2. Conectar el celular a la PC de dev por USB (modo depuración USB
   habilitado en Android).
3. Abrir `chrome://inspect` en Chrome desktop — debería listar la sesión
   del WebView de Fully Kiosk.
4. Devtools completo contra la sesión real: consola, breakpoints,
   inspector de red, todo — sin overlay, sin buffer, sin limitaciones.

### Entregable de esta fase
- Confirmar disponibilidad en la versión de Fully Kiosk instalada.
- Si está disponible: documentar el paso a paso exacto (nombres de menú
  reales, no genéricos) en `remote_control.md`, sección nueva "Debug
  remoto en mobile".
- Si NO está disponible: descartar esta fase y quedarse con el overlay
  (Fase 2) como único mecanismo mobile — documentar igual la
  investigación para no repetirla en el futuro.

Esta fase no tiene dependencia dura de la Fase 2 — puede resultar que el
remote debugging cubra todo el caso de uso mobile y el overlay quede como
respaldo liviano para chequeos rápidos en medio de un ensayo (sin PC a
mano), no como herramienta primaria.

---

## Fase 4 — Persistencia a archivo (Lua sink)

La más pesada en piezas nuevas — evaluar si hace falta después de tener
las Fases 1-3 en uso real. Cubre el caso de logs que deben sobrevivir un
crash del navegador o revisarse después sin haber estado mirando el
celular en el momento del evento.

### Mecanismo propuesto

- El JS escribe cada línea de log (o solo las de `nikLogError`, a
  definir) vía el mismo canal que ya usa para otro estado:
  `SET/EXTSTATE/NikRemote/<key>` — mismo patrón que el resto del sistema
  (ver `01_CONVENCIONES.md` § módulos compartidos, y el poll
  `NIK_SLOW_POLL` de `config.js`).
- Script Lua nuevo (candidato: `RemoteControl/Nik_RemoteDebug_Sink.lua`)
  corriendo en background (registrado como acción con
  `defer`/`atexit`, patrón ya usado por `Nik_RemoteState_Poll.lua`) que
  lee esa `ExtState` y la vuelca a archivo (`io.open(path, "a")`).
- Ubicación del archivo: candidato bajo el propio repo o `%APPDATA%\REAPER`
  — a definir, evitando problemas de codepage ya conocidos (ver
  `00_CONTEXTO_GENERAL.md` — nunca usar `os.execute()`/`io.popen()` para
  esto; `io.open` de Lua nativo no tiene ese problema).

### Preguntas a resolver antes de implementar
- ¿Todo el log, o solo errores/categorías críticas? (Volumen — escribir a
  disco en cada `nikLog()` de una ruta caliente como el poll de 10ms
  sería excesivo; probablemente solo `nikLogError` + un snapshot on-demand
  del buffer de la Fase 2, no un stream continuo.)
- ¿Rotación de archivo? (Evitar crecimiento indefinido en ensayos largos.)

### Entregable de esta fase
- `Nik_RemoteDebug_Sink.lua`.
- Sumar la `ExtState` correspondiente a `NIK_SLOW_POLL` en `config.js`
  (recordar el gotcha ya documentado: sumar la key en Lua NO alcanza, hay
  que sumarla también al poll — ver `remote_control.md` § Gotchas).
- Definir y documentar la política de qué se persiste (no todo el log).

---

## Orden de implementación

1. Logger centralizado (Fase 1) — sin esto no hay base para nada más.
2. Overlay mobile (Fase 2) — resuelve el dolor concreto actual (debug en
   Fully Kiosk sin devtools).
3. Investigar remote debugging real (Fase 3) — en paralelo o después de
   la 2, no bloquea nada; puede simplificar o reemplazar la necesidad de
   pulir el overlay más allá de lo básico.
4. Sink a archivo (Fase 4) — solo si el uso real de las fases anteriores
   muestra que hace falta persistencia más allá de copiar el buffer a
   mano.

Cada fase es una sesión de trabajo separada, por el modo de trabajo
habitual (pasos chicos, confirmación antes de avanzar, sin regenerar
archivos completos en los diffs).
