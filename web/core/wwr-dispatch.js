// core/wwr-dispatch.js
// wwr_onreply() — parser central del feed de REAPER (main.js llama a esta
// función global en cada respuesta del poll). Extraído sin cambios de
// nsaudio_remote_control.html como parte de la modularización (ver
// MODULARIZACION_CONTROL_REMOTO.md).
// Depende de: config.js, core/utils.js, markers/markers.js, core/state.js,
// core/faders.js, core/tracks-render.js — deben cargarse antes en el HTML.

// Los templates SVG que se clonan por track (trackRow1Svg, trackRow2Svg,
// trackSendSvg) traen <linearGradient id="..."> fijos. cloneNode(true)
// duplica esos ids tal cual — el navegador resuelve toda referencia
// fill="url(#id)" contra la PRIMERA ocurrencia de ese id en el documento.
// Mientras esa primera ocurrencia esté visible, el resto de los clones le
// "prestan" el gradiente sin problema; si ese track puntual queda oculto
// (display:none, ver TracksVis), esa definición deja de renderizarse y
// TODOS los clones que dependían de ella pierden el fill (fondo blanco
// desaparece, se ve el color de fondo del track). Se llama una vez por
// clon, apenas se inserta, con un sufijo único (el índice del track).
function nikUniquifyGradientIds(cloneRoot, suffix) {
    var grads = cloneRoot.querySelectorAll("linearGradient[id]");
    for (var g = 0; g < grads.length; g++) {
        var oldId = grads[g].id;
        var newId = oldId + "_" + suffix;
        grads[g].id = newId;
        var refs = cloneRoot.querySelectorAll("[fill=\"url(#" + oldId + ")\"]");
        for (var r = 0; r < refs.length; r++) {
            refs[r].setAttributeNS(null, "fill", "url(#" + newId + ")");
        }
    }
}

function wwr_onreply(results) {
    /*var resultsDisplay = document.getElementById("_results");
     if(resultsDisplay!=null){
         var _backLoaded = document.getElementById("backLoad");
         _backLoaded.style.display = "block";
         resultsDisplay.innerHTML = results;
         } */

    var ar = results.split("\n");
    for (var x = 0; x < ar.length; x++) {
        var tok = ar[x].split("\t");
        if (tok.length > 0) switch (tok[0]) {
            case "TRANSPORT":
                if (tok.length > 4) {
                    var backLoaded = document.getElementById("backLoad");
                    if (backLoaded != null) {
                        if (tok[1] != last_transport_state) {
                            last_transport_state = tok[1];
                            document.getElementById("playButtonOff").style.visibility = (last_transport_state & 1) ? "hidden" : "visible";
                            document.getElementById("playButtonOn").style.visibility = (last_transport_state & 1) ? "visible" : "hidden";
                            document.getElementById("pauseButtonOff").style.visibility = (last_transport_state & 2) ? "hidden" : "visible";
                            document.getElementById("pauseButtonOn").style.visibility = (last_transport_state & 2) ? "visible" : "hidden";
                            document.getElementById("record_off").style.visibility = (last_transport_state & 4) ? "hidden" : "";
                            document.getElementById("record_on").style.visibility = (last_transport_state & 4) ? "visible" : "";
                            document.getElementById("armed_text").style.visibility = (last_transport_state & 4) ? "hidden" : "";
                            document.getElementById("armed_count").style.visibility = (last_transport_state & 4) ? "hidden" : "";
                            document.getElementById("abort_text").style.visibility = (last_transport_state & 4) ? "visible" : "";
                            document.getElementById("abort_cross").style.visibility = (last_transport_state & 4) ? "visible" : "";
                        }
                        if (tok[3] != last_repeat) {
                            last_repeat = tok[3];
                            document.getElementById("repeat_off").style.visibility = (last_repeat > 0) ? "hidden" : "";
                            document.getElementById("repeat_on").style.visibility = (last_repeat > 0) ? "visible" : "";
                        }
                        var statusDisplay = document.getElementById("status");

                        // Formato del readout de posición: toggle sticky vía long tap en
                        // #status (nikPositionDisplayMode, ver core/init.js), independiente
                        // del ruler real del proyecto. tok[2]=position_seconds, tok[5]=
                        // position_string_beats (measures.beats.hundredths) — ambos vienen
                        // siempre en TRANSPORT sin importar cómo esté seteado el ruler.
                        if (nikPositionDisplayMode == "minsec") {
                            statusPosition[0] = nikFormatMinSec(parseFloat(tok[2]));
                            statusPosition[1] = "Minutes:Seconds";
                        }
                        else {
                            statusPosition[0] = tok[5];
                            statusPosition[1] = "Measures.Beats";
                        }
                        document.getElementById("timeUnits").textContent = statusPosition[1];

                        joggerAggSign = Math.sign(joggerAgg);
                        if (joggerAgg != 0) {
                            var joggerAggExp = Math.exp(Math.abs(joggerAgg)) * Math.sign(joggerAgg);
                            if (statusPosition[1] == "Measures.Beats") {
                                statusJogging = BtoMB(Math.floor(Math.exp(Math.abs(joggerAgg)))) * Math.sign(joggerAgg) + ".00";
                            }
                            else { statusJogging = joggerAggExp.toPrecision(4) + " s"; }
                            statusDisplay.textContent = statusJogging;
                            statusDisplay.style.fill = (joggerAggSign < 0) ? "#FE003B" : "#00FE95";
                        }
                        else {
                            statusDisplay.textContent = statusPosition[0];
                            statusDisplay.style.fill = "#a8a8a8";
                        }
                        if (tok[2] != playPosSeconds) { playPosSeconds = tok[2]; }
                        // Refresco en vivo del BPM equivalente de Playrate: en proyectos
                        // con mapa de tempo variable, el bpm original vigente cambia según
                        // la sección que está sonando -- no alcanza con refrescar solo
                        // cuando llega el poll lento de EXTSTATE/playrate (ver playrate.js).
                        nikPlayrateRefreshMainReadout(nikPlayrateEnsureFader().getValue());
                    }
                    last_time_str = tok[4];
                }
                break;
            case "EXTSTATE":
                if (tok[1] == "NikRemote" && tok[2] == "active_project_name") {
                    if (tok[3] != nikCurrentProjectName) {
                        if (nikCurrentProjectName != null) nikTabMemorySave(nikCurrentProjectName);
                        nikTabMemoryResetRenderCaches();
                        nikTabMemoryRestore(tok[3]);
                        nikCurrentProjectName = tok[3];
                        nikPlayrateRequestTempoMap(); // el mapa de tempo puede diferir por proyecto
                    }
                    nikLastProjectNameUpdate = Date.now();
                    var nameDisplay = document.getElementById("nikActiveProjectName");
                    if (nameDisplay) nameDisplay.textContent = tok[3].replace(/\.rpp$/i, "");
                }
                if (tok[1] == "NikRemote" && tok[2] == "reapitch_semitone") {
                    nikReaPitchUpdateSemitoneDisplay(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "reapitch_enabled") {
                    nikReaPitchUpdateEnabledDisplay(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "playrate") {
                    nikPlayrateUpdateDisplay(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "tempo_map") {
                    nikPlayrateSetTempoMap(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "marker_bars") {
                    nikMarkerBarsMap = nikParseMarkerBars(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "project_tabs") {
                    nikRenderProjectTabsList(tok[3]);
                }
                if (tok[1] == "NikRemote" && tok[2] == "preservepitch") {
                    nikPreservePitchServerState = tok[3];
                    var cb = document.getElementById("nikPreservePitchCheckbox");
                    if (cb && document.activeElement != cb) cb.checked = (tok[3] == "on");
                }
                break;
            case "CMDSTATE":
                var buttonMetro = document.getElementById("buttonMetro");
                if (tok[1] == 40364 && buttonMetro) {
                    if (last_metronome == 1) {
                        buttonMetro.childNodes[3].setAttributeNS(null, "visibility", "visible");
                        buttonMetro.childNodes[7].setAttributeNS(null, "visibility", "hidden");
                    }
                    else {
                        buttonMetro.childNodes[3].setAttributeNS(null, "visibility", "hidden");
                        buttonMetro.childNodes[7].setAttributeNS(null, "visibility", "visible");
                    }
                    last_metronome = tok[2];
                }
                var buttonSoloInFront = document.getElementById("buttonSoloInFront");
                if (tok[1] == 40745 && buttonSoloInFront) {
                    var soloOn = (tok[2] == 1);
                    buttonSoloInFront.classList.toggle("nikToggledOn", soloOn);
                    var soloColor = soloOn ? "#FFC107" : "#808080";
                    document.getElementById("iconSoloInFrontSource").setAttributeNS(null, "fill", soloColor);
                    document.getElementById("iconSoloInFrontBeam").setAttributeNS(null, "fill", soloColor);
                    document.getElementById("iconSoloInFrontSpot").setAttributeNS(null, "fill", soloColor);
                    last_soloinfront = tok[2];
                }
                break;
            case "BEATPOS":
                var playLine = document.querySelector('#playLine');
                if (tok.length > 5 && playLine) {
                    var playLineCirc = 301.1;
                    var playLineArc = playLineCirc - (playLineCirc / tok[6]);
                    //var playLineRotate = (360 / tok[6]) * tok[5]; //freewheeling play line
                    thisBeat = Math.round(tok[5]);
                    var playLineRotate = (360 / tok[6]) * thisBeat;
                    thisSig = tok[6];
                    if (drawnSig != thisSig || drawnBeat != thisBeat && playLine) {
                        playLine.setAttributeNS(null, "stroke-dasharray", playLineCirc);
                        playLine.setAttributeNS(null, "stroke-dashoffset", playLineArc);
                        playLine.setAttribute("transform", "rotate(" + playLineRotate + ",151.8,52.4)");
                    }
                    ts_numerator = tok[6];
                    ts_denominator = tok[7];
                    document.getElementById("tsNum").textContent = ts_numerator;
                    document.getElementById("tsDen").textContent = ts_denominator;
                }
                break;

            case "REGION_LIST":
                g_regions = [];
                break;
            case "REGION":
                g_regions.push(tok);
                break;
            case "MARKER_LIST":
                g_markers = [];
                break;
            case "MARKER":
                g_markers.push(tok);
                break;
            case "MARKER_LIST_END":
                break;

            case "REGION_LIST_END":
                var pos = parseFloat(playPosSeconds).toFixed(6);

                //assemble mrMap array : time, marker number, region start number, region end number.
                for (var i = 0; i < g_regions.length; i++) {
                    if (g_regions[i][5] == 0) { g_regions[i][5] = 25198720; } // Give uncoloured regions a colour.
                }
                for (var i = 0; i < g_markers.length; i++) {
                    if (g_markers[i][4] == 0) { g_markers[i][4] = 25198720; } // Give uncoloured markers a colour.
                }
                var mrMapAr = [];
                for (var i = 0; i < g_regions.length * 2; i++) {
                    mrMapAr[i] = [];
                    if (i < g_regions.length) {                             //add the region starts to the ar
                        mrMapAr[i][0] = g_regions[i][3];
                        mrMapAr[i][2] = g_regions[i][2];
                    }
                    else {                                               //add the region ends to the ar
                        mrMapAr[i][0] = g_regions[i - g_regions.length][4];
                        mrMapAr[i][3] = g_regions[i - g_regions.length][2];
                    }
                }
                for (var i = 0; i < g_markers.length; i++) {                //add the markers to the ar
                    mrMapAr[i + (g_regions.length * 2)] = [];
                    mrMapAr[i + (g_regions.length * 2)][0] = g_markers[i][3];
                    mrMapAr[i + (g_regions.length * 2)][1] = g_markers[i][2];
                }

                for (var i = 0; i < mrMapAr.length; i++) {                  //prep times for sorting
                    posToSix = parseFloat(mrMapAr[i][0]).toFixed(6);
                    mrMapAr[i][0] = parseFloat(posToSix);
                }

                mrMapAr.sort(function (a, b) {                           //sort into time order
                    return (a[0] === b[0] ? 0 : (a[0] < b[0] ? -1 : 1));
                });

                function mergeAt(idx) {
                    if (mrMapAr[i - 1][idx]) { a = mrMapAr[i - 1][idx] } else { a = 0 };
                    if (mrMapAr[i][idx]) { b = mrMapAr[i][idx] } else { b = 0 };
                    mrMapAr[i - 1][idx] = parseFloat(a) + parseFloat(b);
                }

                for (var i = 1; i < mrMapAr.length; i++) {                  //merge cells if at same time, delete the duplicate
                    if (mrMapAr[i - 1] && mrMapAr[i][0] === mrMapAr[i - 1][0]) {
                        mergeAt(2); mergeAt(3);
                        mrMapAr.splice(i, 1);
                    }
                }

                var prevl = -1, thisl = -1, nextl = -1;
                for (var i = 0; i < mrMapAr.length; i++) {
                    var diff = (mrMapAr[i][0] - pos);
                    if (diff < 0) {
                        if (i > prevl) { prevl = i }
                    }
                    if (diff == 0) { thisl = i };
                    if (diff > 0) {
                        if (i > nextl) { nextl = i; break; }
                    }
                }

                function getValuesFromId(array, id, colourIdx) {
                    for (var i = 0, len = array.length; i < len; i++) {
                        if (array[i][2] == id) { return [id, (array[i][1]), (array[i][colourIdx])] }
                    }
                    return [0, 0, 0];
                }

                var nextPrevSvg = document.getElementById("nextPrev")
                if ((pos != newPos || mrMapAr.length != newMrMapLength) && nextPrevSvg) {
                    function getValFromAr(array, id, idLoc, valLoc) {
                        for (var i = 0, len = array.length; i < len; i++) {
                            if (array[i][idLoc] == id) { return array[i][valLoc]; }
                        }
                        return;
                    }

                    var markerChainMap = {};
                    var nikFullChainState = { color: null, step: 0 };
                    for (var mi = 0; mi < mrMapAr.length; mi++) {
                        if (mrMapAr[mi][1] >= 1) {
                            var mChainId = mrMapAr[mi][1];
                            var mChainName = getValFromAr(g_markers, mChainId, 2, 1);
                            if (mChainName) markerChainMap[mChainId] = nikResolveMarkerDisplay(mChainName, nikFullChainState);
                        }
                    }

                    if (mrMapAr[prevl] && mrMapAr[prevl][1] >= 1) {
                        var mPrevIdx = mrMapAr[prevl][1];
                        var mPrevName = getValFromAr(g_markers, mPrevIdx, 2, 1);
                        var mPrevCol = getValFromAr(g_markers, mPrevIdx, 2, 4);
                        mPrevCol = "#" + (mPrevCol | 0x1000000).toString(16).substr(-6);
                        var mPrevDisplay = mPrevName;
                        if (mPrevName) {
                            var mPrevResolved = markerChainMap[mPrevIdx];
                            if (mPrevResolved.resolvedColor) { mPrevCol = mPrevResolved.resolvedColor; mPrevDisplay = mPrevResolved.displayName; }
                        }
                        document.getElementById("marker1").setAttributeNS(null, "visibility", "visible");
                        document.getElementById("marker1Bg").setAttributeNS(null, "fill", mPrevCol);
                        document.getElementById("marker1Number").textContent = mPrevIdx;
                        document.getElementById("marker1Number").setAttributeNS(null, "fill", lumaOffset(mPrevCol));
                        document.getElementById("prevMarkerName").textContent = (!mPrevDisplay) ? ("unnamed") : (mPrevDisplay);
                        document.getElementById("prevMarkerName").setAttributeNS(null, "fill", mPrevResolved && mPrevResolved.resolvedColor ? mPrevResolved.resolvedColor : "#A8A8A8");
                    }
                    else { document.getElementById("marker1").setAttributeNS(null, "visibility", "hidden"); }

                    if (mrMapAr[thisl] && mrMapAr[thisl][1] >= 1) {
                        var mThisIdx = mrMapAr[thisl][1];
                        var mThisName = getValFromAr(g_markers, mThisIdx, 2, 1);
                        var mThisCol = getValFromAr(g_markers, mThisIdx, 2, 4);
                        mThisCol = "#" + (mThisCol | 0x1000000).toString(16).substr(-6);
                        var mThisDisplay = mThisName;
                        if (mThisName) {
                            var mThisResolved = markerChainMap[mThisIdx];
                            if (mThisResolved.resolvedColor) { mThisCol = mThisResolved.resolvedColor; mThisDisplay = mThisResolved.displayName; }
                        }
                        document.getElementById("marker2").setAttributeNS(null, "visibility", "visible");
                        document.getElementById("marker2Bg").setAttributeNS(null, "fill", mThisCol);
                        document.getElementById("marker2Number").textContent = mThisIdx;
                        document.getElementById("marker2Number").setAttributeNS(null, "fill", lumaOffset(mThisCol));
                        document.getElementById("atMarkerName").textContent = (!mThisDisplay) ? ("unnamed") : (mThisDisplay);
                        document.getElementById("atMarkerName").setAttributeNS(null, "fill", mThisResolved && mThisResolved.resolvedColor ? mThisResolved.resolvedColor : "#A8A8A8");
                    }
                    else { document.getElementById("marker2").setAttributeNS(null, "visibility", "hidden"); }

                    if (mrMapAr[nextl] && mrMapAr[nextl][1] >= 1) {
                        var mNextIdx = mrMapAr[nextl][1];
                        var mNextName = getValFromAr(g_markers, mNextIdx, 2, 1);
                        var mNextCol = getValFromAr(g_markers, mNextIdx, 2, 4);
                        mNextCol = "#" + (mNextCol | 0x1000000).toString(16).substr(-6);
                        var mNextDisplay = mNextName;
                        if (mNextName) {
                            var mNextResolved = markerChainMap[mNextIdx];
                            if (mNextResolved.resolvedColor) { mNextCol = mNextResolved.resolvedColor; mNextDisplay = mNextResolved.displayName; }
                        }
                        document.getElementById("marker3").setAttributeNS(null, "visibility", "visible");
                        document.getElementById("marker3Bg").setAttributeNS(null, "fill", mNextCol);
                        document.getElementById("marker3Number").textContent = mNextIdx;
                        document.getElementById("marker3Number").setAttributeNS(null, "fill", lumaOffset(mNextCol));
                        document.getElementById("nextMarkerName").textContent = (!mNextDisplay) ? ("unnamed") : (mNextDisplay);
                        document.getElementById("nextMarkerName").setAttributeNS(null, "fill", mNextResolved && mNextResolved.resolvedColor ? mNextResolved.resolvedColor : "#A8A8A8");
                    }
                    else { document.getElementById("marker3").setAttributeNS(null, "visibility", "hidden"); }

                    if (prevl >= 0) { homeIconVis = "hidden"; prevIconVis = "visible"; }
                    else {
                        homeIconVis = "visible"; prevIconVis = "hidden";
                        if (pos > 0) {
                            document.getElementById("marker1").setAttributeNS(null, "visibility", "visible");
                            document.getElementById("prevMarkerName").textContent = "HOME";
                            document.getElementById("prevMarkerName").setAttributeNS(null, "fill", "#A8A8A8");
                            document.getElementById("marker1Number").textContent = "H";
                            document.getElementById("marker1Bg").setAttributeNS(null, "fill", "#1a1a1a");
                            document.getElementById("marker1Number").setAttributeNS(null, "fill", "#A8A8A8");
                        }
                        else {
                            document.getElementById("marker2").setAttributeNS(null, "visibility", "visible");
                            document.getElementById("atMarkerName").textContent = "HOME";
                            document.getElementById("atMarkerName").setAttributeNS(null, "fill", "#A8A8A8");
                            document.getElementById("marker2Number").textContent = "H";
                            document.getElementById("marker2Bg").setAttributeNS(null, "fill", "#1a1a1a");
                            document.getElementById("marker2Number").setAttributeNS(null, "fill", "#A8A8A8");
                        }
                    }
                    if (thisl < 0 && pos != 0) { elAttribute("dropMarker", "visibility", "visible") }
                    else { elAttribute("dropMarker", "visibility", "hidden") }
                    if (nextl >= 0) {
                        endIconVis = "hidden"; nextIconVis = "visible";
                    }
                    else {
                        document.getElementById("marker3").setAttributeNS(null, "visibility", "visible");
                        document.getElementById("nextMarkerName").textContent = "END";
                        document.getElementById("nextMarkerName").setAttributeNS(null, "fill", "#A8A8A8");
                        document.getElementById("marker3Number").textContent = "E";
                        document.getElementById("marker3Bg").setAttributeNS(null, "fill", "#1a1a1a");
                        document.getElementById("marker3Number").setAttributeNS(null, "fill", "#A8A8A8");
                        endIconVis = "visible"; nextIconVis = "hidden";
                    }
                    elAttribute("iconPrev", "visibility", prevIconVis);
                    elAttribute("iconHome", "visibility", homeIconVis);
                    elAttribute("iconNext", "visibility", nextIconVis);
                    elAttribute("iconEnd", "visibility", endIconVis);

                    nikMarkerBrowserHighlightCurrent();

                    newPos = pos;
                    newMrMapLength = mrMapAr.length;
                }
                break;

            case "NTRACK":
                if (tok.length > 1) { nTrack = tok[1]; }
                break;

            case "TRACK":
                idx = parseInt(tok[1]);
                if (tok.length > 5) {
                    var backLoaded = document.getElementById("backLoad");
                    var allTracksDiv = document.getElementById("tracks");
                    var trackFound = document.getElementById("track" + tok[1]);

                    if (!trackFound) {
                        var trackDiv = document.createElement("div");
                        trackDiv.id = ("track" + tok[1]);
                        trackDiv.className = ("trackDiv");

                        trackHeightsAr[tok[1]] = 0;

                        var trackRow1Div = document.createElement("div");
                        trackRow1Div.className = ("trackRow1");
                        var trackRow2Div = document.createElement("div");
                        trackRow2Div.className = ("trackRow2");
                        trackRow2Div.id = tok[1];
                        var trackSendsDiv = document.createElement("div");
                        trackSendsDiv.id = ("sendsTrack" + idx);

                        if (trackDiv && allTracksDiv) { allTracksDiv.appendChild(trackDiv); }
                        trackDiv.appendChild(trackRow1Div);
                        trackDiv.appendChild(trackRow2Div);
                        trackDiv.appendChild(trackSendsDiv);
                    }

                    else {
                        if (backLoaded != null && backLoaded.nextSibling != null) {
                            var cloneTrackRow1 = document.getElementById("trackRow1Svg").cloneNode(true);
                            cloneTrackRow1.removeAttribute("id");
                            var cloneTrackRow2 = document.getElementById("trackRow2Svg").cloneNode(true);
                            cloneTrackRow2.removeAttribute("id");
                            var cloneTrackSend = document.getElementById("trackSendSvg").cloneNode(true);
                            cloneTrackSend.removeAttribute("id");

                            if (idx == 0) { //master track stuff

                                masterMuteOffButton = document.getElementById("master-mute-off");
                                masterMuteOnButton = document.getElementById("master-mute-on");
                                if (tok[3] & 8) { masterMuteOffButton.style.visibility = "hidden"; masterMuteOnButton.style.visibility = "visible"; }
                                else { masterMuteOffButton.style.visibility = "visible"; masterMuteOnButton.style.visibility = "hidden"; }
                                masterMuteOffButton.onmousedown = mouseDownEventHandler("SET/TRACK/" + 0 + "/MUTE/-1;TRACK/" + 0);
                                masterMuteOnButton.onmousedown = mouseDownEventHandler("SET/TRACK/" + 0 + "/MUTE/-1;TRACK/" + 0);
                                masterClipIndicator = document.getElementById("master-clip_on");
                                if (tok[6] > 0) { masterClipIndicator.style.visibility = "visible"; }
                                else { masterClipIndicator.style.visibility = "hidden"; }
                                masterMeterReadout = document.getElementById("masterDb");
                                masterMeterReadout.textContent = (mkvolstr(tok[4]));

                                var masterTrackContent = document.getElementById("track0");
                                var masterTrackRow2Content = masterTrackContent.childNodes[3];
                                masterTrackRow2Content.id = "0";
                                if (!masterTrackRow2Content.innerHTML) {
                                    masterTrackRow2Content.appendChild(cloneTrackRow2);
                                    nikUniquifyGradientIds(cloneTrackRow2, "master");
                                    var trackSendsDiv = document.createElement("div");
                                    trackSendsDiv.id = ("sendsTrack0");
                                    masterTrackContent.appendChild(trackSendsDiv);
                                    nikTabMemoryApplyPending(0);
                                }

                                var volThumb = masterTrackRow2Content.getElementsByClassName("fader")[0];
                                if (faderConAr[0] != 1) {
                                    volFaderConect(masterTrackRow2Content, volThumb);
                                    faderConAr[0] = 1;
                                }
                                volThumb.volSetting = (Math.pow(tok[4], 1 / 4) * 194.68);
                                var vteMove = "translate(" + volThumb.volSetting + " 0)";
                                if (mouseDown != 1) { volThumb.setAttributeNS(null, "transform", vteMove); }

                                var masterSends = tok[12];
                                if (masterSends != trackSendCntAr[0]) {
                                    trackSendCntAr[0] = masterSends;
                                }
                            }

                            if (idx > 0) { //normal track stuff

                                var trackRow1Content = document.getElementById("track" + idx).childNodes[0];
                                if (!trackRow1Content.innerHTML) {
                                    trackRow1Content.appendChild(cloneTrackRow1);
                                    nikUniquifyGradientIds(cloneTrackRow1, idx);
                                    trackRow1Content.firstChild.getElementsByClassName("hitbox")[0].id = idx;
                                }

                                var trackRow2Content = document.getElementById("track" + idx).childNodes[1];
                                if (!trackRow2Content.innerHTML) {
                                    trackRow2Content.appendChild(cloneTrackRow2);
                                    nikUniquifyGradientIds(cloneTrackRow2, idx);
                                    nikTabMemoryApplyPending(idx);
                                }

                                trackBg = trackRow1Content.firstChild.getElementsByClassName("trackrow1bg")[0];
                                if (tok[13] > 0) {
                                    if (tok[13] != trackColoursAr[idx]) {
                                        var customTrackColour = ("#" + (tok[13] | 0x1000000).toString(16).substr(-6));
                                        trackBg.style.fill = customTrackColour;
                                        trackColoursAr[idx] = tok[13];
                                    }
                                }
                                else { trackBg.style.fill = "#9DA5A5"; }

                                if (tok[1] != trackNumbersAr[idx]) {
                                    trackNumber = trackRow1Content.firstChild.getElementsByClassName("trackNumber")[0];
                                    trackNumber.textContent = tok[1];
                                    trackNumbersAr[idx] = tok[1];
                                }

                                if (tok[2] != trackNamesAr[idx]) {
                                    trackText = trackRow1Content.firstChild.getElementsByClassName("trackName")[0];
                                    trackText.textContent = tok[2];
                                    trackNamesAr[idx] = tok[2];
                                }

                                trackRow1Content.firstChild.getElementsByClassName("recarm")[0].onmousedown = mouseDownEventHandler("SET/TRACK/" + idx + "/RECARM/-1;TRACK/" + idx);
                                trackRow1Content.firstChild.getElementsByClassName("mute")[0].onmousedown = mouseDownEventHandler("SET/TRACK/" + tok[1] + "/MUTE/-1;TRACK/" + tok[1]);
                                trackRow1Content.firstChild.getElementsByClassName("solo")[0].onmousedown = mouseDownEventHandler("SET/TRACK/" + idx + "/SOLO/-1;TRACK/" + idx);
                                trackRow1Content.firstChild.getElementsByClassName("monitor")[0].onmousedown = mouseDownEventHandler("SET/TRACK/" + idx + "/RECMON/-1;TRACK/" + idx);
                                if (tok[3] != trackFlagsAr[idx]) {

                                    recarmOffButton = trackRow1Content.firstChild.getElementsByClassName("recarm-off")[0];
                                    recarmOnButton = trackRow1Content.firstChild.getElementsByClassName("recarm-on")[0];
                                    if (tok[3] & 64) { recarmOffButton.style.visibility = "hidden"; recarmOnButton.style.visibility = "visible"; }
                                    else { recarmOffButton.style.visibility = "visible"; recarmOnButton.style.visibility = "hidden"; }

                                    soloOffButton = trackRow1Content.firstChild.getElementsByClassName("solo-off")[0];
                                    soloOnButton = trackRow1Content.firstChild.getElementsByClassName("solo-on")[0];
                                    if (tok[3] & 16) { soloOffButton.style.visibility = "hidden"; soloOnButton.style.visibility = "visible"; }
                                    else { soloOffButton.style.visibility = "visible"; soloOnButton.style.visibility = "hidden"; }

                                    muteOffButton = trackRow1Content.firstChild.getElementsByClassName("mute-off")[0];
                                    muteOnButton = trackRow1Content.firstChild.getElementsByClassName("mute-on")[0];
                                    if (tok[3] & 64) { muteOffButton.style.visibility = "hidden"; muteOnButton.style.visibility = "hidden"; }
                                    else {
                                        if (tok[3] & 8) { muteOffButton.style.visibility = "hidden"; muteOnButton.style.visibility = "visible"; }
                                        else { muteOffButton.style.visibility = "visible"; muteOnButton.style.visibility = "hidden"; }
                                    }

                                    monitorOffButton = trackRow1Content.firstChild.getElementsByClassName("monitor-off")[0];
                                    monitorOnButton = trackRow1Content.firstChild.getElementsByClassName("monitor-on")[0];
                                    monitorAutoButton = trackRow1Content.firstChild.getElementsByClassName("monitor-auto")[0];
                                    if (tok[3] & 64) {
                                        if (tok[3] & 128) { monitorOffButton.style.visibility = "hidden"; monitorOnButton.style.visibility = "visible"; monitorAutoButton.style.visibility = "hidden"; }
                                        else {
                                            if (tok[3] & 256) { monitorOffButton.style.visibility = "hidden"; monitorOnButton.style.visibility = "hidden"; monitorAutoButton.style.visibility = "visible"; }
                                            else { monitorOffButton.style.visibility = "visible"; monitorOnButton.style.visibility = "hidden"; monitorAutoButton.style.visibility = "hidden"; }
                                        }
                                    }
                                    else { monitorOffButton.style.visibility = "hidden"; monitorOnButton.style.visibility = "hidden"; monitorAutoButton.style.visibility = "hidden"; }

                                    if (tok[3] & 512) { //track hidden in TCP
                                        document.getElementById("track" + idx).style.display = "none";
                                    }
                                    else { document.getElementById("track" + idx).style.display = "block"; }

                                    folderIcon = trackRow1Content.firstChild.getElementsByClassName("folder_icon")[0];
                                    if (tok[3] & 1) { folderIcon.style.visibility = "visible"; }
                                    else { folderIcon.style.visibility = "hidden"; }
                                    trackFlagsAr[idx] = tok[3];
                                }

                                if (tok[10] != trackSendCntAr[idx]) {
                                    sendIndicator = trackRow1Content.firstChild.getElementsByClassName("s_on")[0];
                                    if (tok[10] > 0) { sendIndicator.style.visibility = "visible"; }
                                    else { sendIndicator.style.visibility = "hidden"; }
                                    trackSendCntAr[idx] = tok[10];
                                }

                                if (tok[11] != trackRcvCntAr[idx]) {
                                    rcvIndicator = trackRow1Content.firstChild.getElementsByClassName("r_on")[0];
                                    if (tok[11] > 0) { rcvIndicator.style.visibility = "visible"; }
                                    else { rcvIndicator.style.visibility = "hidden"; }
                                    trackRcvCntAr[idx] = tok[11];
                                }

                                if (tok[12] != trackHwOutCntAr[idx]) {
                                    sendIndicator = trackRow1Content.firstChild.getElementsByClassName("s_on")[0];
                                    if (tok[12] > 0) { sendIndicator.style.visibility = "visible"; }
                                    trackHwOutCntAr[idx] = tok[12];
                                }

                                if (tok[6] != trackPeakAr[idx]) {
                                    clipIndicator = trackRow1Content.firstChild.getElementsByClassName("clip_on")[0];
                                    if (tok[6] > 0) { clipIndicator.style.visibility = "visible"; }
                                    else { clipIndicator.style.visibility = "hidden"; }
                                    trackPeakAr[idx] = tok[6];
                                }

                                meterReadout = trackRow1Content.firstChild.getElementsByClassName("meterReadout")[0];
                                meterReadout.textContent = (mkvolstr(tok[4]));

                                if (tok[3] & 64) { recarmCountAr[idx] = 1 } else { recarmCountAr[idx] = 0 }
                                function getSum(total, num) { return total + num; }
                                var armedCount = document.getElementById("armed_count");
                                var armedText = document.getElementById("armed_text");
                                recarmCount = recarmCountAr.reduce(getSum);
                                armedCount.textContent = recarmCount;
                                armedCount.setAttributeNS(null, "fill", ((recarmCount == 0) ? "#5D3729" : "#545454"));
                                armedText.setAttributeNS(null, "fill", ((recarmCount == 0) ? "#5D3729" : "#545454"));

                                var volThumb = trackRow2Content.firstChild.getElementsByClassName("fader")[0];
                                if (faderConAr[idx] != 1) {
                                    volFaderConect(trackRow2Content, volThumb);
                                    faderConAr[idx] = 1;
                                }
                                volThumb.volSetting = (Math.pow(tok[4], 1 / 4) * 194.68);
                                var vteMove = "translate(" + volThumb.volSetting + " 0)";
                                if (mouseDown != 1) { volThumb.setAttributeNS(null, "transform", vteMove); }
                            }
                            var trackSendsContent = document.getElementById("sendsTrack" + idx);
                            trackSendHwCntAr[idx] = (parseInt(trackSendCntAr[idx]) || 0) + (parseInt(trackHwOutCntAr[idx]) || 0);
                            if (trackSendsContent != null && trackSendHwCntAr[idx] != null) {
                                if (trackSendsContent.childNodes.length < trackSendHwCntAr[idx]) {
                                    var sendDiv = document.createElement("div");
                                    sendDiv.className = ("sendDiv");
                                    var sendIdx = trackSendsContent.childNodes.length;
                                    trackSendsContent.appendChild(sendDiv);
                                    sendDiv.appendChild(cloneTrackSend);
                                    nikUniquifyGradientIds(cloneTrackSend, idx + "_" + sendIdx);
                                    var thisSendThumb = sendDiv.getElementsByClassName("sendThumb")[0];
                                    sendConect(sendDiv, thisSendThumb);
                                    //bug - adding a send doesn't update the height of that send. So it'll be zero even if the panel is expanded.
                                }
                                if (trackSendsContent.childNodes.length > trackSendHwCntAr[idx]) {
                                    trackSendsContent.removeChild(trackSendsContent.firstChild);
                                }
                            }
                        }
                    }

                    var tracksDiv = document.getElementById('tracks');
                    if (tracksDiv != null) {
                        var tracksDrawn = tracksDiv.childNodes.length;
                    }
                    if (tracksDrawn > nTrack) {
                        var lastTrackDiv = tracksDiv.lastChild;
                        var lastTrackId = lastTrackDiv ? lastTrackDiv.id.replace("track", "") : null;
                        tracksDiv.removeChild(lastTrackDiv);
                        if (lastTrackId != null) {
                            trackNamesAr[lastTrackId] = undefined;
                            trackNumbersAr[lastTrackId] = undefined;
                            trackColoursAr[lastTrackId] = undefined;
                            trackFlagsAr[lastTrackId] = undefined;
                            trackHeightsAr[lastTrackId] = undefined;
                            faderConAr[lastTrackId] = undefined;
                        }
                    }
                }
                break;

            case "SEND":
                function sendConect(content, thumb) {
                    content.addEventListener("mousemove", sendMouseMoveHandler, false);
                    content.addEventListener("touchmove", sendMouseMoveHandler, false);
                    content.addEventListener("mouseleave", mouseLeaveHandler, false);
                    content.addEventListener("mouseup", sendMouseUpHandler, false);
                    content.addEventListener("touchend", sendMouseUpHandler, false);
                    thumb.addEventListener("mousedown", function (event) { mouseDownHandler(event, event.srcElement) }, false);
                    thumb.addEventListener('touchstart', function (event) {
                        if (event.touches.length > 0) mouseDownHandler(event, event.srcElement);
                        event.preventDefault();
                    }, false);
                }

                if (tok.length > 3) {
                    var targetName;
                    if (tok[6] > 0) targetName = trackNamesAr[tok[6]];
                    else targetName = "Hardware";
                    var sendMuted = ", not muted";
                    if (tok[3] & 8) sendMuted = ", MUTED";

                    var trackSendsContent = document.getElementById("sendsTrack" + tok[1]);
                    if (trackSendsContent.childNodes.length > 0) {
                        var thisSendDiv = trackSendsContent.childNodes[tok[2]];
                        if (thisSendDiv != null) {
                            thisSendDiv.id = [tok[2]];
                            sendTitleText = thisSendDiv.firstChild.getElementsByClassName("sendTitleText")[0];
                            if (sendTitleText.textContent != targetName) sendTitleText.textContent = targetName;
                            sDbText = thisSendDiv.firstChild.getElementsByClassName("sDbText")[0];
                            sDbValue = mkvolstr(tok[4])
                            if (sDbText.Content != sDbValue) sDbText.textContent = sDbValue;

                            var sendLine = thisSendDiv.firstChild.getElementsByClassName("sendLine")[0];
                            sLineSetting = (Math.pow(tok[4], 1 / 4) * 154) + 27;
                            if (mouseDown != 1) { sendLine.setAttributeNS(null, "x2", sLineSetting); }

                            var sendThumb = thisSendDiv.firstChild.getElementsByClassName("sendThumb")[0];
                            if (tok[6] > 0) {
                                var sendTargetBg = document.getElementsByClassName("trackrow1bg")[(tok[6] - 1)]
                                if (sendTargetBg != undefined) { var sendTargetBgColour = (sendTargetBg.getAttribute("style")) }
                                var sendThumbColour = sendThumb.getAttribute("style")
                                var defaultColour = "fill: rgb(157, 165, 165);";
                                if (sendTargetBgColour != defaultColour) {
                                    if (sendThumbColour != sendTargetBgColour) {
                                        sendThumb.setAttributeNS(null, "style", sendTargetBgColour);
                                        sendTitleText.setAttributeNS(null, "style", sendTargetBgColour);
                                        sendThumb.setAttributeNS(null, "opacity", "0.5");
                                    }
                                }
                                else {
                                    sendThumb.setAttributeNS(null, "style", "none");
                                    sendTitleText.setAttributeNS(null, "style", "none");
                                    sendThumb.setAttributeNS(null, "opacity", "0.5");
                                }
                            }

                            sThumbSetting = (Math.pow(tok[4], 1 / 4) * 154) + 27;
                            if (mouseDown != 1) { sendThumb.setAttributeNS(null, "cx", sThumbSetting); }

                            var sendMuteButton = thisSendDiv.firstChild.getElementsByClassName("send_mute")[0];
                            sendMuteButton.onmousedown = mouseDownEventHandler("SET/TRACK/" + tok[1] + "/SEND/" + tok[2] + "/MUTE/-1");
                            var sendMuteOff = thisSendDiv.firstChild.getElementsByClassName("send_mute_off")[0];
                            var sendMuteOn = thisSendDiv.firstChild.getElementsByClassName("send_mute_on")[0];
                            if (tok[3] & 8) {
                                sendMuteOff.style.visibility = "hidden";
                                sendMuteOn.style.visibility = "visible";
                            }
                            else {
                                sendMuteOff.style.visibility = "visible";
                                sendMuteOn.style.visibility = "hidden";
                            }
                        }
                    }
                }
        }
    }
    if (trackSendHwCntAr.length > 0) {
        for (x = 0; x < trackSendHwCntAr.length; x++) {
            if (trackSendHwCntAr[x] > 0) {
                for (y = 0; y < trackSendHwCntAr[x]; y++) {
                    wwr_req("GET/TRACK/" + x + "/SEND/" + y);
                }
            }
        }
    }
}