// core/vertical-fader.js — fader vertical modular, para popups (Playrate, ReaPitch).
// Reutiliza <input type="range"> nativo, rotado por CSS (ver .nikVFaderTrack en
// styles.css) — drag/touch nativo del input, sin reinventar el manejo de eventos
// que sí hace falta en core/faders.js (faders de volumen, SVG custom por track).
// Depende de: NIK_FADER_DBLTAP_MS (config.js).

var nikVFaderLastTapAr = {};

function nikVFaderCheckDoubleTap(key) {
    var now = (new Date).getTime();
    var last = nikVFaderLastTapAr[key] || 0;
    if ((now - last) < NIK_FADER_DBLTAP_MS) {
        nikVFaderLastTapAr[key] = 0;
        return true;
    }
    nikVFaderLastTapAr[key] = now;
    return false;
}

function nikCreateVerticalFader(config) {
    // config: {
    //   key,                  string único del fader (ej. "playrate", "reapitch")
    //   sliderId, displayId,  ids de los elementos ya presentes en el HTML del modal
    //   min, max, step, defaultValue, initialValue,
    //   formatDisplay(value),
    //   onDragChange(value),  feedback local sin red (equivalente a *_SliderInput de hoy)
    //   onCommit(value)       dispara el wwr_req real (equivalente a *_SliderCommit de hoy)
    //   }
    var slider = document.getElementById(config.sliderId);
    var display = document.getElementById(config.displayId);
    if (!slider) return null;

    slider.min = config.min;
    slider.max = config.max;
    slider.step = config.step;
    slider.value = (config.initialValue != null) ? config.initialValue : config.defaultValue;
    if (display) display.textContent = config.formatDisplay(slider.value);

    var knob = null;
    if (config.knobMountId) {
        var knobMountEl = document.getElementById(config.knobMountId);
        if (knobMountEl) knob = nikCreateFaderKnobSvg({ mountEl: knobMountEl, orientation: config.knobOrientation || "vertical" });
    }
    function updateKnob(value) {
        if (knob) knob.setFraction((value - config.min) / (config.max - config.min));
    }
    updateKnob(slider.value);

    slider.addEventListener("input", function () {
        if (display) display.textContent = config.formatDisplay(slider.value);
        updateKnob(slider.value);
        if (config.onDragChange) config.onDragChange(slider.value);
    }, false);

    slider.addEventListener("change", function () {
        if (config.onCommit) config.onCommit(slider.value);
    }, false);

    function tryDoubleTap(event) {
        if (nikVFaderCheckDoubleTap(config.key)) {
            if (event.preventDefault) event.preventDefault();
            handle.reset();
            return true;
        }
        return false;
    }
    slider.addEventListener("mousedown", tryDoubleTap, false);
    slider.addEventListener("touchstart", function (event) {
        if (event.touches.length > 0) tryDoubleTap(event);
    }, false);

    var handle = {
        setValue: function (value, opts) {
            slider.value = value;
            if (display) display.textContent = config.formatDisplay(value);
            updateKnob(value);
            if (!(opts && opts.silent) && config.onDragChange) config.onDragChange(value);
        },
        getValue: function () { return slider.value; },
        reset: function () {
            handle.setValue(config.defaultValue);
            if (config.onCommit) config.onCommit(config.defaultValue);
        },
        stepBy: function (direction) {
            var next = Number(slider.value) + (direction * config.step);
            if (next < config.min) next = config.min;
            if (next > config.max) next = config.max;
            handle.setValue(next);
            if (config.onCommit) config.onCommit(next);
        }
    };
    return handle;
}