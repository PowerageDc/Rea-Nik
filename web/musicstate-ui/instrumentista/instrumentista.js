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
        ";GET/EXTSTATE/NikRemote/reapitch_semitone" +
        ";GET/EXTSTATE/NikMusicState/publish_version";
}

function nikInstrumentistaInit() {
    wwr_req_recur("TRANSPORT", 10);
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
    var pos = parseFloat(playPosSeconds);
    var bpm = (typeof nikMsTempoAt === "function") ? nikMsTempoAt(pos) : null;
    if (bpm == null) return "—";
    return '<span class="ms-tempo-number">' + Math.round(bpm) + "</span> BPM";
}

function nikInstrumentistaFormatSongName() {
    return nikCurrentProjectName ? nikCurrentProjectName.replace(/\.rpp$/i, "") : "—";
}

function nikInstrumentistaRender() {
    var role = nikInstrumentistaGetRole();

    document.getElementById("msRole").textContent = role || "(sin rol)";
    document.getElementById("msKeyTonicText").innerHTML = nikInstrumentistaFormatKeyTonicHtml(
        (typeof nikMusicStateCurrentProjectKey === "function") ? nikMusicStateCurrentProjectKey() : null
    );
    document.getElementById("msTempo").innerHTML = nikInstrumentistaFormatTempo();
    document.getElementById("msSongName").textContent = nikInstrumentistaFormatSongName();

    var sectionEl = document.getElementById("msSection");
    var section = (typeof nikMsCurrentSection === "function") ? nikMsCurrentSection() : null;
    if (section) {
        sectionEl.textContent = section.displayName;
        sectionEl.style.color = section.resolvedColor || "";
    } else {
        sectionEl.textContent = "—";
        sectionEl.style.color = "";
    }

    // Previa/próxima -- misma fuente de datos que nikMsCurrentSection()
    // (nikMsMarkersSorted + nikMsFindSectionIndexAt), un índice antes y
    // uno después del vigente. Reusa nikMsMarkerChainMap ya resuelto por
    // ms-section.js -- no se recalcula nada acá, solo se lee.
    var curIdx = (typeof nikMsFindSectionIndexAt === "function")
        ? nikMsFindSectionIndexAt(parseFloat(playPosSeconds)) : -1;
    document.getElementById("msSectionPrev").textContent = nikInstrumentistaAdjacentSectionLabel(curIdx - 1);
    document.getElementById("msSectionNext").textContent = nikInstrumentistaAdjacentSectionLabel(curIdx + 1);

    nikInstrumentistaRenderChordStrip();

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

// Nombre de sección en un índice de nikMsMarkersSorted, o "" si el índice
// cae fuera de rango (no hay previa antes del primer marker, o no hay
// próxima después del último) -- el slot queda vacío, no "—", para no
// competir visualmente con el "—" de la sección actual sin dato.
function nikInstrumentistaAdjacentSectionLabel(idx) {
    if (idx < 0 || !nikMsMarkersSorted || idx >= nikMsMarkersSorted.length) return "";
    var row = nikMsMarkersSorted[idx];
    var resolved = nikMsMarkerChainMap[row[2]];
    return resolved ? resolved.displayName : "";
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

function nikInstrumentistaFindInsertBeforeNode(stripEl, offset) {
    var children = stripEl.children;
    for (var i = 0; i < children.length; i++) {
        var childOffset = parseInt(children[i].getAttribute("data-offset"), 10);
        if (childOffset > offset) return children[i];
    }
    return null;
}

// Shift limpio de ±1: no se reconstruye nada, se reetiquetan los data-offset
// de los nodos existentes (dispara la transición CSS sola) y se maneja el
// ciclo de vida del nodo que entra/sale por los offsets fantasma (±3).
// delta = -1: avanza (el actual pasa a anterior) -> entra por la derecha.
// delta = +1: retrocede -> entra por la izquierda.
function nikInstrumentistaShiftChordSlots(newList, delta) {
    var stripEl = document.getElementById("msChordStrip");
    var newByKey = {};
    for (var i = 0; i < newList.length; i++) newByKey[newList[i].key] = newList[i];

    var enterGhostOffset = (delta === -1) ? 3 : -3;
    var exitGhostOffset = (delta === -1) ? -3 : 3;

    for (var key in nikInstrumentistaChordNodesByKey) {
        if (!nikInstrumentistaChordNodesByKey.hasOwnProperty(key)) continue;
        var node = nikInstrumentistaChordNodesByKey[key];
        if (newByKey[key]) {
            node.setAttribute("data-offset", String(newByKey[key].offset));
        } else {
            node.setAttribute("data-offset", String(exitGhostOffset));
            (function (leavingNode, leavingKey) {
                var onLeave = function (ev) {
                    if (ev.propertyName !== "flex-basis" && ev.propertyName !== "opacity") return;
                    leavingNode.removeEventListener("transitionend", onLeave);
                    if (leavingNode.parentNode) leavingNode.parentNode.removeChild(leavingNode);
                    delete nikInstrumentistaChordNodesByKey[leavingKey];
                };
                leavingNode.addEventListener("transitionend", onLeave);
            })(node, key);
        }
    }

    // Los nodos continuos (ya existían y siguen existiendo) no se tocan acá
    // -- solo se les cambió data-offset arriba, y eso alcanza para que la
    // transición CSS corra sola sin reinsertarlos en el DOM. Solo los nodos
    // nuevos se insertan, usando como referencia el próximo nodo continuo (o
    // ya insertado en esta misma pasada) a su derecha en newList -- no la
    // dirección de delta, que era la causa del bug anterior.
    var nextNode = null;
    for (var j = newList.length - 1; j >= 0; j--) {
        var item = newList[j];
        var existing = nikInstrumentistaChordNodesByKey[item.key];

        if (existing) {
            nextNode = existing;
            continue;
        }

        var slot = document.createElement("span");
        slot.className = "ms-chord-slot";
        slot.setAttribute("data-offset", String(enterGhostOffset));
        slot.dataset.chordRaw = item.text;
        slot.innerHTML = nikInstrumentistaFormatChordHtml(item.text);

        if (nextNode) stripEl.insertBefore(slot, nextNode);
        else stripEl.appendChild(slot);

        nikInstrumentistaChordNodesByKey[item.key] = slot;
        (function (enteringNode, finalOffset) {
            void enteringNode.offsetWidth;
            requestAnimationFrame(function () {
                enteringNode.setAttribute("data-offset", String(finalOffset));
            });
        })(slot, item.offset);

        nextNode = slot;
    }
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
        nikInstrumentistaShiftChordSlots(newList, delta);
    }
    nikInstrumentistaChordPrevWindow = newList;
}

function nikInstrumentistaStartRenderLoop(intervalMs) {
    window.setInterval(nikInstrumentistaRender, intervalMs || 200);
}