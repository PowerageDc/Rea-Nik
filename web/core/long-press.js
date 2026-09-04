// core/long-press.js
// Helper genérico de long-press (touch + mouse), extraído del patrón usado
// originalmente en modals/marker-browser/marker-browser.js
// (nikAttachMarkerLongPress). Sin barra de progreso ni otro feedback visual
// — quien lo use puede engancharse a onStart/onCancel si hace falta.
// marker-browser.js sigue con su propia implementación por ahora, no
// migrada a este helper (candidato a unificar en un cleanup futuro).
//
// Uso: nikAttachLongPress(el, { ms, moveTolerance, onLongPress, onStart, onCancel }).
// Marca el._nikSuppressClick = true cuando dispara, para que el onclick
// normal del elemento pueda ignorar ese click (mismo criterio que markers).

function nikAttachLongPress(el, options) {
    options = options || {};
    var ms = options.ms || 450;
    var moveTolerance = (options.moveTolerance != undefined) ? options.moveTolerance : 10;
    var onLongPress = options.onLongPress || function () {};
    var onStart = options.onStart || function () {};
    var onCancel = options.onCancel || function () {};

    var timer = null;
    var startX = 0, startY = 0;
    var fired = false;

    function start(x, y) {
        fired = false;
        startX = x; startY = y;
        onStart();
        timer = setTimeout(function () {
            fired = true;
            onLongPress();
        }, ms);
    }
    function cancel() {
        clearTimeout(timer);
        onCancel();
    }
    function move(x, y) {
        if (Math.abs(x - startX) > moveTolerance || Math.abs(y - startY) > moveTolerance) cancel();
    }

    el.addEventListener("touchstart", function (e) { start(e.touches[0].clientX, e.touches[0].clientY); }, { passive: true });
    el.addEventListener("touchmove", function (e) { move(e.touches[0].clientX, e.touches[0].clientY); }, { passive: true });
    el.addEventListener("touchend", function () { cancel(); if (fired) el._nikSuppressClick = true; }, { passive: true });
    el.addEventListener("touchcancel", cancel, { passive: true });
    el.addEventListener("mousedown", function (e) { start(e.clientX, e.clientY); });
    el.addEventListener("mousemove", function (e) { if (timer) move(e.clientX, e.clientY); });
    el.addEventListener("mouseup", function () { cancel(); if (fired) el._nikSuppressClick = true; });
    el.addEventListener("mouseleave", cancel);
}