# Feature — Control Remoto Web: protocolo y lectura de estado

Capa de datos del control remoto: cómo la web lee y escribe estado de
REAPER. Arquitectura general e índice de features: `remote_control.md`.
Memoria y selector por proyecto: `remote_control_projects.md`. UI:
`remote_control_ui.md`.

El protocolo de `main.js` (formato de comandos, `GET/`, `SET/`, `_RS...`)
está documentado en sus propios comentarios.

## 1. Patrón A: script Lua + ExtState + polling (default)

1. Un script Lua (o un módulo consumido por varios) lee o escribe estado
   real de REAPER en `ExtState` (`persist=false`, sección `"NikRemote"`).
2. La web dispara ese script como acción custom (`_RS...`, Command ID de
   `NIK_LUA_COMMANDS`, ver §8).
3. La web lee el resultado con `GET/EXTSTATE/NikRemote/<key>`, encadenado
   en la misma request que el `_RS`.

`reaper.GetExtState(section, key)` devuelve un solo string (`""` si no
existe), no un par `(ok, valor)`: tratarlo como par corta el script en
silencio sin aplicar nada.

## 2. Patrón B: `CMDSTATE` nativo encadenado al click

Para toggles ya expuestos como Command ID nativo de REAPER, sin Lua
propio ni `ExtState`. El click dispara la acción más un
`GET/<commandId>` en la misma request (sin esperar el poll de fondo), y
`;GET/<commandId>` se suma al final de `NIK_SLOW_POLL` (`config.js`) como
resync periódico. Al no ser `EXTSTATE`, no aplica la regla de §3 sobre
`Nik_RemoteState_Poll.lua`.

El feedback visual cambia el atributo `fill` de elementos SVG por `id`
desde el case `"CMDSTATE"` de `core/wwr-dispatch.js`. Es preferible a
alternar visibilidad de grupos duplicados por índice de `childNodes`, que
depende del whitespace del markup. Usos: `buttonMetro` (`40364`) y
`buttonSoloInFront` (`40745`, ver `remote_control_ui.md` §4).

## 3. Lectura de estado consolidada (`Nik_RemoteState_Poll.lua`)

Todas las lecturas de fondo van en un solo script con un solo Command ID:

```
Nik_RemoteState_Poll.lua
  ├─ ActiveProject_common_logic.write_active_project_name()
  ├─ lectura directa de Master_GetPlayRate + preserve pitch (40671)
  ├─ ReaPitchBus_common_logic.write_aggregated_state()
  └─ MarkerBars_common_logic.write_aggregated_state()
```

Agregar una lectura de fondo:

1. Sumar una sección en este script, o en el módulo `common_logic` del
   dominio.
2. Sumar su `GET/EXTSTATE/NikRemote/<key>` a `NIK_SLOW_POLL` en
   `config.js`. Sin esto la key se escribe pero nunca llega a la web.

Nunca un `_RS` nuevo encadenado al poll (ver §7, parpadeo del menú).

**Patrón de agregación** en los módulos: `read_aggregated_state()` (lógica
pura) y `write_aggregated_state()` (llama a la anterior y escribe
`ExtState`). Un `Nik_*_Read.lua` standalone queda como wrapper de una
línea sobre `write_aggregated_state()`.

## 4. Lecturas on-demand fuera del poll

Cuando el costo no justifica sumarlas al tick de 1000 ms, se disparan
encadenadas a un evento concreto (abrir un popup, boot, cambio de
proyecto):

- `Nik_ProjectTabs_Read.lua`: al abrir el popup de tabs
  (`remote_control_projects.md` §2).
- `Nik_Playrate_ReadTempoMap.lua`: boot, cambio de proyecto y apertura del
  popup de Playrate (`remote_control_faders.md` §6).

## 5. Dispatch del feed (`core/wwr-dispatch.js`, `wwr_onreply`)

- **Una excepción dentro de `wwr_onreply` congela el resto de la
  respuesta.** Corta el `for` del parser y nada de lo que venía después se
  procesa (nombre de proyecto en `-`, tracks del proyecto anterior, lista
  de tabs vacía). Ejemplo típico: llega un `SEND` de un track cuya fila ya
  se quitó del DOM tras cambiar a un proyecto con menos tracks.
- **Todo `getElementById` sobre filas dinámicas lleva guard** (`!= null`
  antes de usar el elemento), como hace el `case "TRACK"`. Lo mismo para
  los elementos de un modal: el `fetch` de `modal-loader.js` es async y un
  poll puede llegar antes de que el modal esté inyectado.
- **No asumir que todo case sigue el patrón `if (elemento) {...}`:**
  verificar caso por caso antes de sacar markup que `wwr-dispatch.js`
  referencia.
- **Los guards pueden esconder desincronizaciones HTML↔JS.** Si el `id`
  buscado ya no existe (típico tras rediseñar el markup), el guard falla
  en silencio: el estado cambia por detrás y la UI no se actualiza.
  Confirmar el `id` real tras cada rediseño.
- **Arrays por track:** al quitar una fila sobrante, el bloque
  correspondiente limpia todos los arrays indexados por track, incluidos
  `trackSendCntAr`, `trackRcvCntAr`, `trackHwOutCntAr`,
  `trackSendHwCntAr`, `trackPeakAr` y `recarmCountAr`. Todo array por
  track nuevo se limpia ahí. Sin eso:
  - el loop final sigue pidiendo `GET/TRACK/x/SEND/y` de tracks que ya no
    existen;
  - una fila recreada con el mismo índice no repinta su indicador si el
    valor coincide con el guardado;
  - `recarmCountAr` arrastra armados de tracks quitados.

  `recarmCountAr` se limpia con `0`: un `undefined` explícito hace que su
  `reduce` dé `NaN`.

## 6. Datos de protocolo reutilizables

- `TRANSPORT` siempre trae `tok[5]` (`measures.beats.hundredths`) y
  `tok[2]` (`position_seconds`), sin importar cómo esté seteado el ruler
  del proyecto. No hace falta leer `BEATPOS` ni inferir el formato.
- `TRANSPORT` y `TRACK` se piden cada 10 ms; el poll de fondo
  (`NIK_SLOW_POLL`), cada 1000 ms.
- Para derivar un valor que depende de la posición de reproducción, el
  patrón es enviar los datos crudos una sola vez (on-demand) y resolverlo
  en el cliente con campos que ya llegan en el poll rápido
  (`remote_control_faders.md` §6).

## 7. Gotchas de protocolo

- **Correr un ReaScript como acción hace parpadear el menú superior de
  REAPER** (cosmético, no corrompe Undo). Escala con la cantidad de `_RS`
  empaquetados en el mismo tick: por eso el poll de fondo es un solo
  script (§3).
- **`wwr_req_recur` con el mismo intervalo se empaqueta en una sola
  request HTTP**, aunque estén registrados en llamadas separadas.
  Desfasar los intervalos es la única forma de partir un bundle.
- **`SET/TRACK/x/B_SHOWINTCP/valor` no refresca el TCP visualmente**
  (salta `TrackList_AdjustWindows()`). El refresco lo hace
  `Nik_TrackVis_Refresh.lua` (ver `remote_control_ui.md` §6).

## 8. `config.js`: Command IDs y poll

- `NIK_LUA_COMMANDS`: Command ID de cada script `_RS...` que la web
  dispara. Son específicos de cada PC.
- `NIK_SLOW_POLL`: cadena de `GET/...` del poll de fondo (§3).
- Constantes de colores y timing, y `NIK_TRANSPORT_SCALE` (escala del
  bloque play/pause/stop).
- Los `commandId` hardcodeados en `config.js` actúan como fallback. Cómo
  se generan los reales en cada PC: `05_REAPACK_DEPLOY.md`.

## 9. Pendientes

- Decidir si los `commandId` de fallback de `config.js` se eliminan
  (error visible si falta `config.local.js`) o se mantienen con validación
  explícita. Hoy fallan en silencio si el generador no corrió en esa PC.