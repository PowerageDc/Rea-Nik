// mm-slider.js — slider horizontal propio para Monitor Mix.
//
// Reemplaza al <input type="range"> en esta UI: el nativo salta al valor en el
// down, antes de saber si el gesto es un scroll. Acá el valor solo se escribe
// al soltar un tap (en la línea) o al confirmarse el eje horizontal.
// Mismo contrato que nikCreateVerticalFader (core/vertical-fader.js), más
// isActive(). El contenedor (#sliderId) lo crea monitor-app.js; los hijos
// (línea, relleno, thumb) los crea este módulo.
// Depende de: NIK_FADER_DBLTAP_MS y nikVFaderCheckDoubleTap (core/vertical-fader.js).

var NIK_MM_SLIDER = {
    THUMB_PX: 28,          // diámetro visual del thumb
    HIT_HALF_PX: 22,       // medio ancho de la zona táctil del thumb (blanco de 44 px)
    AXIS_THR_LINE_PX: 8,   // movimiento para decidir eje, down sobre la línea
    AXIS_THR_THUMB_PX: 4,  // idem, down sobre el thumb
    TAP_MAX_MS: 350        // más que esto sin mover = hold, no cuenta como tap
};

function nikMmCreateSlider(config) {
    var el = document.getElementById(config.sliderId);
    var display = document.getElementById(config.displayId);
    if (!el) return null;

    var K = NIK_MM_SLIDER;
    var min = config.min, max = config.max, step = config.step;

    var line = document.createElement("div");
    line.className = "mm-sl-line";
    var fill = document.createElement("div");
    fill.className = "mm-sl-fill";
    var thumb = document.createElement("div");
    thumb.className = "mm-sl-thumb";
    thumb.style.width = K.THUMB_PX + "px";
    thumb.style.height = K.THUMB_PX + "px";
    el.appendChild(line);
    el.appendChild(fill);
    el.appendChild(thumb);

    var value = (config.initialValue != null) ? Number(config.initialValue) : Number(config.defaultValue);
    var dragging = false;   // eje horizontal confirmado
    var g = null;           // gesto en curso (null = ninguno)

    function clamp(v) {
        return v < min ? min : (v > max ? max : v);
    }

    function fracOf(v) {
        return (v - min) / (max - min);
    }

    function paint() {
        var f = fracOf(value);
        var usable = "(100% - " + K.THUMB_PX + "px) * " + f;
        thumb.style.left = "calc(" + usable + ")";
        fill.style.width = "calc(" + (K.THUMB_PX / 2) + "px + " + usable + ")";
        if (display) display.textContent = config.formatDisplay(value);
    }

    // frac (0..1) -> valor con paso aplicado
    function snap(frac) {
        if (frac < 0) frac = 0;
        if (frac > 1) frac = 1;
        return clamp(min + Math.round(frac * (max - min) / step) * step);
    }

    function fracFromX(clientX) {
        var usable = g.rect.width - K.THUMB_PX;
        if (usable <= 0) return 0;
        return (clientX - g.rect.left - K.THUMB_PX / 2 - g.grab) / usable;
    }

    function setFromX(clientX) {
        var v = snap(fracFromX(clientX));
        if (v === value) return false;
        value = v;
        paint();
        return true;
    }

    function endGesture(e) {
        if (g && el.releasePointerCapture) {
            try { el.releasePointerCapture(g.id); } catch (err) { /* sin captura */ }
        }
        g = null;
        dragging = false;
    }

    el.addEventListener("pointerdown", function (e) {
        if (g) return; // un solo dedo por slider
        if (e.pointerType === "mouse" && e.button !== 0) return;
        var rect = el.getBoundingClientRect();
        var usable = rect.width - K.THUMB_PX;
        var centerX = rect.left + K.THUMB_PX / 2 + fracOf(value) * (usable > 0 ? usable : 0);
        var onThumb = Math.abs(e.clientX - centerX) <= K.HIT_HALF_PX;
        g = {
            id: e.pointerId,
            type: e.pointerType,
            x0: e.clientX,
            y0: e.clientY,
            t0: performance.now(),
            rect: rect,
            onThumb: onThumb,
            grab: onThumb ? (e.clientX - centerX) : 0,
            axis: null
        };
        // Sin escribir nada: la intención se decide en move/up.
    }, false);

    el.addEventListener("pointermove", function (e) {
        if (!g || e.pointerId !== g.id || g.axis === "v") return;
        if (g.axis === null) {
            var dx = e.clientX - g.x0, dy = e.clientY - g.y0;
            var thr = g.onThumb ? K.AXIS_THR_THUMB_PX : K.AXIS_THR_LINE_PX;
            if (Math.max(Math.abs(dx), Math.abs(dy)) < thr) return;
            // Mouse: no hay scroll táctil que ceder, siempre horizontal.
            g.axis = (g.type === "mouse" || Math.abs(dx) >= Math.abs(dy)) ? "h" : "v";
            if (g.axis === "v") return; // el navegador scrollea; llegará pointercancel
            dragging = true;
            try { el.setPointerCapture(g.id); } catch (err) { /* sin captura */ }
        }
        if (setFromX(e.clientX) && config.onDragChange) config.onDragChange(value);
    }, false);

    el.addEventListener("pointerup", function (e) {
        if (!g || e.pointerId !== g.id) return;
        if (g.axis === "h") {
            if (config.onCommit) config.onCommit(value);
        } else if (g.axis === null) {
            // Tap: down + up sin superar el umbral de movimiento.
            if (g.onThumb) {
                // Sobre el thumb solo cuenta para el doble tap.
                if (nikVFaderCheckDoubleTap(config.key)) handle.reset();
            } else if (performance.now() - g.t0 <= K.TAP_MAX_MS) {
                setFromX(e.clientX);
                if (config.onDragChange) config.onDragChange(value);
                if (config.onCommit) config.onCommit(value);
            }
            // Línea con hold largo: no hace nada.
        }
        endGesture(e);
    }, false);

    // Scroll tomado a mitad de un arrastre, o gesto cancelado: si ya había
    // arrastre horizontal, se cierra con el valor actual para no dejar el
    // último envío sin el sufijo "e".
    el.addEventListener("pointercancel", function (e) {
        if (!g || e.pointerId !== g.id) return;
        if (g.axis === "h" && config.onCommit) config.onCommit(value);
        endGesture(e);
    }, false);

    // Con el eje horizontal confirmado, evita que una deriva vertical del dedo
    // haga que el navegador tome el gesto como scroll.
    el.addEventListener("touchmove", function (e) {
        if (dragging && e.cancelable) e.preventDefault();
    }, { passive: false });

    var handle = {
        setValue: function (v, opts) {
            value = clamp(min + Math.round((Number(v) - min) / step) * step);
            paint();
            if (!(opts && opts.silent) && config.onDragChange) config.onDragChange(value);
        },
        getValue: function () { return value; },
        reset: function () {
            handle.setValue(config.defaultValue);
            if (config.onCommit) config.onCommit(Number(config.defaultValue));
        },
        isActive: function () { return dragging; }
    };

    paint();
    return handle;
}