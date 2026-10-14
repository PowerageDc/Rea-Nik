# Feature — MusicState: cómo testear la sincronización y las UIs

Pruebas de la capa de sincronización y de las UIs web (instrumentista,
cantante). Las pruebas de otras capas viven con su código (§7). Mecanismos
probados: `musicstate_sync.md`.

## 1. En dev (misma PC + celular por Wi-Fi)

Abrir el prompter en el navegador de la PC y en el celular a la vez, con el
celular al lado del monitor. Chequeos en la consola de la PC:

- `nikTransportPlayState` da `1` en play.
- `JSON.stringify(nikMusicStateTimesigMap)` en un proyecto 4/4 sin markers
  da `[{"bar":1,"num":4,"den":4}]`.
- `nikTransportPlayRate` refleja el playrate ~1 s después de cambiarlo.
- `nikMusicStateLookaheadSec = X` ajusta el lookahead de oído (efecto en el
  siguiente render).

**Caché del navegador.** El servidor de REAPER no manda cabeceras
anti-caché y `config.local.js` se carga por XHR síncrono. Tras editar
scripts, recarga forzada (Ctrl+F5; en el celular, borrar la caché del
sitio o usar pestaña privada) antes de concluir que un cambio no
funciona.

## 2. Poll lento (la extrapolación debe sostener los acordes)

`g_wwr_req_recur[0][1] = 500` (el índice 0 es `TRANSPORT`). Restaurar con
`g_wwr_req_recur[0][1] = 100`.

## 3. Ritmo real de respuestas

Mide 10 s y se restaura solo:

```js
(function(){var t=[],o=wwr_onreply;wwr_onreply=function(r,d){t.push(performance.now());return o(r,d)};setTimeout(function(){wwr_onreply=o;var g=t.slice(1).map(function(x,i){return Math.round(x-t[i])});console.log("intervalos ms:",g.join(","))},10000)})()
```

## 4. Corte de red

DevTools → Network → Offline con la canción en play. Esperado:

- A los ~1,5 s aparecen el cartel y el bloque atenuado.
- Los acordes siguen avanzando hasta ~8 s y ahí se detienen (tope).
- Al volver a "No throttling" el cartel desaparece en ~100–150 ms y la
  tira salta a la posición real.

Variante: hacer stop o seek en REAPER durante el corte y verificar que al
reconectar la pantalla muestra la posición nueva.

**Diagnóstico de recuperación.** Recargar la página antes (para no duplicar
listeners). Imprime `errcntAlVolver`, `primerReplyMs` y `cartelMs`:

```js
(function(){var o=wwr_onreply;window.addEventListener("online",function(){var t0=performance.now(),e0=g_wwr_errcnt,tr=null,el=document.querySelector(".ms-screen");wwr_onreply=function(r,d){if(tr===null)tr=Math.round(performance.now()-t0);return o(r,d)};var iv=setInterval(function(){if(!el.classList.contains("is-stale")){clearInterval(iv);wwr_onreply=o;console.log({errcntAlVolver:e0,primerReplyMs:tr,cartelMs:Math.round(performance.now()-t0)})}},10)})})()
```

## 5. Logging del cambio de proyecto (`NIK_MS_DEBUG`)

`NIK_MS_DEBUG` (`ms-dispatch.js`, `false` por defecto) activa `nikMsLog`:
imprime en consola, con timestamp, estas etiquetas: `MARKERS_IN`,
`NAME_CHANGE`, `SWITCH` / `SWITCH_SKIP`, `RESET`, `HARMONY_IN`,
`SECTION_SHIFT` / `SECTION_JUMP`, `CHORDS_SHIFT` / `CHORDS_JUMP`.
`MARKERS_IN` sale cada 500 ms (ruido: filtrarlo).

Esperado: con el tab quieto, ningún `SWITCH`. Al cambiar de tab,
`SWITCH markers` seguido de `SECTION_JUMP` y `CHORDS_JUMP` casi juntos y,
~400 ms después, `NAME_CHANGE` con `SWITCH_SKIP name`. Útil para datos
colgados o fades dobles al cambiar de proyecto.

## 6. Prueba de estrés física

Hecha en sala con router propio (incluso con WAN inestable). Repetir si
cambia la red o la sala: canción entera en play, corte de Wi-Fi del
celular de 3, 5 y 10 s, stop/seek en REAPER durante el corte largo y 2–3
celulares. El cartel debe aparecer solo en cortes reales y los acordes
seguir alineados con los de la PC.

## 7. Pruebas de otras capas

| Qué | Dónde |
|---|---|
| Transposición, carry-over y silencio, consultas de lyrics (`CurrentLyric`, `LyricEnded`, `NextDistance`) y lead | `musicstate_client.md` §3 |
| Protocolo `ProjExtState` → `ExtState` (`Nik_MusicState_ProbeExtState.lua`) y "el dato no llega" | `musicstate_data_model.md` §5 |
| Round-trip Helper → publicación → cliente, cambio de proyecto, republicación de lyrics | `musicstate_bridge.md` §6 |
