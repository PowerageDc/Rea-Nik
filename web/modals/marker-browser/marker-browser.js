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

var nikPreMarkerBars = 2;
var NIK_PRE_MARKER_LONGPRESS_MS = 450;
var NIK_PRE_MARKER_MOVE_TOLERANCE = 10;
var nikMarkerBrowserSorted = [];
var nikMarkerBrowserCurrentId = null;

function nikUpdatePreMarkerBarsDisplay() {
    var pill = document.getElementById("nikPreMarkerBarsPill");
    var number = document.getElementById("nikPreMarkerBarsNumber");
    var caption = document.getElementById("nikPreMarkerBarsCaption");
    if (pill) pill.textContent = nikPreMarkerBars + "c";
    if (number) number.textContent = nikPreMarkerBars;
    if (caption) caption.textContent = (nikPreMarkerBars == 1 ? "compás antes" : "compases antes");
}

function nikTogglePreMarkerStepper() {
    var row = document.getElementById("nikPreMarkerStepperRow");
    if (!row) return;
    row.style.display = (row.style.display == "flex") ? "none" : "flex";
    requestAnimationFrame(nikUpdateMarkerScrollFade);
}

var nikMarkerFadeListenerAttached = false;

function nikUpdateMarkerScrollFade() {
    var scroller = document.getElementById("nikMarkerBrowserScroll");
    var fade = document.getElementById("nikMarkerScrollFade");
    if (!scroller || !fade) return;
    var canScrollMore = (scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight) > 4;
    fade.style.opacity = canScrollMore ? "1" : "0";
}

function nikPreMarkerBarsStep(delta) {
    nikPreMarkerBars = Math.max(1, Math.min(8, nikPreMarkerBars + delta));
    nikUpdatePreMarkerBarsDisplay();
}

function nikFirePreMarkerSeek(markerId) {
    wwr_req("SET/EXTSTATE/NikRemote/preseek_marker_id/" + markerId +
        ";SET/EXTSTATE/NikRemote/preseek_bars/" + nikPreMarkerBars +
        ";" + NIK_LUA_COMMANDS.preMarkerSeek.commandId);
    nikCloseMarkerBrowser();
}

function nikAttachMarkerLongPress(item, markerId, bar) {
    var timer = null;
    var startX = 0, startY = 0;
    var fired = false;

    function start(x, y) {
        fired = false;
        startX = x; startY = y;
        bar.style.transition = "none";
        bar.style.width = "0%";
        bar.offsetWidth;
        bar.style.transition = "width " + NIK_PRE_MARKER_LONGPRESS_MS + "ms linear";
        bar.style.width = "100%";
        timer = setTimeout(function () {
            fired = true;
            bar.style.transition = "none";
            bar.style.width = "0%";
            nikFirePreMarkerSeek(markerId);
        }, NIK_PRE_MARKER_LONGPRESS_MS);
    }
    function cancel() {
        clearTimeout(timer);
        bar.style.transition = "none";
        bar.style.width = "0%";
    }
    function move(x, y) {
        if (Math.abs(x - startX) > NIK_PRE_MARKER_MOVE_TOLERANCE || Math.abs(y - startY) > NIK_PRE_MARKER_MOVE_TOLERANCE) cancel();
    }

    item.addEventListener("touchstart", function (e) { start(e.touches[0].clientX, e.touches[0].clientY); }, { passive: true });
    item.addEventListener("touchmove", function (e) { move(e.touches[0].clientX, e.touches[0].clientY); }, { passive: true });
    item.addEventListener("touchend", function () { cancel(); if (fired) item._nikSuppressClick = true; }, { passive: true });
    item.addEventListener("touchcancel", cancel, { passive: true });
    item.addEventListener("mousedown", function (e) { start(e.clientX, e.clientY); });
    item.addEventListener("mousemove", function (e) { if (timer) move(e.clientX, e.clientY); });
    item.addEventListener("mouseup", function () { cancel(); if (fired) item._nikSuppressClick = true; });
    item.addEventListener("mouseleave", cancel);
}

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
    var sorted = g_markers.slice().sort(function (a, b) { return parseFloat(a[3]) - parseFloat(b[3]); });
    nikMarkerBrowserSorted = sorted;
    var nikPopupChainState = { color: null, step: 0 };
    nikUpdatePreMarkerBarsDisplay();
    for (var i=0; i<sorted.length; i++) {
        var m = sorted[i];
        var rawName = m[1] ? m[1] : ("unnamed (" + m[2] + ")");
        var resolved = nikResolveMarkerDisplay(m[1] ? m[1] : "", nikPopupChainState);
        var displayName = m[1] ? resolved.displayName : rawName;
        var resolvedColor = resolved.resolvedColor;

        var item = document.createElement("div");
        item.style.cssText = "display:flex; justify-content:space-between; align-items:center; padding:10px 8px; color:#A8A8A8; font-family:'Open Sans',sans-serif; font-size:1.3em; border-bottom:1px solid #262626; border-left:3px solid transparent; position:relative; overflow:hidden;";
        var pressBar = document.createElement("div");
        pressBar.style.cssText = "position:absolute; left:0; bottom:0; height:2px; width:0%; background:#00D0FF;";
        item.appendChild(pressBar);
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
        item.onclick = function () {
            if (this._nikSuppressClick) { this._nikSuppressClick = false; return; }
            wwr_req("SET/POS_STR/m" + this.getAttribute("data-markerid"));
            nikCloseMarkerBrowser();
        };
        nikAttachMarkerLongPress(item, m[2], pressBar);
        list.appendChild(item);
        }
    nikMarkerBrowserCurrentId = null;
    nikMarkerBrowserHighlightCurrent();
    document.getElementById("nikMarkerBrowserOverlay").style.display = "flex";
    var scroller = document.getElementById("nikMarkerBrowserScroll");
    if (scroller && !nikMarkerFadeListenerAttached) {
        scroller.addEventListener("scroll", nikUpdateMarkerScrollFade);
        nikMarkerFadeListenerAttached = true;
        }
    requestAnimationFrame(nikUpdateMarkerScrollFade);
    }

function nikMarkerBrowserFindCurrentId(pos) {
    var currentId = null;
    for (var i = 0; i < nikMarkerBrowserSorted.length; i++) {
        var mTime = parseFloat(nikMarkerBrowserSorted[i][3]);
        if (mTime <= pos + 1e-6) currentId = nikMarkerBrowserSorted[i][2];
        else break;
        }
    return currentId;
    }

function nikMarkerBrowserHighlightCurrent() {
    var overlay = document.getElementById("nikMarkerBrowserOverlay");
    if (!overlay || overlay.style.display != "flex") return;
    var currentId = nikMarkerBrowserFindCurrentId(parseFloat(playPosSeconds));
    if (currentId == nikMarkerBrowserCurrentId) return;
    nikMarkerBrowserCurrentId = currentId;
    var items = document.getElementById("nikMarkerBrowserList").children;
    for (var i = 0; i < items.length; i++) {
        var isCurrent = (items[i].getAttribute("data-markerid") == currentId);
        items[i].style.borderLeftColor = isCurrent ? "#00D0FF" : "transparent";
        items[i].style.backgroundColor = isCurrent ? "#1f2f33" : "transparent";
        }
    }

function nikCloseMarkerBrowser() {
    document.getElementById("nikMarkerBrowserOverlay").style.display = "none";
    }
