// modals/marker-browser/marker-browser.js — lógica del popup de lista de markers.
// Markup en marker-browser.html (inyectado por modal-loader.js al boot).
// Depende de: g_markers (global de markers del proyecto, index.html),
// nikMarkerBarsMap (parseado en wwr_onreply, index.html),
// nikResolveMarkerDisplay / nikFormatMinSec (helpers COMPARTIDOS — también
// los usa el indicador de markers de la UI principal, index.html — quedan
// ahí, no son exclusivos de este modal, candidatos a markers/markers.js en
// una futura pasada de modularización).
//
// nikMarkerAreaClick es el trigger de apertura: está acá (no en index.html)
// porque ya llama directo a nikOpenMarkerBrowser() — mismo criterio que el
// resto de los modales, donde el "abrir" vive junto al resto de la lógica
// del popup aunque el elemento que dispara el click esté en la UI principal.
//
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que el onclick="nikMarkerAreaClick(event)" del
// área de markers en index.html las encuentre igual que antes.

function nikMarkerAreaClick(event) {
    var t = event.target;
    while (t && t.id != "prevButton" && t.id != "nextButton" && t.id != "dropMarker" && t.tagName != "svg") {
        t = t.parentNode;
        }
    if (t && (t.id == "prevButton" || t.id == "nextButton" || t.id == "dropMarker")) return;
    nikOpenMarkerBrowser();
    }

function nikOpenMarkerBrowser() {
    var list = document.getElementById("nikMarkerBrowserList");
    if (!list) return;
    list.innerHTML = "";
    var sorted = g_markers.slice().sort(function(a,b){ return parseFloat(a[3]) - parseFloat(b[3]); });
    var nikPopupChainState = { color: null, step: 0 };
    for (var i=0; i<sorted.length; i++) {
        var m = sorted[i];
        var rawName = m[1] ? m[1] : ("unnamed (" + m[2] + ")");
        var resolved = nikResolveMarkerDisplay(m[1] ? m[1] : "", nikPopupChainState);
        var displayName = m[1] ? resolved.displayName : rawName;
        var resolvedColor = resolved.resolvedColor;

        var item = document.createElement("div");
        item.style.cssText = "display:flex; justify-content:space-between; align-items:center; padding:10px 8px; color:#A8A8A8; font-family:'Open Sans',sans-serif; font-size:1.3em; border-bottom:1px solid #262626;";
        var nameSpan = document.createElement("span");
        nameSpan.textContent = displayName;
        if (resolvedColor) nameSpan.style.color = resolvedColor;
        var posSpan = document.createElement("span");
        posSpan.style.cssText = "display:flex; color:#999999; font-size:0.95em; margin-left:8px; flex-shrink:0; font-variant-numeric:tabular-nums;";
        var timeSpan = document.createElement("span");
        timeSpan.style.cssText = "min-width:2.8em; text-align:right;";
        timeSpan.textContent = nikFormatMinSec(parseFloat(m[3]));
        var barsValSpan = document.createElement("span");
        barsValSpan.style.cssText = "min-width:3.2em; text-align:right;";
        var barsVal = nikMarkerBarsMap[m[2]];
        barsValSpan.textContent = barsVal ? (barsVal + "c") : "";
        posSpan.appendChild(timeSpan);
        posSpan.appendChild(barsValSpan);
        item.appendChild(nameSpan);
        item.appendChild(posSpan);
        item.setAttribute("data-markerid", m[2]);
        item.onclick = function(){
            wwr_req("SET/POS_STR/m" + this.getAttribute("data-markerid"));
            nikCloseMarkerBrowser();
            };
        list.appendChild(item);
        }
    document.getElementById("nikMarkerBrowserOverlay").style.display = "flex";
    }

function nikCloseMarkerBrowser() {
    document.getElementById("nikMarkerBrowserOverlay").style.display = "none";
    }
