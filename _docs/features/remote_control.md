# Feature — Control Remoto Web (`nsaudio_remote_control.html`)

Interfaz web para controlar REAPER desde el celular durante ensayos
(transporte, faders, markers, playrate, semitonos ReaPitch, cambio de
proyecto). Complementa `01_CONVENCIONES.md` (nomenclatura de scripts,
patrón `dofile`). Este doc es el punto de entrada: arquitectura general e
índice. El detalle vive en los docs de cada capa (§3).

## 1. Cliente y entorno

- **Servidor:** el servidor web integrado de REAPER (Preferences >
  Control/OSC/web). Versión de REAPER y entorno de desarrollo:
  `00_CONTEXTO_GENERAL.md`.
- **Cliente:** celular Android con Fully Kiosk Browser. No se usa como PWA
  instalada: la IP de LAN no es alcanzable por el servidor que genera el
  WebAPK.
- **Contenido:** `C:\dev\Rea-Nik\web\`, servido como `reaper_www_root` vía
  junction (`00_CONTEXTO_GENERAL.md`, "Entorno de desarrollo"). El mismo
  `web\` aloja las UIs de MusicState (`musicstate-ui/`).

## 2. Arquitectura de archivos

`nsaudio_remote_control.html` es shell puro: markup y `<script src>` en
orden, sin lógica de negocio inline. La lógica se reparte por capas de
carpeta:

| Ubicación | Rol |
|---|---|
| `config.js` | Command IDs y constantes (colores, timing, poll); ver `remote_control_protocol.md` §8 |
| `modal-loader.js` | Inyecta `modals/*/*.html` en `#modalsRoot` |
| `core/` | Utilidades puras, estado global, dispatch del feed de REAPER, faders, memoria por proyecto, modo PA, bootstrapping |
| `markers/markers.js` | Parseo y color de nombres de marker, compartido |
| `modals/<nombre>/` | Un popup por carpeta: `<nombre>.html` y `<nombre>.js` |

La carpeta es el inventario de archivos; este doc no lo duplica.

**Scripts clásicos, nunca `type="module"`.** El HTML usa `onclick="nikAlgo()"`
inline en muchos lugares; con módulos ES esas funciones quedarían
scopeadas al archivo y los `onclick` se romperían. Todo cuelga de
`window`. El orden de carga lo da el orden de los `<script>` en el HTML.

**`main.js`** es librería de REAPER y no se modifica; su protocolo está en
`remote_control_protocol.md`.

## 3. Documentos por capa

| Capa | Doc | Se adjunta para |
|---|---|---|
| Protocolo y lectura de estado | `remote_control_protocol.md` | Lectura nueva, `ExtState`, `Nik_RemoteState_Poll`, `wwr_onreply`, `config.js` |
| Estado por proyecto | `remote_control_projects.md` | Memoria de UI por tab, selector de proyectos, watchdog |
| UI, estilos y popups | `remote_control_ui.md` | Popup nuevo, CSS/SVG, OptionsBar, posición del transporte, visibilidad de tracks |
| Markers | `remote_control_markers.md` | Seeker, popup de markers, colores, compases, seek relativo |
| Playrate y ReaPitch | `remote_control_faders.md` | Fader vertical, knob SVG, Playrate, ReaPitch |
| Modo PA | `monitor_mix_pa.md` | M/S sobre el corte del PA, chip en MASTER |
| Debug desde el celular | `06_SISTEMA_DEBUG_REMOTE_CONTROL.md` | Logs y depuración de la web en mobile |

## 4. Índice de features

| Feature | Dónde |
|---|---|
| Lectura de estado (poll consolidado, on-demand, `CMDSTATE`) | `remote_control_protocol.md` §1 a §4 |
| Dispatch del feed y arrays por track | `remote_control_protocol.md` §5 |
| Memoria de UI por proyecto | `remote_control_projects.md` §1 |
| Selector de proyectos y ciclado de tabs | `remote_control_projects.md` §2 |
| Watchdog de proyecto desconectado | `remote_control_projects.md` §3 |
| Estilos, paleta y popups | `remote_control_ui.md` §1 y §2 |
| Toggle Loop/Rec/Tracks armadas y Solo in front | `remote_control_ui.md` §4 |
| Formato de posición del transporte (long-tap) | `remote_control_ui.md` §5 |
| Visibilidad de tracks en TCP | `remote_control_ui.md` §6 |
| Seeker de markers, colores y compases por sección | `remote_control_markers.md` §1 a §3 |
| Popup de markers y seek relativo "N compases antes" | `remote_control_markers.md` §4 |
| Fader vertical modular y knob SVG | `remote_control_faders.md` §1 y §2 |
| Playrate (mapa de tempo, BPM bidireccional) y ReaPitch | `remote_control_faders.md` §5 a §7 |
| Color por desviación de los readouts de Playrate y ReaPitch | `remote_control_faders.md` §4 |
| Modo PA | `monitor_mix_pa.md` |

## 5. Pendientes

Cada pendiente vive en el doc de su capa:
`remote_control_protocol.md` §9, `remote_control_projects.md` §4,
`remote_control_ui.md` §7, `remote_control_markers.md` §7 y
`remote_control_faders.md` §8.