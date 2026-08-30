// modals/tracksvis/tracksvis.js — lógica del popup de visibilidad de tracks (TCP).
// Markup en tracksvis.html (inyectado por modal-loader.js al boot).
// Depende de: NIK_LUA_COMMANDS (config.js), y de arrays de estado global de
// tracks (nTrack, trackFlagsAr, trackColoursAr, trackNamesAr) que viven en
// index.html — son core compartido con el resto de la UI de tracks, no
// exclusivos de este modal, así que no se mudan acá.
// nikTracksVisSnapshot sí es exclusiva de este modal (se resetea al abrir,
// se compara al aplicar) y se mudó junto con las funciones.
//
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que el onclick="nikOpenTracksVisModal()" del
// botón en la UI principal (index.html) y los onclick inline de
// tracksvis.html las encuentren igual que antes.

var nikTracksVisSnapshot = {};

function nikOpenTracksVisModal() {
    var list = document.getElementById("nikTracksVisList");
    if (!list) return;
    list.innerHTML = "";
    nikTracksVisSnapshot = {};
    for (var i = 1; i <= nTrack; i++) {
        var flags = parseInt(trackFlagsAr[i]) || 0;
        var visible = !(flags & 512);
        var hasFx = !!(flags & 4);
        nikTracksVisSnapshot[i] = visible;

        var row = document.createElement("label");
        row.style.cssText = "display:flex; align-items:center; gap:10px; padding:10px 8px; color:#A8A8A8; font-family:'Open Sans',sans-serif; font-size:1.1em; border-bottom:1px solid #262626; cursor:pointer;";

        var cb = document.createElement("input");
        cb.type = "checkbox";
        cb.checked = visible;
        cb.setAttribute("data-trackidx", i);
        cb.style.cssText = "flex-shrink:0; width:20px; height:20px;";

        var rawColor = parseInt(trackColoursAr[i]) || 0;
        var trackColor = (rawColor > 0) ? ("#" + (rawColor|0x1000000).toString(16).substr(-6)) : "#A8A8A8";

        var nameSpan = document.createElement("span");
        nameSpan.textContent = trackNamesAr[i] ? trackNamesAr[i] : ("Track " + i);
        nameSpan.style.cssText = "flex:1 1 auto; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; color:" + trackColor + ";";

        var fxSpan = document.createElement("span");
        fxSpan.textContent = hasFx ? "FX" : "";
        fxSpan.style.cssText = "color:#57FF86; font-size:0.8em; flex-shrink:0;";

        row.appendChild(cb);
        row.appendChild(nameSpan);
        row.appendChild(fxSpan);
        list.appendChild(row);
        }
    document.getElementById("nikTracksVisOverlay").style.display = "flex";
    }

function nikCloseTracksVisModal() {
    document.getElementById("nikTracksVisOverlay").style.display = "none";
    }

function nikTracksVisSetAll(state) {
    var checkboxes = document.getElementById("nikTracksVisList").getElementsByTagName("input");
    for (var i = 0; i < checkboxes.length; i++) { checkboxes[i].checked = state; }
    }

function nikApplyTracksVis() {
    var checkboxes = document.getElementById("nikTracksVisList").getElementsByTagName("input");
    var cmds = "";
    for (var i = 0; i < checkboxes.length; i++) {
        var idx = checkboxes[i].getAttribute("data-trackidx");
        var newVisible = checkboxes[i].checked;
        if (newVisible != nikTracksVisSnapshot[idx]) {
            cmds += "SET/TRACK/" + idx + "/B_SHOWINTCP/" + (newVisible ? 1 : 0) + ";";
            }
        }
    if (cmds != "") {
        cmds += "SET/UNDO/" + encodeURIComponent("Mostrar/ocultar tracks (remoto)") + ";";
        cmds += NIK_LUA_COMMANDS.trackVisRefresh.commandId + ";";
        wwr_req(cmds);
        }
    nikCloseTracksVisModal();
    }
