// ms-section-row.js — fila de sección prev / actual / next con animación
// (compartida por instrumentista y cantante)
//
// Traslado 1:1 desde instrumentista.js, sin cambios de lógica. Ver
// musicstate_instrumentista.md §7 ("Animación de la fila de sección").
//
// Contrato de DOM (los dos shells deben usar estos ids):
//   msSectionRow, msSectionPrev, msSection, msSectionNext, msSectionNextFill
// Contrato de CSS: clase .is-jumping en #msSectionRow (fade) y transiciones
// de opacity/transform/color en prev/current/next. #msSectionRow debe ser
// contenedor de posicionamiento (position distinto de static): el fantasma
// de nikMsBuildGhost se posiciona en absoluto contra él (ms-base.css lo
// garantiza con position: relative).
//
// Punto de entrada: nikMsSectionRowRender(screenJumped), una vez por render.
// screenJumped = true si OTRA capa de la misma pantalla (tira de acordes,
// reel de letra) hizo jump en este mismo tick: en ese caso un avance de uno
// se trata como salto (fade) en vez de cruce animado.
//
// Requiere, ya cargados: ms-section.js (nikMsEffectivePosSeconds,
// nikMsFindSectionIndexAt, nikMsSectionByIndex, nikMsSecUntilNextSection),
// core/music-state.js (nikMusicStateIsPlaying) y nikMsLog.

var NIK_MS_SECTION_PRELUDE_SEC = 2;
var nikMsSectionRowPrevTriple = null;
var nikMsSectionRowFillArmedIdx = null;
var nikMsSectionRowJumpPendingIdx = null;

function nikMsSectionRowId(sec) { return sec ? (sec.id + "|" + sec.displayName) : null; }

function nikMsSectionRowPaint(curIdx) {
    var byIndex = (typeof nikMsSectionByIndex === "function") ? nikMsSectionByIndex : function () { return null; };
    var prev = byIndex(curIdx - 1);
    var cur = byIndex(curIdx);
    var next = byIndex(curIdx + 1);

    var prevEl = document.getElementById("msSectionPrev");
    var curEl = document.getElementById("msSection");
    var nextFillEl = document.getElementById("msSectionNextFill");

    prevEl.textContent = prev ? prev.displayName : "";
    prevEl.style.color = "";
    curEl.textContent = cur ? cur.displayName : "\u00A0";
    curEl.style.color = cur ? (cur.resolvedColor || "") : "";
    nikMsSectionRowPrepareNext(next);
    void nextFillEl.offsetHeight;
    nextFillEl.style.transition = "";
}

// Texto + color + fill oculto (sin transición) de "next" -- NO fuerza
// reflow ni restaura la transición del fill acá: queda a cargo de quien
// llama, para poder batchearlo junto con el resto del lote (ver abajo).
function nikMsSectionRowPrepareNext(next) {
    var nextEl = document.getElementById("msSectionNext");
    var nextFillEl = document.getElementById("msSectionNextFill");
    nextEl.textContent = next ? next.displayName : "";
    nextFillEl.textContent = next ? next.displayName : "";
    nextFillEl.style.color = next ? (next.resolvedColor || "") : "";
    nextFillEl.style.transition = "none";
    nextFillEl.style.clipPath = "inset(100% 0 0 0)";
}

function nikMsSectionRowArmFill(secRemaining) {
    var nextFillEl = document.getElementById("msSectionNextFill");
    requestAnimationFrame(function () {
        nextFillEl.style.transition = "clip-path " + secRemaining + "s linear";
        nextFillEl.style.clipPath = "inset(0 0 0 0)";
    });
}

function nikMsSectionRowResetFill() {
    var nextFillEl = document.getElementById("msSectionNextFill");
    nextFillEl.style.transition = "none";
    nextFillEl.style.clipPath = "inset(100% 0 0 0)";
    void nextFillEl.offsetHeight;
    nextFillEl.style.transition = "";
}

function nikMsFlipTransform(beforeRect, afterRect) {
    if (!beforeRect.height || !afterRect.height) return "";
    var dx = (beforeRect.left + beforeRect.width / 2) - (afterRect.left + afterRect.width / 2);
    var dy = (beforeRect.top + beforeRect.height / 2) - (afterRect.top + afterRect.height / 2);
    var s = beforeRect.height / afterRect.height;
    return "translate(" + dx + "px," + dy + "px) scale(" + s + ")";
}

// Arma (sin disparar) el clon-fantasma de lo que sourceEl tenía, para que
// se desvanezca en su lugar en vez de descartarse sin más -- ver "Clonar
// elementos DOM con id" en 01_CONVENCIONES.md. No fuerza reflow ni dispara
// el fade acá: el flush y el release quedan a cargo del lote completo en
// nikMsSectionRowShift.
function nikMsBuildGhost(sourceEl, containerEl) {
    if (!sourceEl.textContent) return null;
    var r = sourceEl.getBoundingClientRect();
    var cr = containerEl.getBoundingClientRect();
    var ghost = sourceEl.cloneNode(true);
    ghost.removeAttribute("id");
    ghost.style.position = "absolute";
    ghost.style.left = (r.left - cr.left) + "px";
    ghost.style.top = (r.top - cr.top) + "px";
    ghost.style.width = r.width + "px";
    ghost.style.margin = "0";
    containerEl.appendChild(ghost);
    ghost.addEventListener("transitionend", function onDone(ev) {
        if (ev.propertyName !== "opacity") return;
        ghost.removeEventListener("transitionend", onDone);
        if (ghost.parentNode) ghost.parentNode.removeChild(ghost);
    });
    return ghost;
}

// Cruce limpio de a un índice. Todo el lote (prev/current/next + el
// fantasma de lo que se pierde) se dispone, se mide y se dispara junto --
// un solo flush compartido, un solo release compartido. Si se hace por
// nodo (como la versión anterior), cada flush individual termina
// comprometiendo el estado pendiente de los OTROS nodos todavía sin
// suprimir -- causa real del bug donde ni la escala ni el color se veían
// animar bien.
function nikMsSectionRowShift(newCurIdx) {
    var rowEl = document.getElementById("msSectionRow");
    var prevEl = document.getElementById("msSectionPrev");
    var curEl = document.getElementById("msSection");
    var nextEl = document.getElementById("msSectionNext");
    var nextFillEl = document.getElementById("msSectionNextFill");

    // FIRST
    var rCurBefore = curEl.getBoundingClientRect();
    var rNextBefore = nextEl.getBoundingClientRect();
    var ghost = nikMsBuildGhost(prevEl, rowEl);

    // Suprimir ANTES de mutar/medir nada más -- cualquier forced reflow
    // posterior (necesario para medir con el texto ya nuevo) flushea todo
    // el documento, no solo el nodo leído.
    prevEl.style.transitionProperty = "none";
    curEl.style.transitionProperty = "none";
    nextEl.style.transitionProperty = "none";

    // MUTATE
    var byIndex = (typeof nikMsSectionByIndex === "function") ? nikMsSectionByIndex : function () { return null; };
    var newCur = byIndex(newCurIdx);
    var newNext = byIndex(newCurIdx + 1);

    var newPrev = byIndex(newCurIdx - 1);
    prevEl.textContent = newPrev ? newPrev.displayName : "";
    prevEl.style.color = curEl.style.color || "var(--ms-fg)";
    prevEl.style.opacity = "1";
    curEl.textContent = newCur ? newCur.displayName : "\u00A0";
    curEl.style.color = newCur ? (newCur.resolvedColor || "") : "";
    nikMsSectionRowPrepareNext(newNext);

    // INVERT -- medir ya con el contenido nuevo, armar los 3 disfraces,
    // todo con las transiciones todavía suprimidas.
    var rCurAfter = curEl.getBoundingClientRect();
    var rPrevAfter = prevEl.getBoundingClientRect();

    prevEl.style.transform = nikMsFlipTransform(rCurBefore, rPrevAfter);
    curEl.style.transform = nikMsFlipTransform(rNextBefore, rCurAfter);
    nextEl.style.opacity = "0";
    nextEl.style.transform = "scale(0.7)";
    if (ghost) ghost.style.transitionProperty = "opacity, transform";

    // Un solo flush para todo el lote.
    void rowEl.offsetHeight;

    // PLAY -- restaurar transición completa, soltar los 3 juntos.
    prevEl.style.transitionProperty = "";
    curEl.style.transitionProperty = "";
    nextEl.style.transitionProperty = "";
    nextFillEl.style.transition = "";

    requestAnimationFrame(function () {
        prevEl.style.transform = "";
        prevEl.style.color = "";
        prevEl.style.opacity = "";
        curEl.style.transform = "";
        nextEl.style.transform = "";
        nextEl.style.opacity = "";
        if (ghost) {
            ghost.style.opacity = "0";
            ghost.style.transform = "scale(0.7)";
        }
    });
}

function nikMsSectionRowJump(curIdx) {
    var rowEl = document.getElementById("msSectionRow");
    nikMsSectionRowJumpPendingIdx = curIdx;
    if (rowEl.classList.contains("is-jumping")) return;

    rowEl.classList.add("is-jumping");
    var onFadeOut = function (ev) {
        if (ev.propertyName !== "opacity") return;
        rowEl.removeEventListener("transitionend", onFadeOut);
        nikMsSectionRowPaint(nikMsSectionRowJumpPendingIdx);
        nikMsSectionRowJumpPendingIdx = null;
        rowEl.classList.remove("is-jumping");
    };
    rowEl.addEventListener("transitionend", onFadeOut);
}

function nikMsSectionRowRender(screenJumped) {
    var pos = nikMsEffectivePosSeconds();
    var curIdx = (typeof nikMsFindSectionIndexAt === "function") ? nikMsFindSectionIndexAt(pos) : -1;
    var byIndex = (typeof nikMsSectionByIndex === "function") ? nikMsSectionByIndex : function () { return null; };

    var newTriple = {
        prevId: nikMsSectionRowId(byIndex(curIdx - 1)),
        curId: nikMsSectionRowId(byIndex(curIdx)),
        nextId: nikMsSectionRowId(byIndex(curIdx + 1))
    };
    var old = nikMsSectionRowPrevTriple;

    if (old === null) {
        nikMsSectionRowPaint(curIdx);
        nikMsSectionRowFillArmedIdx = null;
    } else if (newTriple.prevId === old.prevId && newTriple.curId === old.curId && newTriple.nextId === old.nextId) {
        var isPlaying = (typeof nikMusicStateIsPlaying === "function") && nikMusicStateIsPlaying();
        if (!isPlaying) {
            if (nikMsSectionRowFillArmedIdx !== null) {
                nikMsSectionRowResetFill();
                nikMsSectionRowFillArmedIdx = null;
            }
        } else if (nikMsSectionRowFillArmedIdx !== curIdx) {
            var secUntilNext = (typeof nikMsSecUntilNextSection === "function") ? nikMsSecUntilNextSection(pos) : null;
            if (secUntilNext !== null && secUntilNext <= NIK_MS_SECTION_PRELUDE_SEC) {
                nikMsSectionRowArmFill(secUntilNext);
                nikMsSectionRowFillArmedIdx = curIdx;
            }
        }
        nikMsSectionRowPrevTriple = newTriple;
        return;
    } else if (newTriple.curId !== null && newTriple.prevId === old.curId && newTriple.curId === old.nextId && !screenJumped) {
        nikMsLog("SECTION_SHIFT", "cur=" + newTriple.curId);
        nikMsSectionRowShift(curIdx);
        nikMsSectionRowFillArmedIdx = null;
    } else {
        nikMsLog("SECTION_JUMP", "cur=" + newTriple.curId);
        nikMsSectionRowJump(curIdx);
        nikMsSectionRowFillArmedIdx = null;
    }

    nikMsSectionRowPrevTriple = newTriple;
}
