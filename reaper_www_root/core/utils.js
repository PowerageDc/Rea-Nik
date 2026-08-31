// core/utils.js — utilidades puras sin estado, sin dependencias cruzadas.
// Extraído de nsaudio_remote_control.html (ver MODULARIZACION_CONTROL_REMOTO.md).

function setTextForObject(obj, text) {
    if (obj.lastChild) obj.lastChild.nodeValue = text;
    else obj.appendChild(document.createTextNode(text));
}

function lumaOffset(c) {
    var c = c.substring(1);
    var rgb = parseInt(c, 16);
    var r = (rgb >> 16) & 0xff;
    var g = (rgb >> 8) & 0xff;
    var b = (rgb >> 0) & 0xff;
    var luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    function componentToHex(c) {
        var hex = c.toString(16);
        return hex.length == 1 ? "0" + hex : hex;
    }
    if (luma < 150) { r = r + 150; g = g + 150; b = b + 150 }
    if (luma > 150) { r = r - 120; g = g - 120; b = b - 120 }
    if (r < 0) { r = 0 }; if (g < 0) { g = 0 }; if (b < 0) { b = 0 }
    if (r > 255) { r = 255 }; if (g > 255) { g = 255 }; if (b > 255) { b = 255 }
    return "#" + componentToHex(r) + componentToHex(g) + componentToHex(b);
}

// Interpola entre dos colores hex ("#rrggbb") segun t (0..1)
function nikLerpColor(hexA, hexB, t) {
    t = Math.max(0, Math.min(1, t));
    var a = parseInt(hexA.slice(1), 16), b = parseInt(hexB.slice(1), 16);
    var ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255;
    var br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
    var r = Math.round(ar + (br - ar) * t);
    var g = Math.round(ag + (bg - ag) * t);
    var bl = Math.round(ab + (bb - ab) * t);
    return "#" + ((1 << 24) + (r << 16) + (g << 8) + bl).toString(16).slice(1);
}

// Gris en el default, verde hacia arriba, naranja hacia abajo, intensidad = distancia normalizada
function nikDeviationColor(value, defaultVal, minVal, maxVal) {
    if (value == defaultVal) return "#A8A8A8";
    if (value > defaultVal) {
        return nikLerpColor("#A8A8A8", "#00FF99", (value - defaultVal) / (maxVal - defaultVal));
    }
    return nikLerpColor("#A8A8A8", "#FF9500", (defaultVal - value) / (defaultVal - minVal));
}

function elAttribute(id, attribute, value) {
    if (document.getElementById(id)) {
        document.getElementById(id).setAttributeNS(null, attribute, value);
    }
}

function BtoMB(beats) {
    var mbM = Math.floor(beats / ts_numerator);
    var mbB = beats - (mbM * ts_numerator);
    return (mbM + "." + mbB)
}

function easeInOutCubic(t, b, c, d) {
    if ((t /= d / 2) < 1) {
        return c / 2 * t * t * t + b;
    }
    else { return c / 2 * ((t -= 2) * t * t + 2) + b; }
};