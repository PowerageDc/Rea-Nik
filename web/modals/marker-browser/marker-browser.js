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
    var fadeTop = document.getElementById("nikMarkerScrollFadeTop");
    if (!scroller || !fade) return;
    var canScrollMore = (scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight) > 4;
    fade.style.opacity = canScrollMore ? "1" : "0";
    if (fadeTop) fadeTop.style.opacity = (scroller.scrollTop > 4) ? "1" : "0";
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
        item.style.cssText = "display:flex; flex-direction:column; gap:4px; padding:14px 10px; color:#A8A8A8; font-family:'Open Sans',sans-serif; border-bottom:1px solid #3A3A3A; border-left:3px solid transparent; position:relative; overflow:hidden;";
        var pressBar = document.createElement("div");
        pressBar.style.cssText = "position:absolute; left:0; bottom:0; height:2px; width:0%; background:#00D0FF;";
        item.appendChild(pressBar);
        var nameSpan = document.createElement("span");
        nameSpan.style.cssText = "font-size:1.22em; font-weight:600; line-height:1.3;";
        nameSpan.textContent = displayName;
        if (resolvedColor) nameSpan.style.color = resolvedColor;
        var posSpan = document.createElement("span");
        posSpan.style.cssText = "display:flex; gap:14px; color:#C4C4C4; font-size:1.05em; letter-spacing:0.02em; font-variant-numeric:tabular-nums;";
        var timeSpan = document.createElement("span");
        timeSpan.style.cssText = "min-width:2.6em;";
        timeSpan.textContent = nikFormatMinSec(parseFloat(m[3]));
        var barsValSpan = document.createElement("span");
        barsValSpan.style.cssText = "display:flex; align-items:baseline; gap:4px; min-width:7em;";
        var barsVal = nikMarkerBarsMap[m[2]];
        if (barsVal) {
            var barsLabelSpan = document.createElement("span");
            barsLabelSpan.style.cssText = "color:#9A9A9A;";
            barsLabelSpan.textContent = "Compases:";
            var sepSpan = document.createElement("span");
            sepSpan.style.cssText = "color:#5A5A5A;";
            sepSpan.textContent = "|";
            var barsNumSpan = document.createElement("span");
            barsNumSpan.style.cssText = "min-width:1.4em; text-align:right; font-weight:600;";
            barsNumSpan.textContent = barsVal;
            barsValSpan.appendChild(barsLabelSpan);
            barsValSpan.appendChild(barsNumSpan);
        }
        posSpan.appendChild(timeSpan);
        if (barsVal) posSpan.appendChild(sepSpan);
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
    document.getElementById("nikMarkerBrowserOverlay").style.display = "flex";
    var savedMem = nikTabUiMemory[nikCurrentProjectName];
    document.getElementById("nikMarkerBrowserScroll").scrollTop = savedMem ? (savedMem.markerScrollTop || 0) : 0;
    nikMarkerBrowserHighlightCurrent(true);
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

function nikMarkerBrowserHighlightCurrent(skipAutoScroll) {
    var overlay = document.getElementById("nikMarkerBrowserOverlay");
    if (!overlay || overlay.style.display != "flex") return;
    var currentId = nikMarkerBrowserFindCurrentId(parseFloat(playPosSeconds));
    if (currentId == nikMarkerBrowserCurrentId) return;
    nikMarkerBrowserCurrentId = currentId;
    var items = document.getElementById("nikMarkerBrowserList").children;
    var currentItem = null;
    for (var i = 0; i < items.length; i++) {
        var isCurrent = (items[i].getAttribute("data-markerid") == currentId);
        items[i].style.borderLeftColor = isCurrent ? "#00D0FF" : "transparent";
        items[i].style.backgroundColor = isCurrent ? "#1f2f33" : "transparent";
        if (isCurrent) currentItem = items[i];
        }
    if (currentItem && !skipAutoScroll) {
        var scroller = document.getElementById("nikMarkerBrowserScroll");
        var itemTop = currentItem.offsetTop;
        var itemBottom = itemTop + currentItem.offsetHeight;
        var viewTop = scroller.scrollTop;
        var viewBottom = viewTop + scroller.clientHeight;
        if (itemTop < viewTop || itemBottom > viewBottom) {
            currentItem.scrollIntoView({ block: "center", behavior: "smooth" });
            }
        }
    }

function nikMarkerBrowserSaveScroll() {
    if (!nikCurrentProjectName) return;
    var scroller = document.getElementById("nikMarkerBrowserScroll");
    if (!scroller) return;
    if (!nikTabUiMemory[nikCurrentProjectName]) nikTabUiMemory[nikCurrentProjectName] = nikTabMemorySnapshot();
    nikTabUiMemory[nikCurrentProjectName].markerScrollTop = scroller.scrollTop;
    }

function nikCloseMarkerBrowser() {
    nikMarkerBrowserSaveScroll();
    document.getElementById("nikMarkerBrowserOverlay").style.display = "none";
    }
