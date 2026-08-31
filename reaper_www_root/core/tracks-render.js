// core/tracks-render.js — animación de expandir/colapsar filas de track.
// Depende de core/state.js (trackHeightsAr, trackSendHwCntAr, transitions),
// core/utils.js (easeInOutCubic) y de requestAnimationFrame (polyfill
// global, todavía inline en el shell — pendiente de core/init.js).

function hitbox(id) {
    var thisTrackRow2 = document.getElementsByClassName("trackRow2")[id];
    var thisTrackRow2Svg = thisTrackRow2.firstChild.firstElementChild;
    var easingValue = 0;
    transitionTime = 10;

    if (trackHeightsAr[id] == 0) {
        iteration = 0;
        requestAnimationFrame(resizerDown);
        function resizerDown() {
            if (iteration < transitionTime) {
                easingValue = easeInOutCubic(iteration, 0, 1, transitionTime);
                if (easingValue <= 0.1) { easingValue = 0.01; }
                if (transitions == 0) { var row2scaleD = 37; }
                else { row2scaleD = easingValue * 37; }
                thisTrackRow2Svg.setAttributeNS(null, "viewBox", "0 1 320 " + row2scaleD);
                if (trackSendHwCntAr[id] > 0) {
                    if (transitions == 0) { var sendscaleD = 50; }
                    else { sendscaleD = easingValue * 50; }
                    for (x = 0; x < trackSendHwCntAr[id]; x++) {
                        thisSendSvg = document.getElementById("sendsTrack" + [id]).childNodes[x].firstElementChild.firstElementChild;
                        thisSendSvg.setAttributeNS(null, "viewBox", "0 0 320 " + sendscaleD)
                    }
                }
                iteration++;
                requestAnimationFrame(resizerDown);
            }
        }
    }
    else {
        iteration = 0;
        requestAnimationFrame(resizerUp);
        function resizerUp() {
            if (iteration < transitionTime) {
                easingValue = easeInOutCubic(iteration, 1, -1, transitionTime);
                if (transitions == 0) { var row2scaleU = 0.01; }
                else { row2scaleU = easingValue * 37; }
                thisTrackRow2Svg.setAttributeNS(null, "viewBox", "0 0 320 " + row2scaleU);
                if (trackSendHwCntAr[id] > 0) {
                    if (transitions == 0) { var sendscaleU = 0.01; }
                    else { sendscaleU = easingValue * 50; }
                    for (x = 0; x < trackSendHwCntAr[id]; x++) {
                        thisSendSvg = document.getElementById("sendsTrack" + [id]).childNodes[x].firstElementChild.firstElementChild;
                        thisSendSvg.setAttributeNS(null, "viewBox", "0 0 320 " + sendscaleU)
                    }
                }
                iteration++;
                requestAnimationFrame(resizerUp);
            }
        }
    }
    trackHeightsAr[id] ^= 1;
}