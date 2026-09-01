# Contexto para retomar — Bug de memoria de UI al cambiar de tab (proyecto)

Este doc es para pegar al arrancar la conversación nueva. Traigo también los
logs de consola pedidos (`[nikDebug] ...`) generados con la instrumentación
descripta más abajo — analizalos contra la hipótesis antes de proponer nada.

## Proyecto
NikRemote — control remoto web (HTML/JS) para REAPER. Convenciones en
`01_CONVENCIONES.md` / `00_CONTEXTO_GENERAL.md` (adjuntos como project files).
Feature doc de referencia: `remote_control.md` (sección "Memoria de UI por
proyecto — `core/tab-ui-memory.js`").

**Modo de trabajo:** resolver por pasos, esperar confirmación antes de
avanzar. Diffs en formato buscar/reemplazar, nunca archivos regenerados
completos. Nunca asumir sin ver el código real — si falta un archivo,
pedirlo antes de proponer un fix.

## Bug concreto

Mecanismo afectado: `nikTabUiMemory` (`core/tab-ui-memory.js`) — recuerda
qué tracks están con el fader desplegado (`expandedTracks`), por proyecto
activo (tab). Se dispara desde el handler de `active_project_name` en
`core/wwr-dispatch.js` (`nikTabMemorySave` → `nikTabMemoryResetRenderCaches`
→ `nikTabMemoryRestore`).

**Repro:** dos proyectos abiertos como tabs — tab1 con 10 tracks, tab2 con 6.
Se navega 1⇒2⇒1 (ida y vuelta) usando el selector de tabs o los botones
⏮/⏭ Tab.

**Síntomas observados** (en orden de investigación):

1. Sin nada desplegado, 1⇒2⇒1: todo OK.
2. Con **Master expandido** en tab1, 1⇒2⇒1: los tracks 7-10 (los que no
   existen en tab2) aparecen **desplegados** al volver a tab1 — sin que el
   usuario los haya tocado.
3. Con **Master colapsado** en tab1, 1⇒2⇒1: los tracks 7-10 aparecen
   **colapsados** al volver.
4. Con Master colapsado, desplegando explícitamente uno de los tracks 7-10
   (ej. track 9) y haciendo 1⇒2⇒1: ese track vuelve **colapsado** — no
   recuerda el estado que el usuario sí le dio.

Lectura: el estado final de los tracks que no existen en el proyecto más
chico (7-10) parece **copiar el estado de Master**, ignorando su propio
estado real (punto 4 lo prueba: la memoria individual de esos tracks no
funciona en absoluto).

Diagnóstico adicional del propio usuario (Nico): al tocar un track 7-10 que
aparece "ya desplegado", SÍ dispara la animación de apertura (la que corre
cuando `trackHeightsAr[id]==0`) — es decir, el estado interno (`trackHeightsAr`)
parece estar en 0 (colapsado) aunque el render visual (viewBox del SVG) ya
esté en la altura expandida. Estado lógico correcto, render visual
desincronizado — o eso parece a nivel código estático.

## Hipótesis confirmada (parcialmente, por análisis estático)

`nTrack` (global en `core/state.js`) lo actualiza el poll nativo
`NTRACK;TRACK` de REAPER, que corre cada 10ms — mucho más rápido que la
detección de cambio de `active_project_name` (poll lento de 1000ms, o el
on-demand del selector de tabs). Son dos streams de poll **completamente
independientes**, sin sincronización entre sí (viajan en requests HTTP
separadas).

Consecuencia: al salir de tab1 (10 tracks) hacia tab2 (6 tracks), es muy
probable que quede `nTrack == 6` (ya el valor del proyecto nuevo) para
cuando `nikTabMemorySave("tab1")` finalmente corre (disparado por la
detección, más lenta, del cambio de `active_project_name`). El loop:

```javascript
function nikTabMemorySnapshot() {
    var expandedTracks = {};
    for (var i = 0; i <= nTrack; i++) {          // nTrack ya vale 6, no 10
        if (trackHeightsAr[i] == 1) expandedTracks[i] = 1;
    }
    return { expandedTracks: expandedTracks };
}
```

nunca llega a mirar los índices 7-10 — cualquier desplegado ahí se pierde
**antes de guardarse**. Esto **explica completamente el punto 4** (no
recuerda tracks individuales altos).

**Lo que todavía NO explica:** por qué el estado final de esos tracks
*copia* el de Master en vez de simplemente quedar en 0/colapsado por
default (que sería lo esperable si el dato simplemente se pierde). Esta
parte sigue sin una causa confirmada por lectura de código — necesita los
logs de una corrida real para confirmar o descartar.

## Instrumentación ya aplicada (temporal, para debug — revertir al cerrar)

5 líneas de `console.log("[nikDebug] ...")` agregadas en:
- `core/tab-ui-memory.js` → `nikTabMemorySave()` (loguea snapshot guardado)
- `core/tab-ui-memory.js` → `nikTabMemoryRestore()` (loguea `nTrack`, cantidad
  de elementos `.trackRow2` en el DOM, el objeto `saved.expandedTracks`, y
  por cada índice donde decide actuar: su `trackHeightsAr` previo,
  `shouldBeExpanded`, y si el elemento DOM existía)
- `core/wwr-dispatch.js` → creación de shell de track nuevo (loguea idx)
- `core/wwr-dispatch.js` → remoción de track sobrante (loguea idx removido y
  su `trackHeightsAr` justo antes de borrarlo)
- `core/wwr-dispatch.js` → handler de `active_project_name`, ANTES de
  `nikTabMemorySave` (loguea el valor de `nTrack` en el instante exacto en
  que se detecta el cambio de proyecto — este es el dato clave para
  confirmar/descartar la hipótesis de arriba)

## Qué necesito que hagas en la conversación nueva

1. Voy a pegar el output de consola completo (con el orden real en que
   llegaron las líneas) del repro del **punto 2** (Master expandido +
   track 9 también expandido, 1⇒2⇒1).
2. Cruzalo contra la hipótesis de arriba: ¿`nTrack` efectivamente ya vale 6
   en el momento del `SAVE` de tab1? ¿Y en el `RESTORE` de vuelta a tab1,
   ya vale 10, o también está atrasado?
3. Con eso, confirmá (o refutá) el mecanismo exacto de por qué los tracks
   altos terminan copiando el estado de Master, y proponé el fix — no antes
   de tener el dato concreto de los logs.
4. Si el fix implica no confiar en `nTrack` en vivo para los loops de
   snapshot/restore (ej. usar el conteo real de `.trackRow2` en el DOM, o
   diferir el restore hasta que el conteo de tracks coincida con el
   proyecto destino), planteá el approach y esperá confirmación antes de
   escribir el diff — por el modo de trabajo habitual.

## Archivos relevantes (los voy a volver a adjuntar si hacen falta)
`core/tab-ui-memory.js`, `core/wwr-dispatch.js`, `core/state.js`,
`core/tracks-render.js`, `nsaudio_remote_control.html`. Puede hacer falta
`core/init.js` si querés confirmar el intervalo exacto del poll rápido
`NTRACK;TRACK` (todavía no lo compartí en esta sesión).

## Ya cerrado en esta misma investigación (no reabrir)
- **Bug "Master no persiste por tab"**: resuelto. Causa: el loop de
  `nikTabMemorySnapshot`/`nikTabMemoryRestore` arrancaba en `i = 1`,
  salteando el índice 0 (Master, que usa el mismo mecanismo que un track
  normal — ver `track0`/`hitbox(0)` en el HTML). Fix aplicado: arrancar
  ambos loops en `i = 0`. Confirmado funcionando por Nico.
