# Contexto de Debug — Undo espurio por scripts vía Web Remote (NikRemote)

Documento de traspaso para retomar en otra conversación. Complementa (no
reemplaza) `00_CONTEXTO_GENERAL.md` y `01_CONVENCIONES.md` del proyecto.

## Qué se estaba haciendo

Migración de la sección de semitonos de ReaPitch a patrón readout+modal
(como playrate), + fix de bug de nombre de proyecto no actualizado, + fix
de bug de lista de tracks fantasma al cerrar proyecto. Todo eso **ya
funciona y está cerrado**. En el camino apareció un bug serio no
relacionado a esas features puntuales, que es el foco de este documento.

## El bug encontrado (grave, ya mitigado)

**Síntoma:** ejecutar un script Lua repetidamente **vía el mecanismo `_RS`
del control remoto web** (`wwr_req_recur`, en loop continuo) genera puntos
de undo reales acumulados, etiquetados "ReaScript: Run", que terminan
bloqueando operaciones normales (grabar, editar) porque el Undo History
queda atascado deshaciendo esos puntos fantasma en vez de las acciones
reales del usuario.

**Confirmado por descarte:**
- Pasa con **cualquier** script ejecutado así, no es específico de un
  script en particular (se probó con 3 scripts distintos: lectura de
  nombre de proyecto, lectura de ReaPitch, lectura de playrate — este
  último preexistente, corría así desde antes de esta sesión sin que se
  hubiera notado/reportado el problema).
- **No** es cuestión de frecuencia ni de cantidad de ejecuciones: correr
  el mismo script 10-20 veces seguidas **a mano** desde el Action List
  (rápido, simulando alta frecuencia) **no** genera undo real. Solo
  aparece cuando el disparo es vía `_RS` del remoto en loop
  (`wwr_req_recur`).
- El panel docked de Undo History (a la derecha de Help) sí muestra
  "ReaScript: Run" incluso en ejecución manual repetida, pero eso es
  cosmético — `Edit > Undo` sigue mostrando correctamente la última
  acción real del usuario en ese caso. El bug real (Undo real
  contaminado, no solo el panel) solo aparece con el patrón
  `wwr_req_recur` + `_RS`.
- No se encontró documentación oficial de REAPER/SWS que confirme el
  mecanismo exacto. Hipótesis manejadas y descartadas por evidencia:
  - ~~Es por llamar `SetExtState` repetidamente~~ → descartado (ejecución
    manual repetida con `SetExtState` no rompe nada).
  - ~~Es por un script específico mal escrito~~ → descartado (pasa con
    los 3 scripts, incluido uno preexistente y ya probado en producción).

**Conclusión operativa:** el problema está específicamente en el
mecanismo de disparo **recurrente vía `_RS` desde el remoto**
(`wwr_req_recur` con un Command ID de ReaScript adentro), no en el
contenido de los scripts ni en la frecuencia de ejecución per se.

## Regla nueva a incorporar en `01_CONVENCIONES.md`

> Ningún script custom (Command ID `_RS...`) debe ejecutarse dentro de un
> poll recurrente (`wwr_req_recur`). Es seguro dispararlo puntual
> (`wwr_req`, un solo tiro) desde un click o acción discreta del usuario
> en el remoto (ej: botón Tab, apertura de un modal, commit de un
> slider). El poll de fondo recurrente debe limitarse a lecturas pasivas
> (`GET/EXTSTATE`, `GET/`), nunca a comandos `_RS`.

*(Pendiente: agregar esto formalmente al archivo de convenciones — no se
hizo todavía en esta sesión, solo se aplicó en la práctica.)*

## Estado actual del código (`nsaudio_remote_control.html`)

- `NIK_SLOW_POLL`: quedó reducido a **solo** `GET/EXTSTATE/...` (pasivo,
  sin ningún `_RS`), corriendo en `wwr_req_recur(NIK_SLOW_POLL, 1000)`
  dentro de `init()`.
- `NIK_ONDEMAND_READS`: variable nueva, junta `ACTIVEPROJECT_CMD_READ +
  PLAYRATE_CMD_READ + REAPITCH_CMD_READ` + los `GET/EXTSTATE`
  correspondientes. Se dispara puntual (`wwr_req`, no recurrente) desde:
  - Botones Tab ⏮/⏭ (ya estaba así, se mantuvo).
  - `nikOpenPlayrateModal()` — al abrir el modal.
  - `nikOpenReaPitchModal()` — al abrir el modal.
  - `nikPlayrateSliderCommit()` — al soltar el slider.
  - `nikReaPitchSliderCommit()` — al soltar el slider.
- Con esto se resolvieron los bugs colaterales que habían aparecido al
  sacar el polling de fondo (sliders volviendo a 100/0 solos, popups sin
  leer el estado real al abrir).
- El watchdog `nikCheckProjectNameWatchdog` (para limpiar el nombre de
  proyecto si REAPER cierra del todo) quedó implementado pero **su
  utilidad depende de que algo siga escribiendo `active_project_name`
  regularmente** — con el poll de fondo ahora pasivo, hay que confirmar
  si sigue teniendo sentido tal cual, o si hay que revisarlo junto con lo
  de abajo.

## Pendiente inmediato (2 puntos, en este orden)

### 1. Quick fix menor (bajo riesgo, no aplicado todavía)
Agregar `NIK_ONDEMAND_READS` como disparo único al cargar la página
(dentro de `init()`), para que abrir la UI con un proyecto ya abierto en
REAPER muestre datos frescos desde el primer instante, en vez de lo
último que haya quedado en ExtState de una sesión anterior.

**No resuelve** el caso de abrir/cambiar de proyecto en REAPER *mientras*
la UI ya está abierta e inactiva — ahí no hay ningún disparador posible
con el approach actual (ver punto 2).

### 2. Investigar patrón `reaper.defer()` como reemplazo de fondo (no probado)
Hipótesis: un script persistente iniciado una vez (Action List, o
autoarranque vía SWS "run on startup"), que loopea con `reaper.defer()`
y escribe `SetExtState` cada ~1 segundo **desde adentro de REAPER**
(nunca disparado por `_RS` vía web), sería mecánicamente equivalente a
"ejecución manual repetida" — que ya se confirmó que NO genera undo
espurio. Si se valida, permitiría volver a tener sync automático en
background (nombre de proyecto, playrate, semitonos) sin el riesgo que
causó todo este debug.

**Antes de migrar nada a este patrón**, hace falta un test de validación:
1. Armar un script mínimo: `reaper.defer(loop)` que solo haga
   `SetExtState("NikRemote", "test_heartbeat", tostring(os.time()), false)`
   cada ~1 segundo, nada más.
2. Arrancarlo una vez desde el Action List y dejarlo corriendo un rato
   largo (¿15-30 min?) mientras se opera normal en REAPER: agregar
   tracks, grabar, deshacer cosas reales.
3. Confirmar que el Undo real (`Edit > Undo`, no solo el panel docked)
   **no** se contamina con "ReaScript: Run" ni bloquea nada.

Si el test pasa: migrar los 3 scripts de lectura (`Nik_ActiveProject_Read`,
`NikRemote_PlayRate_Read`, `NikRemote_ReaPitch_Read`) a este patrón
`defer()`, y **sacar** toda la lógica on-demand recién armada en Tabs/
modales/sliders (volvería a ser innecesaria).

Si el test falla (contamina igual): descartar `defer()` también, y quedarse
definitivamente con el approach on-demand actual — aceptando como
limitación permanente que los readouts solo se refrescan con interacción
del usuario en el remoto.

## Archivos relevantes de esta sesión

- `nsaudio_remote_control.html` — UI del control remoto (todos los diffs
  de esta sesión ya aplicados por el usuario).
- `Nik_ActiveProject_Read.lua` + `ActiveProject_common_logic.lua` —
  nuevos, creados hoy.
- `NikRemote_TabNext.lua` / `NikRemote_TabPrev.lua` — refactorizados hoy
  para usar el módulo de arriba vía `dofile`.
- `NikRemote_ReaPitch_Read.lua` + `ReaPitchBus_common_logic.lua` —
  preexistentes, sin cambios de contenido (solo cambió cómo/cuándo se
  invocan desde la web).
- `NikRemote_PlayRate_Read.lua` / `NikRemote_PlayRate_Set.lua` /
  `NikRemote_PlayRate_TogglePreservePitch.lua` — preexistentes, sin
  cambios de contenido.

## Modo de trabajo (recordatorio para la próxima conversación)

Mismas convenciones del proyecto: resolver por pasos con confirmación
antes de avanzar, no asumir sin ver el código real (pedir archivos si
hace falta), diffs en formato buscar/reemplazar (nunca regenerar
archivos completos), avisar antes de escribir más de 300 líneas,
conversación en español.
