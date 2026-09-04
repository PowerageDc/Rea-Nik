// core/fader-knob-svg.js — calco del knob de fader nativo (trackRow2Svg, `<g class="fader">`
// en nsaudio_remote_control.html), como capa visual reutilizable para los faders
// verticales de popups (Playrate, ReaPitch). Convive con core/vertical-fader.js:
// el <input type="range"> sigue siendo la capa de interacción (drag/touch/teclado/
// doble-tap, ver .nikVFaderTrack en styles.css, ahora transparente); este módulo
// solo dibuja y mueve el knob encima, pointer-events:none.
//
// Mismos gradientes/paths que el fader de volumen de track (fGrad1-5 + outline),
// re-IDeados con sufijo único por instancia para evitar colisión de <linearGradient
// id> si se montan varios faders en la misma página (mismo problema que resuelve
// nikUniquifyGradientIds() en core/wwr-dispatch.js, ver 01_CONVENCIONES.md).
//
// Geometría lógica fija, viewBox "0 0 320 72" (mismo box que usa .nikVFaderTrack
// para el <input> antes de rotarlo):
//   - pista: x 20→300 (280 de largo), centrada en y (32→40, 8 de alto)
//   - knob: 46 de ancho x 36 de alto, centrado en y (18→54)
//   - recorrido del knob: x 20→254 (234 = 280 - 46)
// Para orientación vertical, el <svg> se monta con la clase
// .nikFaderKnobSvg--vertical (rotate(-90deg), ver styles.css) — el mismo asset
// horizontal sirve para las dos orientaciones, no se redibuja nada.

var nikFaderKnobSvgSeq = 0;

function nikCreateFaderKnobSvg(config) {
    // config: { mountEl, orientation: "vertical" | "horizontal" }
    var id = "nikFK" + (nikFaderKnobSvgSeq++);
    var trackX = 20, trackW = 280, knobW = 46, knobTravel = trackW - knobW; // 234, simétrico: margen 20 a cada lado en un viewBox de 320
    var orientClass = (config.orientation == "vertical") ? " nikFaderKnobSvg--vertical" : "";

    var svgNS = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("class", "nikFaderKnobSvg" + orientClass);
    svg.setAttribute("viewBox", "0 0 320 72");

    svg.innerHTML =
        '<rect x="' + trackX + '" y="32" width="' + trackW + '" height="8" fill="#262626" />' +
        '<g id="' + id + 'Knob" transform="translate(' + trackX + ',18)">' +
        '<g>' +
        '<linearGradient id="' + id + 'g1" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#212121"/><stop offset="1" stop-color="#949494"/>' +
        '</linearGradient>' +
        '<rect x="38" y="0.5" fill="url(#' + id + 'g1)" width="8" height="35" />' +
        '<linearGradient id="' + id + 'g2" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset="0.9991" stop-color="#7A7A7A"/>' +
        '</linearGradient>' +
        '<path fill="url(#' + id + 'g2)" d="M26,0.5h12v35H26c-1.1,0-2-0.9-2-2v-31C24,1.4,24.9,0.5,26,0.5z" />' +
        '<linearGradient id="' + id + 'g3" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#9C9C9C"/><stop offset="1" stop-color="#4D4D4D"/>' +
        '</linearGradient>' +
        '<path fill="url(#' + id + 'g3)" d="M21,35.5c1.1,0,2-0.9,2-2v-31c0-1.1-0.9-2-2-2H9v35H21z" />' +
        '<linearGradient id="' + id + 'g4" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset="0.1231" stop-color="#F2F2F2"/>' +
        '<stop offset="0.3517" stop-color="#CFCFCF"/><stop offset="0.6607" stop-color="#979797"/>' +
        '<stop offset="1" stop-color="#525252"/>' +
        '</linearGradient>' +
        '<rect x="1" y="0.5" fill="url(#' + id + 'g4)" width="8" height="35" />' +
        '</g>' +
        '<path d="M1,0.5h20c1.1,0,2,0.9,2,2v31c0,1.1-0.9,2-2,2H1V0.5 M24,2.5c0-1.1,0.9-2,2-2h20v35H26c-1.1,0-2-0.9-2-2V2.5 M0.5,0v36H21c1.4,0,2.5-1.1,2.5-2.5c0,1.4,1.1,2.5,2.5,2.5h20.5V0H26c-1.4,0-2.5,1.1-2.5,2.5C23.5,1.1,22.4,0,21,0H0.5L0.5,0z" />' +
        '<path opacity="0.1" fill="#FFFFFF" d="M2,1.5h19c0.6,0,1,0.4,1,1v31c0,0.6-0.4,1-1,1H2V1.5 M25,2.5c0-0.6,0.4-1,1-1h19v33H26c-0.6,0-1-0.4-1-1V2.5 M1,0.5v35h20c1.1,0,2-0.9,2-2v-31c0-1.1-0.9-2-2-2H1L1,0.5z M24,2.5v31c0,1.1,0.9,2,2,2h20v-35H26C24.9,0.5,24,1.4,24,2.5L24,2.5z" />' +
        '<linearGradient id="' + id + 'g5" x1="0" y1="0" x2="0" y2="1">' +
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="0.5" stop-color="#FFFFFF"/>' +
        '</linearGradient>' +
        '<path opacity="0.33" fill="url(#' + id + 'g5)" d="M26,35.5h1v-1h-1c-0.6,0-1-0.4-1-1v-31c0-0.6,0.4-1,1-1h1v-1h-1c-1,0-1.8,0.7-2,1.6v31.8C24.2,34.8,25,35.5,26,35.5z" />' +
        '</g>';

    config.mountEl.appendChild(svg);
    var knobGroup = document.getElementById(id + "Knob");

    return {
        setFraction: function (f) {
            if (f < 0) f = 0; if (f > 1) f = 1;
            var x = trackX + f * knobTravel;
            knobGroup.setAttribute("transform", "translate(" + x + ",18)");
        }
    };
}