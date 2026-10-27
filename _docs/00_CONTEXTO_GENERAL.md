# Contexto General — Proyecto REAPER Practice Rig / Stems Player

## Setup técnico
- REAPER v7.82
- SWS/S&M Extensions
- Windows 10

## Entorno de desarrollo
Repo real (`.git`, historial completo) vive en `C:\dev\Rea-Nik\`, **fuera**
de `%APPDATA%\REAPER` — decisión tomada para resolver dos problemas a la
vez: categorías cortas en ReaPack (`reapack-index` deriva la categoría de
la ruta relativa a la raíz del repo — con el repo afuera, las carpetas de
dominio quedan directamente en la raíz, sin el prefijo `Scripts/Custom/`
de antes) y una raíz de repo real abierta en VS Code (el workspace viejo
abría subcarpetas sueltas vía `.gitignore` allow-list, lo cual rompía el
refresh automático de extensiones como GitGraph).

Estructura:

```
C:\dev\Rea-Nik
├── AutoColor, RemoteControl, ReaPitchBus, RenderWorkflow, TempoTools,
│ MvsepImporter, MusicState, MonitorMix, ProjectFolder, StemFragment, 
│ Tests-Debug, _Shared
├── web\ ← contenido servido como reaper_www_root
├── _docs
└── Rea-Nik.code-workspace
```

Los scripts Lua **no** requieren estar físicamente bajo `Scripts\` del
resource path de REAPER — el Command ID se asigna según dónde REAPER
encuentra el archivo al registrarlo ("Load ReaScript..."), sin importar
la ubicación. Se registran directo contra `C:\dev\Rea-Nik\<Dominio>\...`.

`web\` sí necesita vivir en una ruta fija (`reaper_www_root`, requerida
por el servidor web embebido de REAPER) — se resuelve con un **junction**:

```
%APPDATA%\REAPER\reaper_www_root → (junction) → C:\dev\Rea-Nik\web
```

Creado con `New-Item -ItemType Junction` (no symlink — no requiere admin
en Windows 10). Transparente para REAPER: lee/escribe como si fuera una
carpeta normal.

**Importante:** el Command ID de cada script es específico de esta PC de
dev — no tiene relación con el Command ID que un script recibe en una PC
de destino tras un deploy vía ReaPack (ver `05_REAPACK_DEPLOY.md`), ya
que ReaPack instala en `Scripts\Rea-Nik\<categoría>\...`, una ruta
distinta. Son independientes por diseño, no hay sincronización posible
entre ambos.

## Modo de trabajo (aplica a toda sesión de scripting/documentación)
- Resolver por pasos, esperando confirmación antes de avanzar al siguiente.
- Advertir antes de escribir más de 300 líneas de código.
- Al debuguear o modificar código existente: **no regenerar archivos completos**.
  Entregar diffs en formato listo para buscar/copiar/pegar. El bloque de código
  debe contener solo el código a buscar y reemplazar, sin comentarios extra
  dentro del bloque.
- Desarrollo iterativo y modular: construir y testear en etapas, no de una vez.
- Conversaciones en español.

## Propósito general del proyecto
Flujo de trabajo centrado en un proyecto plantilla ("Practice Rig - Stems
Player") para transformar canciones separadas en stems (Drums, Bass, Guitar,
Piano, Other, Vocals) en pistas de práctica: renders de secciones específicas
con combinaciones de stems adaptadas (un instrumento protagonista, o la mezcla
completa menos un instrumento), incluyendo un count-in de metrónomo grabado en
el archivo final.

## Mapa del ecosistema de funcionalidades

Cada funcionalidad tiene su propio doc en `features/`, pero todas comparten
las convenciones de `01_CONVENCIONES.md`. Relación entre ellas:

```
MVSEP Importer  →  llena el folder "Stem Bus" con los 6 stems
                         │
                         ▼
                Sistema de Snapshots (SN_*)
                (ya implementado, script custom)
                         │
                         ▼
                Render Workflow
        (regiones nombradas + count-in + preset)
                         │
                         ▼
        Batch Script (EN DESARROLLO)
   vincula región ↔ snapshot ↔ render automático
```

Funcionalidades independientes (no articulan directamente con el flujo de
render, pero conviven en el mismo proyecto/entorno):
- **Auto-color system**: colorea tracks por familia de instrumento.
- **Tempo mapping / ReaBeat**: detección de tempo y corrección de mapa de
  tempo para intros atípicas.
- **Panel ReaPitch (Stem Bus)**: control nativo de semitonos ReaPitch vía
  ReaImGui, ver `03_PANEL_REAPITCH_KNOB.md`.
- **A/B de tracks (ABPair)**: alterna por solo entre dos tracks (ej. MIDI
  corregido vs WAV original) con un atajo, también desde el Piano Roll. El
  contrato vive en el encabezado de los scripts; hoy solo uso local.
- **Control remoto web**: interfaz HTML para controlar REAPER desde el
  celular en ensayos (transporte, faders, markers, playrate, semitonos
  ReaPitch), ver `features/remote_control.md`.
- **MusicState (armonía, cues, prompter y letra)**: el Helper (ReaImGui)
  carga por proyecto tonalidad, roles, armonía, cues y letra; se publican
  vía ExtState y UIs web de celular (prompter de instrumentista, UI de
  cantante) los muestran sincronizados con el transporte, tolerando una
  red inestable. Punto de entrada e índice de docs de la feature:
  `features/musicstate_data_model.md`. Qué adjuntar según la tarea: sección
  "Qué adjuntar según la tarea (MusicState)", al final de este doc.
- **Monitor Mix (monitoreo por músico)**: mezcla personal del baterista
  (a futuro, de otros músicos) por un bus con `B_MAINSEND=0` hacia el par
  de salidas secundario de la placa, con volumen, mute y paneo a nivel de send.
  Filtro de tracks configurable en código, publicado por ExtState con un
  script one-shot que dispara el cliente, y una interfaz web separada
  (segundo Web Control) sin controles de transporte, con el mismo header,
  secciones que las UIs de MusicState (la fila de cues del footer no está
  cableada). El remoto principal tiene un modo PA para cortar tracks del PA
  sin alterar la mezcla del par secundario. Ver `features/monitor_mix.md`
  (ruteo, filtro y datos), `features/monitor_mix_ui.md` (interfaz) y
  `features/monitor_mix_pa.md` (capa PA).
- **Deploy vía ReaPack**: empaquetado y distribución de un subconjunto de
  scripts (hoy: Control remoto + Auto-color + MusicState + MonitorMix + ProjectFolder) a PCs de ensayo
  sin git ni editor de código, vía repo propio `Rea-Nik` en GitHub. Ver
  `05_REAPACK_DEPLOY.md`.

## Estado general (ver detalle en cada doc de feature)
| Funcionalidad           | Estado                                        |
|--------------------------|------------------------------------------------|
| Auto-color system        | Confirmado funcionando                         |
| MVSEP stem importer      | Importer base y script de voces separadas (lead/back), con módulo y config compartidos. Pendientes en `features/mvsep_importer.md` |
| Sistema de Snapshots      | Implementado (script custom, prefijo SN_)      |
| Render Workflow           | Regiones, count-in y preset implementados; batch render pendiente |
| Tempo mapping / ReaBeat   | Diagnóstico en curso                           |
| Panel ReaPitch (Stem Bus) | Funcional, pulido visual pendiente             |
| Control remoto web        | Funcional. Pendientes por capa en `features/remote_control.md` §5 |
| MusicState / Prompter     | Helper, prompter de instrumentista (vertical y landscape), sincronización y UI de cantante (letra). Pendientes en `features/musicstate_instrumentista.md` §5 y `features/musicstate_cantante.md` §6 |
| Deploy vía ReaPack        | Publicado: AutoColor, RemoteControl, MusicState (con lyrics y UI de cantante), MonitorMix y ProjectFolder, vía metapaquetes + .www. Pendientes en `05_REAPACK_DEPLOY.md` |
| Monitor Mix               | Ruteo, filtro, bus y sends, canal de datos (ExtState más feed nativo), UI web del baterista, capa PA con modo PA en el remoto principal. Pendientes en sus docs. Ver `features/monitor_mix.md`, `features/monitor_mix_ui.md` y `features/monitor_mix_pa.md` |

## Pendientes generales (horizonte, no bloqueantes)
- Count-in con offset negativo de render: **evaluado y descartado** como forma
  de evitar el track de count-in — el track propio sigue siendo necesario por
  calidad de sonido y porque el patrón rítmico del conteo varía (4 negras, o
  2 blancas + 4 negras en tempos rápidos).
- Pitch-shift toggle script (per-stem, mapeable a footswitch MIDI).
- Parser de nomenclatura alternativa de secciones (V1, V2, PC, C1...) usada en
  otros proyectos — no bloqueante.

## Qué adjuntar según la tarea (MusicState)

Punto de partida: el doc principal de la tarea y lo que ese doc cita como dependencia. Docs en `_docs/features/`; código de las UIs en `web/musicstate-ui/`.

| Tarea | Docs | Código |
|---|---|---|
| UI de prompter | `musicstate_instrumentista.md` | `instrumentista/`, `nsaudio_prompter.html` |
| UI de cantante | `musicstate_cantante.md` | `cantante/`, `nsaudio_cantante.html` |
| UI de Monitor Mix | `monitor_mix_ui.md`, `musicstate_shared_ui.md` | `monitor/`, `nsaudio_monitor.html` |
| Módulo compartido (fila de sección, cabecera, sin señal) | `musicstate_shared_ui.md` y el de la UI | `shared/ms-*.js` |
| Sync (posición, lookahead, tempo, playrate, polls) | `musicstate_sync.md`, `musicstate_client.md`, `musicstate_testing.md` | `core/music-state.js`, `shared/ms-tempo.js`, `shared/ms-beat.js`, `shared/ms-dispatch.js` |
| Ruteo, filtro y datos de Monitor Mix | `monitor_mix.md`, `musicstate_sync.md` | `MonitorMix/*.lua`, `monitor/monitor.js`, `shared/ms-dispatch.js`, `config.js` |
| Capa PA (corte del PA, modo PA del remoto) | `monitor_mix_pa.md`, `monitor_mix.md` | `MonitorMix/MonitorMixPa_common_logic.lua`, `MonitorMix/Nik_MonitorMix_PaRoute.lua`, `core/pa-mode.js`, `core/wwr-dispatch.js`, `config.js` |
| Reutilizar la tira de acordes | `musicstate_instrumentista.md`, `musicstate_shared_ui.md`, `musicstate_sync.md`, `musicstate_client.md` | `instrumentista/`, `shared/ms-beat.js`, `shared/ms-section-row.js` (ejemplo de extracción) |
| Key nueva publicada desde el Helper | `musicstate_data_model.md`, `musicstate_bridge.md`, `musicstate_helper.md` | `MusicState/*.lua` |
| Letras (ingreso y publicación) | `musicstate_lyrics.md`, `musicstate_lyrics_helper.md` | `MusicState/Nik_MusicState_PublishLyrics.lua` |

## Qué adjuntar según la tarea (Control remoto)

Punto de entrada: `remote_control.md` (arquitectura e índice). Docs en `_docs/features/`; código en `web/`.

| Tarea | Docs | Código |
|---|---|---|
| Popup nuevo, estilos, OptionsBar, posición del transporte | `remote_control_ui.md` | `modals/<nombre>/`, `modal-loader.js`, `styles.css`, `nsaudio_remote_control.html` |
| Lectura de estado nueva (poll, `ExtState`, `CMDSTATE`), dispatch del feed | `remote_control_protocol.md` | `RemoteControl/Nik_RemoteState_Poll.lua`, `core/wwr-dispatch.js`, `config.js` |
| Memoria de UI por proyecto, selector de tabs, watchdog | `remote_control_projects.md` | `core/tab-ui-memory.js`, `modals/project-tabs/`, `core/init.js` |
| Markers (seeker, popup, colores, seek relativo) | `remote_control_markers.md`, `remote_control_ui.md` | `modals/marker-browser/`, `markers/markers.js`, `RemoteControl/MarkerBars_common_logic.lua` |
| Playrate, ReaPitch, fader vertical y knob | `remote_control_faders.md`, `remote_control_ui.md` | `core/vertical-fader.js`, `core/fader-knob-svg.js`, `modals/playrate/`, `modals/reapitch/` |