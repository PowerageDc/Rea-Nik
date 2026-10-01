// instrumentista.js — bootstrap real del perfil Instrumentista (MusicState)
//
// Arma los polls definitivos (TRANSPORT, MARKER, slow poll) y dispara los
// pedidos on-demand de boot. Reemplaza, para este propósito, al bloque
// inline de nsaudio_musicstate_test.html -- el test HTML sigue teniendo su
// propio panel de debug (nikMsTestRefreshDebugPanel), que no es parte de
// este archivo (eso es rendering, no bootstrap).
//
// Requiere, ya cargados antes en el <script> del shell que lo use:
// main.js, config.js, config.local.js (opcional), core/utils.js,
// markers/markers.js, core/music-transpose.js, core/music-state.js,
// musicstate-ui/shared/ms-tempo.js, ms-section.js, ms-dispatch.js.

function nikInstrumentistaBuildSlowPoll() {
    // Mismo criterio que el test: reusa el script consolidado (ya escribe
    // reapitch_semitone y active_project_name en cada corrida) -- no un
    // script nuevo, y sin arrastrar el resto de NIK_ONDEMAND_READS
    // (playrate/preservepitch/marker_bars/solo-in-front, irrelevantes
    // para este perfil).
    return NIK_LUA_COMMANDS.statePoll.commandId +
        ";GET/EXTSTATE/NikRemote/active_project_name" +
        ";GET/EXTSTATE/NikRemote/playrate" +
        ";GET/EXTSTATE/NikRemote/reapitch_semitone" +
        ";GET/EXTSTATE/NikMusicState/publish_version";
}

function nikInstrumentistaInit() {
    g_wwr_timer_freq = 20;
    wwr_req_recur("TRANSPORT", 100);
    wwr_req_recur("MARKER", 500);
    wwr_req_recur(nikInstrumentistaBuildSlowPoll(), 1000);
    wwr_start();

    // On-demand, mismo criterio que boot del remoto general (init.js real):
    // no esperar al primer cambio de proyecto para tener datos.
    nikMsRequestTempoAndTimesig();
    if (typeof nikMusicStateRequestAll === "function") nikMusicStateRequestAll();
}

// --- Selector de rol: persistencia por dispositivo (localStorage, no ---
// --- tab-ui-memory.js -- el eje acá es "de quién es este celular",   ---
// --- no el proyecto/tab activo de REAPER, ver diseño §4).            ---

var NIK_INSTRUMENTISTA_ROLE_STORAGE_KEY = "nikInstrumentistaRole";

function nikInstrumentistaGetRole() {
    try { return window.localStorage.getItem(NIK_INSTRUMENTISTA_ROLE_STORAGE_KEY); }
    catch (e) { return null; }
}

function nikInstrumentistaSetRole(role) {
    try { window.localStorage.setItem(NIK_INSTRUMENTISTA_ROLE_STORAGE_KEY, role); }
    catch (e) { /* localStorage no disponible (modo privado, etc.) -- sin persistencia, no bloqueante */ }
}

// "todos" es válido siempre (reservado, IMPL_MusicState.md §11.1), sin
// necesidad de estar en nikMusicStateProjectRoles. Se calcula on-demand,
// sin cachear -- nikMusicStateProjectRoles llega on-demand (ver
// ms-dispatch.js) y puede no estar listo todavía al momento del boot, o
// puede cambiar tras un cambio de proyecto sin que haya un evento que avise.
function nikInstrumentistaIsRoleValid(role) {
    if (!role) return false;
    if (role === "todos") return true;
    return nikMusicStateProjectRoles.indexOf(role) !== -1;
}

// --- Render: layout vertical estático (roadmap punto 3, doc §5) ---
// Separado de nikInstrumentistaInit() a propósito: el bootstrap (polls,
// on-demand) tiene que poder correr solo, sin asumir que existen estos
// IDs de DOM -- así nsaudio_musicstate_test.html sigue funcionando sin
// tocar nada, y el render solo lo arranca el shell que sí tiene esta
// estructura (nsaudio_musicstate_instrumentista_preview.html).

// "maj"/"min" son los únicos casos confirmados (ejemplo del doc de
// diseño). Cualquier otro modo cae al fallback genérico -- no confirmado
// contra el string real que devuelve nikTranspose para modos no
// estándar (dórico, mixolidio, etc.), no debería aparecer en el uso
// actual pero no se descarta.
var NIK_INSTRUMENTISTA_KEY_TONIC_REGEX = /^([A-G])([#b]?)$/;

function nikInstrumentistaFormatKeyTonicHtml(key) {
    if (!key || !key.tonic) return "—";
    var m = NIK_INSTRUMENTISTA_KEY_TONIC_REGEX.exec(key.tonic);
    if (!m) return nikInstrumentistaEscapeHtml(key.tonic); // fallback si el formato no matchea

    var html = "<span>" + m[1] + "</span>";
    if (m[2]) {
        var isSharp = (m[2] === "#");
        var accClass = isSharp ? "ms-key-accidental-sharp" : "ms-key-accidental-flat";
        var accGlyph = isSharp ? "♯" : "♭";
        html += '<span class="' + accClass + '">' + accGlyph + "</span>";
    }
    if (key.mode === "minor") {
        html += '<span class="ms-key-minor">m</span>';
    }
    // major: no se agrega nada. Cualquier otro modo (dórico, mixolidio...):
    // tampoco se agrega nada por ahora -- no confirmado contra un caso real,
    // igual que el fallback que reemplaza.
    return html;
}

function nikInstrumentistaFormatTempo() {
    var pos = nikMsEffectivePosSeconds();
    var bpm = (typeof nikMsTempoAt === "function") ? nikMsTempoAt(pos) : null;
    if (bpm == null) return "—";
    if (typeof nikMusicStatePlayRate === "function") bpm *= nikMusicStatePlayRate();
    return '<span class="ms-tempo-number">' + Math.round(bpm) + "</span> BPM";
}

function nikInstrumentistaFormatSongName() {
    return nikCurrentProjectName ? nikCurrentProjectName.replace(/\.rpp$/i, "") : "—";
}

var NIK_INSTRUMENTISTA_STALE_MS = 1500;
var nikInstrumentistaScreenEl = null;

var nikInstrumentistaBeatLastKey = null;
var nikInstrumentistaChordEventLastKey = null;
var nikInstrumentistaBeatDotCount = null;
var nikInstrumentistaBeatProgressFilling = false;

function nikInstrumentistaUpdateStaleIndicator() {
    if (!nikInstrumentistaScreenEl) nikInstrumentistaScreenEl = document.querySelector(".ms-screen");
    if (!nikInstrumentistaScreenEl) return;
    var last = (typeof nikTransportAnchorMs === "number") ? nikTransportAnchorMs : 0;
    var isStale = (performance.now() - last) > NIK_INSTRUMENTISTA_STALE_MS;
    nikInstrumentistaScreenEl.classList.toggle("is-stale", isStale);
    if (isStale && typeof g_wwr_errcnt === "number" && g_wwr_errcnt > 2) g_wwr_errcnt = 2;
}

function nikInstrumentistaRender() {
    nikInstrumentistaUpdateStaleIndicator();
    var role = nikInstrumentistaGetRole();

    document.getElementById("msRole").textContent = role || "(sin rol)";
    document.getElementById("msKeyTonicText").innerHTML = nikInstrumentistaFormatKeyTonicHtml(
        (typeof nikMusicStateCurrentProjectKey === "function") ? nikMusicStateCurrentProjectKey() : null
    );
    document.getElementById("msTempo").innerHTML = nikInstrumentistaFormatTempo();
    document.getElementById("msSongName").textContent = nikInstrumentistaFormatSongName();

    nikInstrumentistaRenderSectionRow();

    nikInstrumentistaRenderChordStrip();
    nikInstrumentistaRenderBeat();

    // "todos" no se pasa tal cual a nikMusicStateActiveCues -- esa función
    // trata "sin filtro" como null/undefined (devuelve todas), no como el
    // string "todos" (que restringiría solo a cues con "todos" en roles,
    // perdiendo las cues de rol específico). Traducimos acá para no tocar
    // la firma ya cerrada de music-state.js.
    var roleFilter = (!role || role === "todos") ? undefined : role;
    var cues = (typeof nikMusicStateActiveCues === "function") ? nikMusicStateActiveCues(roleFilter) : [];
    var cueBandEl = document.getElementById("msCueBand");
    if (cues.length > 0) {
        cueBandEl.textContent = cues.map(function (c) { return c.text; }).join(" · ");
        cueBandEl.classList.add("is-visible");
    } else {
        cueBandEl.classList.remove("is-visible");
    }
}

var NIK_INSTRUMENTISTA_SECTION_PRELUDE_SEC = 2;
var nikInstrumentistaSectionPrevTriple = null;   // null = todavía no hubo primer render
var nikInstrumentistaSectionFillArmedIdx = null; // curIdx para el que ya se disparó el fill de "next"
var nikInstrumentistaSectionJumpPendingIdx = null;

function nikInstrumentistaSectionId(sec) { return sec ? sec.id : null; }

// Repintado directo, sin animación -- primer render, o después del fade de
// un salto (nikInstrumentistaJumpSectionRow).
function nikInstrumentistaPaintSectionRow(curIdx) {
    var byIndex = (typeof nikMsSectionByIndex === "function") ? nikMsSectionByIndex : function () { return null; };
    var prev = byIndex(curIdx - 1);
    var cur = byIndex(curIdx);
    var next = byIndex(curIdx + 1);

    var prevEl = document.getElementById("msSectionPrev");
    var curEl = document.getElementById("msSection");

    prevEl.textContent = prev ? prev.displayName : "";
    prevEl.style.color = "";
    curEl.textContent = cur ? cur.displayName : "—";
    curEl.style.color = cur ? (cur.resolvedColor || "") : "";
    nikInstrumentistaSetNextLabel(next);
}

// Contenido + color de "next" -- el color ya es el destino real de esa
// sección (no un preview neutro): el fill, mientras todavía está chico a
// la derecha, ya "pinta" el color real que va a tener al llegar al
// centro, sin necesidad de mutar ningún color en el cruce.
function nikInstrumentistaSetNextLabel(next) {
    var nextEl = document.getElementById("msSectionNext");
    var nextFillEl = document.getElementById("msSectionNextFill");
    nextEl.textContent = next ? next.displayName : "";
    nextFillEl.textContent = next ? next.displayName : "";
    nextFillEl.style.color = next ? (next.resolvedColor || "") : "";
    nikInstrumentistaResetSectionFill(nextFillEl);
}

function nikInstrumentistaResetSectionFill(nextFillEl) {
    nextFillEl.style.transition = "none";
    nextFillEl.style.clipPath = "inset(100% 0 0 0)";
    void nextFillEl.offsetHeight;
    nextFillEl.style.transition = "";
}

// Arranca el fill sobre "next" -- una sola transición CSS con duración =
// segundos reales que faltan (no un valor fijo), para que termine de
// llenarse justo en el instante del cruce sin importar en qué punto exacto
// del poll de 50ms se haya detectado el umbral.
function nikInstrumentistaArmSectionFill(secRemaining) {
    var nextFillEl = document.getElementById("msSectionNextFill");
    requestAnimationFrame(function () {
        nextFillEl.style.transition = "clip-path " + secRemaining + "s linear";
        nextFillEl.style.clipPath = "inset(0 0 0 0)";
    });
}

// FLIP simple: dx/dy/scale a partir de un rect "antes" -- no depende de que
// sea el mismo nodo que tenía ese rect, solo de que el rect sea correcto.
function nikInstrumentistaFlipFromRect(el, beforeRect) {
    var after = el.getBoundingClientRect();
    var dx = beforeRect.left - after.left;
    var dy = beforeRect.top - after.top;
    var sx = beforeRect.width / after.width;
    var sy = beforeRect.height / after.height;
    el.style.transitionProperty = "none";
    el.style.transform = "translate(" + dx + "px," + dy + "px) scale(" + sx + "," + sy + ")";
    void el.offsetHeight;
    el.style.transitionProperty = "";
    requestAnimationFrame(function () { el.style.transform = ""; });
}

// Lo que sourceEl tenía se desvanece en su lugar en vez de descartarse sin
// más -- mismo patrón que usan los acordes salientes (clon posicionado +
// fade). Limpia el id del clon antes de insertarlo (ver "Clonar elementos
// DOM con id" en 01_CONVENCIONES.md). El forced reflow entre insertar y
// bajar la opacity es necesario -- sin él el navegador puede coalescer
// ambos estilos y la transición no arranca (mismo bug ya visto con la
// tira de acordes).
function nikInstrumentistaGhostFadeOut(sourceEl, containerEl) {
    if (!sourceEl.textContent) return;
    var r = sourceEl.getBoundingClientRect();
    var cr = containerEl.getBoundingClientRect();
    var ghost = sourceEl.cloneNode(true);
    ghost.removeAttribute("id");
    ghost.style.position = "absolute";
    ghost.style.left = (r.left - cr.left) + "px";
    ghost.style.top = (r.top - cr.top) + "px";
    ghost.style.width = r.width + "px";
    ghost.style.margin = "0";
    ghost.style.transitionProperty = "opacity";
    containerEl.appendChild(ghost);
    void ghost.offsetHeight;
    ghost.style.opacity = "0";
    ghost.addEventListener("transitionend", function onDone(ev) {
        if (ev.propertyName !== "opacity") return;
        ghost.removeEventListener("transitionend", onDone);
        if (ghost.parentNode) ghost.parentNode.removeChild(ghost);
    });
}

// Entrada de "next" -- mismo tratamiento que los acordes entrantes (fade +
// escala chica).
function nikInstrumentistaFadeInEntering(el) {
    el.style.transitionProperty = "none";
    el.style.opacity = "0";
    el.style.transform = "scale(0.7)";
    void el.offsetHeight;
    el.style.transitionProperty = "";
    requestAnimationFrame(function () {
        el.style.opacity = "";
        el.style.transform = "";
    });
}

// Cruce limpio de a un índice: "actual" toma el rect de donde estaba
// "next", "prev" toma el rect de donde estaba "actual".
function nikInstrumentistaShiftSectionRow(newCurIdx) {
    var rowEl = document.getElementById("msSectionRow");
    var prevEl = document.getElementById("msSectionPrev");
    var curEl = document.getElementById("msSection");
    var nextEl = document.getElementById("msSectionNext");

    var rCurBefore = curEl.getBoundingClientRect();
    var rNextBefore = nextEl.getBoundingClientRect();

    nikInstrumentistaGhostFadeOut(prevEl, rowEl);

    var byIndex = (typeof nikMsSectionByIndex === "function") ? nikMsSectionByIndex : function () { return null; };
    var newCur = byIndex(newCurIdx);
    var newNext = byIndex(newCurIdx + 1);

    prevEl.textContent = curEl.textContent;
    prevEl.style.color = "";
    curEl.textContent = newCur ? newCur.displayName : "—";
    curEl.style.color = newCur ? (newCur.resolvedColor || "") : "";
    nikInstrumentistaSetNextLabel(newNext);

    nikInstrumentistaFlipFromRect(prevEl, rCurBefore);
    nikInstrumentistaFlipFromRect(curEl, rNextBefore);
    nikInstrumentistaFadeInEntering(nextEl);
}

// Salto (seek, o cualquier transición que no sea un avance de a un
// índice): sin "antes" válido para FLIP -- fade de toda la fila, repintado
// directo por debajo, fade de vuelta. Mismo patrón que
// nikInstrumentistaRebuildChordSlots(..., true), incluida la protección
// contra saltos seguidos muy rápido.
function nikInstrumentistaJumpSectionRow(curIdx) {
    var rowEl = document.getElementById("msSectionRow");
    nikInstrumentistaSectionJumpPendingIdx = curIdx;
    if (rowEl.classList.contains("is-jumping")) return;

    rowEl.classList.add("is-jumping");
    var onFadeOut = function (ev) {
        if (ev.propertyName !== "opacity") return;
        rowEl.removeEventListener("transitionend", onFadeOut);
        nikInstrumentistaPaintSectionRow(nikInstrumentistaSectionJumpPendingIdx);
        nikInstrumentistaSectionJumpPendingIdx = null;
        rowEl.classList.remove("is-jumping");
    };
    rowEl.addEventListener("transitionend", onFadeOut);
}

// Punto de entrada, llamado desde nikInstrumentistaRender(). Recalcula
// prev/actual/next por IDENTIDAD (no por índice numérico) en cada tick --
// mismo criterio que nikInstrumentistaRenderChordStrip con la tira de
// acordes: comparar solo el índice numérico se quedaba pegado mostrando
// datos viejos/vacíos cuando los datos de fondo cambiaban (ej. markers
// recién cargados) sin que el índice se moviera.
function nikInstrumentistaRenderSectionRow() {
    var pos = nikMsEffectivePosSeconds();
    var curIdx = (typeof nikMsFindSectionIndexAt === "function") ? nikMsFindSectionIndexAt(pos) : -1;
    var byIndex = (typeof nikMsSectionByIndex === "function") ? nikMsSectionByIndex : function () { return null; };

    var newTriple = {
        prevId: nikInstrumentistaSectionId(byIndex(curIdx - 1)),
        curId: nikInstrumentistaSectionId(byIndex(curIdx)),
        nextId: nikInstrumentistaSectionId(byIndex(curIdx + 1))
    };
    var old = nikInstrumentistaSectionPrevTriple;

    if (old === null) {
        nikInstrumentistaPaintSectionRow(curIdx);
        nikInstrumentistaSectionFillArmedIdx = null;
    } else if (newTriple.prevId === old.prevId && newTriple.curId === old.curId && newTriple.nextId === old.nextId) {
        if (nikInstrumentistaSectionFillArmedIdx !== curIdx) {
            var secUntilNext = (typeof nikMsSecUntilNextSection === "function") ? nikMsSecUntilNextSection(pos) : null;
            if (secUntilNext !== null && secUntilNext <= NIK_INSTRUMENTISTA_SECTION_PRELUDE_SEC) {
                nikInstrumentistaArmSectionFill(secUntilNext);
                nikInstrumentistaSectionFillArmedIdx = curIdx;
            }
        }
        nikInstrumentistaSectionPrevTriple = newTriple;
        return;
    } else if (newTriple.prevId === old.curId && newTriple.curId === old.nextId) {
        nikInstrumentistaShiftSectionRow(curIdx);
        nikInstrumentistaSectionFillArmedIdx = null;
    } else {
        nikInstrumentistaJumpSectionRow(curIdx);
        nikInstrumentistaSectionFillArmedIdx = null;
    }

    nikInstrumentistaSectionPrevTriple = newTriple;
}

var nikInstrumentistaChordNodesByKey = {};
var nikInstrumentistaChordPrevWindow = null; // null = todavía no hubo primer render
var nikInstrumentistaChordJumpPendingList = null;

function nikInstrumentistaChordKey(entry) {
    return entry.bar + "_" + entry.qn_offset;
}

// chord === null es el sentinel de silencio explícito (ver
// core/music-state.js) -- se muestra distinguible de "sin dato".
// undefined (offset sin entrada en la ventana) se muestra vacío, no "—",
// para no competir visualmente con el silencio explícito.
function nikInstrumentistaChordSlotText(entry) {
    if (!entry) return "";
    return entry.chord === null ? "—" : entry.chord;
}

function nikInstrumentistaEscapeHtml(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

var NIK_INSTRUMENTISTA_CHORD_REGEX =
    /^([A-G])([#b]?)(maj7|maj|m7b5|dim7|dim|aug|m)?(\d+)?(sus2|sus4|add9|add11|add13)?(\/[A-G][#b]?)?$/;

function nikInstrumentistaFormatChordHtml(text) {
    if (!text) return "";
    var m = NIK_INSTRUMENTISTA_CHORD_REGEX.exec(text);
    if (!m) return nikInstrumentistaEscapeHtml(text);

    var html = '<span class="chord-part-root">' + m[1] + "</span>";
    if (m[2]) {
        var accClass = (m[2] === "#") ? "chord-part-sharp" : "chord-part-flat";
        html += '<span class="' + accClass + '">' + m[2] + "</span>";
    }
    if (m[3]) {
        var qualityClass = (m[3] === "m") ? "chord-part-quality-minor" : "chord-part-quality";
        html += '<span class="' + qualityClass + '">' + m[3] + "</span>";
    }
    if (m[4]) html += '<span class="chord-part-number">' + m[4] + "</span>";
    if (m[5]) html += '<span class="chord-part-sub">' + m[5] + "</span>";
    if (m[6]) html += '<span class="chord-part-bass">' + m[6] + "</span>";
    return html;
}

// Traduce la ventana cruda de nikMusicStateChordWindow a la forma que usa
// el resto de este módulo: key estable por ocurrencia (bar+qn_offset,
// única incluso si el mismo acorde se repite en la canción), offset
// relativo -2..2, y el texto ya resuelto (con transposición aplicada).
function nikInstrumentistaComputeOffsets(win) {
    var currentIdx = -1;
    for (var i = 0; i < win.length; i++) { if (win[i].isCurrent) { currentIdx = i; break; } }

    // Identidad de referencia para los placeholders (offsets sin acorde
    // real, típico cerca del principio/final de la canción): se ancla a
    // la key del acorde vigente, no a un valor fijo -- así, cuando el
    // vigente cambia (shift real), la key del placeholder "cambia" junto
    // con él y el diff lo trata como salida+entrada por el mismo
    // mecanismo de ghost que ya existe para acordes reales, en vez de
    // dejarlo inmóvil descuadrando el ancho total de la tira.
    var anchorKey = (currentIdx !== -1) ? nikInstrumentistaChordKey(win[currentIdx]) : "NOCURRENT";

    var byOffset = {};
    for (var j = 0; j < win.length; j++) {
        // La fórmula general ya cubre currentIdx=-1 sin caso especial:
        // offset = j - (-1) = j+1 -- los acordes antes de que suene el
        // primero quedan en +1/+2 (próximos), nada vigente todavía. El
        // caso especial anterior (offset=0 para todos) colapsaba varias
        // entradas de `win` sobre el mismo offset en `byOffset`, pisándose
        // entre sí -- es la causa del bug ya anotado en la sesión de
        // layout ("doble acorde resaltado al inicio de canción").
        var offset = j - currentIdx;
        byOffset[offset] = win[j];
    }

    var result = [];
    for (var o = -2; o <= 2; o++) {
        var entry = byOffset[o];
        if (entry) {
            result.push({ key: nikInstrumentistaChordKey(entry), offset: o, text: nikInstrumentistaChordSlotText(entry) });
        } else {
            result.push({ key: "PH_" + anchorKey + "_" + o, offset: o, text: "" });
        }
    }
    return result;
}

function nikInstrumentistaSameStructure(a, b) {
    if (a.length !== b.length) return false;
    for (var i = 0; i < a.length; i++) {
        if (a[i].key !== b[i].key || a[i].offset !== b[i].offset) return false;
    }
    return true;
}

// Determina si la ventana nueva es un shift limpio de ±1 respecto a la
// anterior: las keys en común deben tener todas el mismo delta de offset,
// y ese delta debe ser exactamente ±1. Sin overlap, con deltas
// inconsistentes entre sí, o con delta de magnitud >1 -> no es shift
// limpio, se resuelve como salto (sección nueva, cursor movido lejos).
function nikInstrumentistaDetectShift(prevList, newList) {
    var prevByKey = {};
    for (var i = 0; i < prevList.length; i++) prevByKey[prevList[i].key] = prevList[i].offset;

    var delta = null;
    var commonCount = 0;
    for (var j = 0; j < newList.length; j++) {
        var key = newList[j].key;
        if (!(key in prevByKey)) continue;
        commonCount++;
        var d = newList[j].offset - prevByKey[key];
        if (delta === null) delta = d;
        else if (d !== delta) return null;
    }
    if (commonCount === 0) return null;
    if (delta !== 1 && delta !== -1) return null;
    return delta;
}

// Reconstrucción completa de los 5 slots visibles (offset -2..2), igual
// criterio que la versión original: los 5 offsets siempre existen en el
// DOM aunque `newList` traiga menos elementos, para que el ancho
// geométrico de la tira nunca cambie. `withFade` envuelve el swap en el
// fade de `.is-jumping` (ver CSS) -- se usa para el caso de salto, no
// para el primer render (ahí no hay nada previo que desvanecer).
function nikInstrumentistaRebuildChordSlots(newList, withFade) {
    var stripEl = document.getElementById("msChordStrip");

    function doRebuild(list) {
        stripEl.innerHTML = "";
        nikInstrumentistaChordNodesByKey = {};
        var byOffset = {};
        for (var i = 0; i < list.length; i++) byOffset[list[i].offset] = list[i];
        for (var o = -2; o <= 2; o++) {
            var slot = document.createElement("span");
            slot.className = "ms-chord-slot";
            slot.setAttribute("data-offset", String(o));
            var item = byOffset[o];
            slot.dataset.chordRaw = item ? item.text : "";
            slot.innerHTML = item ? nikInstrumentistaFormatChordHtml(item.text) : "";
            stripEl.appendChild(slot);
            if (item) nikInstrumentistaChordNodesByKey[item.key] = slot;
        }
    }

    if (!withFade) { doRebuild(newList); return; }

    // Si ya hay un fade de salto en curso (saltos seguidos muy rápido),
    // no se agrega un segundo listener -- quedaría huérfano, porque el
    // navegador no vuelve a disparar transitionend si la opacity ya está
    // en 0. Alcanza con actualizar cuál es la ventana "pendiente": el
    // listener ya armado la usa cuando dispare.
    nikInstrumentistaChordJumpPendingList = newList;
    if (stripEl.classList.contains("is-jumping")) return;

    stripEl.classList.add("is-jumping");
    var onFadeOut = function (ev) {
        if (ev.propertyName !== "opacity") return;
        stripEl.removeEventListener("transitionend", onFadeOut);
        doRebuild(nikInstrumentistaChordJumpPendingList);
        nikInstrumentistaChordJumpPendingList = null;
        stripEl.classList.remove("is-jumping");
    };
    stripEl.addEventListener("transitionend", onFadeOut);
}

// FLIP de toda la tira en un solo lote: se mide la posición/tamaño real
// (getBoundingClientRect, incluye cualquier transform en vuelo de un shift
// anterior -- ya no hace falta nikInstrumentistaGetCurrentScale aparte) de
// todo lo que sigue vivo ANTES de tocar nada; se aplican TODAS las
// mutaciones del shift (salientes fuera del flujo, continuos reetiquetados,
// entrantes insertados en su offset final) sin leer nada en el medio; se
// mide UNA sola vez el estado resultante; y se disfraza cada nodo afectado
// con transform para soltarlo recién en el próximo frame -- un solo flush
// de layout por shift entero, no uno por nodo, y nada de flex-basis
// animado (ya no varía: los salientes se sacan del flujo con
// position:absolute en vez de vía offset fantasma).
function nikInstrumentistaShiftChordSlots(newList) {
    var stripEl = document.getElementById("msChordStrip");
    var newByKey = {};
    for (var i = 0; i < newList.length; i++) newByKey[newList[i].key] = newList[i];

    var containerRectBefore = stripEl.getBoundingClientRect();

    // FIRST
    var beforeRects = {};
    var continuingKeys = [];
    var exitingKeys = [];
    for (var key in nikInstrumentistaChordNodesByKey) {
        if (!nikInstrumentistaChordNodesByKey.hasOwnProperty(key)) continue;
        beforeRects[key] = nikInstrumentistaChordNodesByKey[key].getBoundingClientRect();
        if (newByKey[key]) continuingKeys.push(key); else exitingKeys.push(key);
    }

    // MUTATE -- salientes primero: sacarlos del flujo ya, para que los
    // continuos calculen su posición final sin el saliente estorbando.
    for (var ei = 0; ei < exitingKeys.length; ei++) {
        var exitKey = exitingKeys[ei];
        var leavingNode = nikInstrumentistaChordNodesByKey[exitKey];
        var er = beforeRects[exitKey];
        leavingNode.style.position = "absolute";
        leavingNode.style.left = (er.left - containerRectBefore.left) + "px";
        leavingNode.style.top = (er.top - containerRectBefore.top) + "px";
        leavingNode.style.width = er.width + "px";
        leavingNode.style.transitionProperty = "opacity";
        leavingNode.style.opacity = "0";
        (function (node2, key2) {
            var onLeave = function (ev) {
                if (ev.propertyName !== "opacity") return;
                node2.removeEventListener("transitionend", onLeave);
                if (node2.parentNode) node2.parentNode.removeChild(node2);
            };
            node2.addEventListener("transitionend", onLeave);
        })(leavingNode, exitKey);
        delete nikInstrumentistaChordNodesByKey[exitKey];
    }

    // MUTATE -- continuos: reetiquetar data-offset (salto instantáneo de
    // font-size/flex-basis, ya no animan por CSS).
    for (var ci = 0; ci < continuingKeys.length; ci++) {
        var contKey = continuingKeys[ci];
        nikInstrumentistaChordNodesByKey[contKey].setAttribute("data-offset", String(newByKey[contKey].offset));
    }

    // MUTATE -- entrantes: insertar directo en su offset final (ya no hay
    // paso intermedio por offset fantasma), mismo criterio de referencia
    // que antes (próximo nodo continuo o recién insertado a su derecha).
    var enteringNodes = [];
    var nextNode = null;
    for (var j = newList.length - 1; j >= 0; j--) {
        var item = newList[j];
        var existingNode = nikInstrumentistaChordNodesByKey[item.key];
        if (existingNode) { nextNode = existingNode; continue; }

        var slot = document.createElement("span");
        slot.className = "ms-chord-slot";
        slot.setAttribute("data-offset", String(item.offset));
        slot.dataset.chordRaw = item.text;
        slot.innerHTML = nikInstrumentistaFormatChordHtml(item.text);
        if (nextNode) stripEl.insertBefore(slot, nextNode);
        else stripEl.appendChild(slot);

        nikInstrumentistaChordNodesByKey[item.key] = slot;
        enteringNodes.push(slot);
        nextNode = slot;
    }

    // LAST -- una sola pasada de layout para toda la tira ya mutada.
    var disguises = [];
    for (var ci2 = 0; ci2 < continuingKeys.length; ci2++) {
        var ck = continuingKeys[ci2];
        var node = nikInstrumentistaChordNodesByKey[ck];
        var before = beforeRects[ck];
        var after = node.getBoundingClientRect();
        var dx = before.left - after.left;
        var dy = before.top - after.top;
        var sx = before.width / after.width;
        var sy = before.height / after.height;
        if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5 || Math.abs(sx - 1) > 0.01 || Math.abs(sy - 1) > 0.01) {
            disguises.push({
                node: node, exclude: "opacity, color",
                from: "translate(" + dx + "px," + dy + "px) scale(" + sx + "," + sy + ")"
            });
        }
    }
    for (var ei2 = 0; ei2 < enteringNodes.length; ei2++) {
        disguises.push({ node: enteringNodes[ei2], exclude: "", from: "scale(0.6)", fadeIn: true });
    }

    // INVERT -- disfraz sin transición, todos los nodos del lote juntos.
    for (var di = 0; di < disguises.length; di++) {
        var d = disguises[di];
        d.node.style.transitionProperty = d.exclude || "none";
        d.node.style.transform = d.from;
        if (d.fadeIn) d.node.style.opacity = "0";
    }
    if (disguises.length) void stripEl.offsetHeight; // un solo flush para todo el lote

    // PLAY -- restaurar transición completa; próximo frame, soltar al
    // reposo (transform:none), de ahí en más compositor-only.
    for (var dj = 0; dj < disguises.length; dj++) {
        disguises[dj].node.style.transitionProperty = "";
    }
    requestAnimationFrame(function () {
        for (var dk = 0; dk < disguises.length; dk++) {
            disguises[dk].node.style.transform = "";
            if (disguises[dk].fadeIn) disguises[dk].node.style.opacity = "";
        }
    });
}

// Misma estructura (mismas ocurrencias en las mismas posiciones) pero
// texto distinto -- único motivo posible: cambio de transposición
// (ReaPitch semitonos) en caliente, sin mover el cursor. Se actualiza el
// texto en el lugar, sin animar posición (no es un shift real).
function nikInstrumentistaRefreshTextInPlace(newList) {
    for (var i = 0; i < newList.length; i++) {
        var item = newList[i];
        var node = nikInstrumentistaChordNodesByKey[item.key];
        if (node && node.dataset.chordRaw !== item.text) {
            node.dataset.chordRaw = item.text;
            node.innerHTML = nikInstrumentistaFormatChordHtml(item.text);
        }
    }
}

function nikInstrumentistaRenderChordStrip() {
    var stripEl = document.getElementById("msChordStrip");
    if (typeof nikMusicStateChordWindow !== "function") { stripEl.textContent = "—"; return; }

    var win = nikMusicStateChordWindow(2, 2);
    var newList = nikInstrumentistaComputeOffsets(win);

    if (nikInstrumentistaChordPrevWindow === null) {
        nikInstrumentistaRebuildChordSlots(newList, false);
        nikInstrumentistaChordPrevWindow = newList;
        return;
    }

    if (nikInstrumentistaSameStructure(nikInstrumentistaChordPrevWindow, newList)) {
        nikInstrumentistaRefreshTextInPlace(newList);
        nikInstrumentistaChordPrevWindow = newList;
        return;
    }

    var delta = nikInstrumentistaDetectShift(nikInstrumentistaChordPrevWindow, newList);
    if (delta === null) {
        nikInstrumentistaRebuildChordSlots(newList, true);
    } else {
        nikInstrumentistaShiftChordSlots(newList);
    }
    nikInstrumentistaChordPrevWindow = newList;
}

function nikInstrumentistaRenderBeat() {
    if (typeof nikBeat === "undefined") return;
    var pos = nikBeat.currentPos();
    if (!pos) return;

    var pulseCount = nikBeat.pulseCountAt(pos.bar);
    var pulseIdx = nikBeat.currentPulseIndex(pos.bar, pos.qn_offset);
    var pulseKey = pos.bar + "_" + pulseIdx;
    if (pulseKey !== nikInstrumentistaBeatLastKey) {
        nikInstrumentistaBeatLastKey = pulseKey;
        nikInstrumentistaFlashBeatDot(pulseIdx, pulseCount);
    }

    if (!nikMusicStateIsPlaying()) {
        if (nikInstrumentistaBeatProgressFilling) {
            nikInstrumentistaResetBeatProgress();
            nikInstrumentistaBeatProgressFilling = false;
        }
        return;
    }

    var chordPos = (typeof nikMusicStateCurrentPos === "function") ? nikMusicStateCurrentPos() : null;
    if (!chordPos || nikMusicStateHarmonyFlat.length === 0) return;
    var idx = nikMusicStateFindIndexAtOrBefore(nikMusicStateHarmonyFlat, chordPos);
    if (idx === -1) return;
    var chordEventKey = nikInstrumentistaChordKey(nikMusicStateHarmonyFlat[idx]);
    if (chordEventKey === nikInstrumentistaChordEventLastKey) return;
    nikInstrumentistaChordEventLastKey = chordEventKey;
    nikInstrumentistaStartChordRing(nikBeat.secUntilNextChordEvent());
    nikInstrumentistaBeatProgressFilling = true;
}

function nikInstrumentistaFlashBeatDot(pulseIdx, pulseCount) {
    var dotsEl = document.getElementById("msBeatDots");
    if (!dotsEl) return;

    if (pulseCount !== nikInstrumentistaBeatDotCount) {
        nikInstrumentistaBeatDotCount = pulseCount;
        dotsEl.innerHTML = "";
        for (var i = 0; i < pulseCount; i++) {
            var dot = document.createElement("span");
            dot.className = "ms-beat-dot";
            dotsEl.appendChild(dot);
        }
    }

    var children = dotsEl.children;
    for (var j = 0; j < children.length; j++) {
        children[j].classList.toggle("is-active", j === (pulseIdx - 1));
    }
}

// Reset instantáneo a scaleX(0) (sin transición) + forzar reflow antes de
// animar -- mismo patrón FLIP (disfrazar sin transición, forzar flush,
// soltar en el próximo frame) que usa nikInstrumentistaShiftChordSlots.
// secUntilNext ya viene calculado UNA VEZ por
// nikBeat.secUntilNextChordEvent() al cruzar el evento anterior -- acá no
// se recalcula nada, solo se dispara la transición CSS.
function nikInstrumentistaResetBeatProgress() {
    var fillEl = document.getElementById("msBeatProgressFill");
    if (!fillEl) return;
    fillEl.classList.remove("is-filling");
    fillEl.style.transitionDuration = "0s";
    fillEl.style.transform = "scaleX(0)";
    void fillEl.offsetWidth;
}

function nikInstrumentistaStartChordRing(secUntilNext) {
    nikInstrumentistaResetBeatProgress();
    if (!secUntilNext || secUntilNext <= 0) return;

    var fillEl = document.getElementById("msBeatProgressFill");
    if (!fillEl) return;
    fillEl.style.transitionDuration = secUntilNext + "s";
    fillEl.classList.add("is-filling");
    fillEl.style.transform = "scaleX(1)";
}

function nikInstrumentistaStartRenderLoop(intervalMs) {
    window.setInterval(nikInstrumentistaRender, intervalMs || 200);
}