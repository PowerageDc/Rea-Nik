// ms-stale.js — indicador de datos viejos (compartido por instrumentista y cantante)
//
// Si pasan más de NIK_MS_STALE_MS sin un TRANSPORT nuevo, marca la pantalla con
// la clase "is-stale" (el CSS de cada UI decide qué atenuar y dónde mostrar
// el cartel "SIN SEÑAL"). Mientras está stale, limita g_wwr_errcnt a 2 para que
// los reintentos de main.js queden cerca de 100 ms y la recuperación al volver
// la red sea rápida (ver musicstate_instrumentista.md §4.6 y §4.7).
//
// Requiere, ya cargados: main.js (g_wwr_errcnt), ms-dispatch.js (nikTransportAnchorMs).

var NIK_MS_STALE_MS = 1500;

function nikMsUpdateStaleIndicator(screenEl) {
    if (!screenEl) return;
    var last = (typeof nikTransportAnchorMs === "number") ? nikTransportAnchorMs : 0;
    var isStale = (performance.now() - last) > NIK_MS_STALE_MS;
    screenEl.classList.toggle("is-stale", isStale);
    if (isStale && typeof g_wwr_errcnt === "number" && g_wwr_errcnt > 2) g_wwr_errcnt = 2;
}