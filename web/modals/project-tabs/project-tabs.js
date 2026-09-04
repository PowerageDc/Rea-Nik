// modals/project-tabs/project-tabs.js — lógica del popup de selector de proyectos (tabs).
// Markup en project-tabs.html (inyectado por modal-loader.js al boot).
// Depende de: NIK_LUA_COMMANDS, NIK_ONDEMAND_READS (config.js).
//
// nikRenderProjectTabsList() es llamada por nombre desde wwr_onreply
// (dispatch central en index.html) cuando llega el ExtState
// "project_tabs" — lectura on-demand, deliberadamente fuera del poll de
// fondo (ver remote_control.md, "Selector de proyectos (tabs)").
//
// nikParseProjectTabs() se mudó acá desde index.html: es un parser
// exclusivo de este dominio (nadie más lo usa), a diferencia de
// nikParseMarkerBars (que sí es compartido y queda en index.html).
//
// Cargado como <script src> clásico (sin type="module"): las funciones
// cuelgan de `window` para que el onclick="nikOpenProjectTabsModal()" del
// nikTabBar en index.html, y la llamada desde wwr_onreply, las encuentren
// igual que antes.

// "idx:nombre:esActivo;idx:nombre:esActivo;..." -> [{idx, name, active}, ...]
// (split defensivo: el nombre podria en teoria contener ":" — se toma el primer
// campo como idx, el ultimo como flag activo, y todo lo del medio como nombre)
function nikParseProjectTabs(str) {
    var list = [];
    if (!str) return list;
    var entries = str.split(";");
    for (var i = 0; i < entries.length; i++) {
        var parts = entries[i].split(":");
        if (parts.length < 3) continue;
        list.push({
            idx: parts[0],
            name: parts.slice(1, parts.length - 1).join(":"),
            active: (parts[parts.length - 1] == "1")
            });
        }
    return list;
    }

function nikOpenProjectTabsModal() {
    nikRefreshProjectTabsHighlight();
    wwr_req(NIK_LUA_COMMANDS.projectTabsRead.commandId + ";GET/EXTSTATE/NikRemote/project_tabs");
    document.getElementById("nikProjectTabsOverlay").style.display = "flex";
    }

// Repinta el resaltado de la lista ya renderizada (de la última apertura)
// contra nikCurrentProjectName, que el poll de fondo mantiene fresco sin
// costo extra — evita mostrar el resaltado viejo mientras se espera la
// respuesta on-demand de Nik_ProjectTabs_Read.lua (ver remote_control.md,
// "Selector de proyectos (tabs)", bug de parpadeo).
function nikRefreshProjectTabsHighlight() {
    var list = document.getElementById("nikProjectTabsList");
    if (!list || typeof nikCurrentProjectName == "undefined" || nikCurrentProjectName == null) return;
    var items = list.children;
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var isActive = (item.getAttribute("data-name") == nikCurrentProjectName);
        item.setAttribute("data-active", isActive ? "1" : "0");
        item.style.color = isActive ? "#00FF99" : "#A8A8A8";
        }
    }

function nikCloseProjectTabsModal() {
    document.getElementById("nikProjectTabsOverlay").style.display = "none";
    }

function nikRenderProjectTabsList(str) {
    var list = document.getElementById("nikProjectTabsList");
    if (!list) return;
    list.innerHTML = "";
    var tabs = nikParseProjectTabs(str);
    for (var i = 0; i < tabs.length; i++) {
        var tab = tabs[i];
        var item = document.createElement("div");
        item.style.cssText = "display:flex; justify-content:space-between; align-items:center; padding:12px 8px; font-family:'Open Sans',sans-serif; font-size:1.3em; border-bottom:1px solid #262626; color:" +
            (tab.active ? "#00FF99" : "#A8A8A8") + ";";
        var nameSpan = document.createElement("span");
        nameSpan.textContent = tab.name;
        var metaSpan = document.createElement("span");
        metaSpan.style.cssText = "color:#999999; font-size:0.8em; margin-left:8px; flex-shrink:0;";
        // Reservado para metadata futura (BPM / metrica / tonalidad), sin uso hoy.
        metaSpan.textContent = "";
        item.appendChild(nameSpan);
        item.appendChild(metaSpan);
        item.setAttribute("data-idx", tab.idx);
        item.setAttribute("data-active", tab.active ? "1" : "0");
        item.setAttribute("data-name", tab.name);
        item.onclick = function(){
            if (this.getAttribute("data-active") == "1") { nikCloseProjectTabsModal(); return; }
            wwr_req("SET/EXTSTATE/NikRemote/project_tabs_target_idx/" + this.getAttribute("data-idx") + ";" + NIK_LUA_COMMANDS.projectTabsSelect.commandId + ";" + NIK_ONDEMAND_READS);
            nikCloseProjectTabsModal();
            };
        list.appendChild(item);
        }
    }
