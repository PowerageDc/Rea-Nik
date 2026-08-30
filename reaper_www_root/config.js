// config.js — Command IDs y valores de customización rápida del Control Remoto.
// Editar ACÁ cuando se registra/cambia un script Lua en el Action List, o para
// ajustar timing/paleta sin tener que buscar en el resto del código.
//
// Arquitectura de referencia: Script Lua + ExtState + polling — ver
// remote_control.md, sección "Arquitectura del patrón".
//
// Cargado como <script src="config.js"> clásico (sin type="module"): todo lo
// declarado acá cuelga de `window` para no romper los onclick="..." inline
// del resto del HTML.

// ==== Command IDs de scripts Lua (_RS...) ====
// Cambian por PC — hay que re-registrar cada script en el Action List al
// mudar de máquina/sala de ensayo. `luaFile: null` = wrapper no identificado
// todavía contra la carpeta real de Scripts (pendiente reorg, ver
// remote_control.md al final — convención Nik_<Dominio>_<Acción>.lua).
// `pending: true` = el hash de acá es un placeholder, falta reemplazarlo por
// el Command ID real una vez registrado el script (remote_control.md,
// sección "Selector de proyectos (tabs)").
var NIK_LUA_COMMANDS = {
    reaPitchSet: {
        luaFile: null, // TODO: confirmar wrapper — dominio ReaPitchBus_common_logic
        commandId: "_RS69b0d0e40546eb776731c126893ea732568ba5f1"
    },
    reaPitchToggle: {
        luaFile: null, // TODO: confirmar wrapper — dominio ReaPitchBus_common_logic
        commandId: "_RSdbe069eef00ee928d32efbc9fa40ebe5959d1a58"
    },
    playrateSet: {
        luaFile: null, // TODO: confirmar wrapper
        commandId: "_RS35ee59851e32d4035c0c1914625876598a00a56f"
    },
    playrateTogglePreservePitch: {
        luaFile: null, // TODO: confirmar wrapper
        commandId: "_RSd4dafe70c206819a3c906a669bfa32c9cb243f6b"
    },
    trackVisRefresh: {
        luaFile: "Nik_TrackVis_Refresh.lua",
        commandId: "_RSd4ca4185e84293eb4a275e830d4a8f2d49e6ff1c"
    },
    // Lectura consolidada: proyecto activo + playrate/preserve pitch +
    // ReaPitch (semitonos/enabled) + compases por sección, en un solo
    // script/Command ID — ver remote_control.md, "Lectura de estado
    // consolidada". Agregar una lectura nueva = sumar sección DENTRO de este
    // script (o su common_logic), nunca un _RS nuevo encadenado acá.
    statePoll: {
        luaFile: "Nik_RemoteState_Poll.lua",
        commandId: "_RS19b96a416380cfbddafb6cbe4286d672c2164d1f"
    },
    // Lectura on-demand, deliberadamente FUERA del poll de fondo (costo de
    // EnumProjects no vale la pena en cada tick de 1000ms) — ver
    // remote_control.md, "Selector de proyectos (tabs)".
    projectTabsRead: {
        luaFile: "Nik_ProjectTabs_Read.lua",
        commandId: "_RSfcdb45e82a335b4d78adcca0497fd3542c4a53d5",
        pending: true // placeholder, reemplazar al registrar en el Action List
    },
    projectTabsSelect: {
        luaFile: "Nik_ProjectTabs_Select.lua",
        commandId: "_RS4f0dfe650a14d8d7a0d02bd40e4c59df0c1bed89",
        pending: true // placeholder, reemplazar al registrar en el Action List
    },
    // Botones ⏮/⏭ del nikTabBar — van encadenados con la acción nativa 40667
    // (no forman parte del objeto, van hardcodeados junto a este Command ID
    // en el propio onclick). luaFile TODO: confirmar contra la reorg de la
    // carpeta Lua.
    tabPrev: {
        luaFile: null, // TODO: confirmar
        commandId: "_RS6acff9912f9ff42bc863923681cc5b9ffcff568a"
    },
    tabNext: {
        luaFile: null, // TODO: confirmar
        commandId: "_RSe7e6a21b05170da8e39895ffee19150db1ae89ee"
    }
};

// ==== Poll de fondo consolidado ====
// GOTCHA (remote_control.md): sumar una key nueva a Nik_RemoteState_Poll.lua
// NO ALCANZA — si no se agrega su GET/EXTSTATE/NikRemote/<key> acá también,
// el Lua escribe el ExtState pero la request bundleada nunca lo pide y el JS
// nunca lo recibe (pasó con marker_bars). Mantener esta lista sincronizada
// con lo que efectivamente escribe Nik_RemoteState_Poll.lua.
var NIK_SLOW_POLL = NIK_LUA_COMMANDS.statePoll.commandId +
    ";GET/EXTSTATE/NikRemote/active_project_name" +
    ";GET/EXTSTATE/NikRemote/playrate" +
    ";GET/EXTSTATE/NikRemote/preservepitch" +
    ";GET/EXTSTATE/NikRemote/reapitch_semitone" +
    ";GET/EXTSTATE/NikRemote/reapitch_enabled" +
    ";GET/EXTSTATE/NikRemote/marker_bars";

// Alias: hoy el refresco puntual (al abrir un modal) pide exactamente lo
// mismo que el poll de fondo — no hay razón para mantenerlos separados.
var NIK_ONDEMAND_READS = NIK_SLOW_POLL;

// ==== Diccionario de colores/traducción de markers por sección ====
// Editable acá — fuente de verdad de colores, ver 01_CONVENCIONES.md (del
// control remoto) para los nombres de sección del proyecto.
// "words"  : formas completas, match por PREFIJO sobre el nombre normalizado
//            (sin acentos/espacios, minúsculas) -> solo cambia el color.
// "abbrev" : formas abreviadas, match EXACTO -> cambia el color Y ADEMÁS
//            traduce el texto mostrado al label completo (+ número si tenía).
// "tint"   : reservado, sin uso hoy (pensado para fondo tipo chip).
// Colores auditados con contraste WCAG AA (≥4.5:1) contra #1a1a1a.
var NIK_MARKER_COLOR_MAP = [
    { label: "Intro",        color: "#a07e21", tint: "#f2ecd1", words: ["intro"],        abbrev: ["in"] },
    { label: "Verso",        color: "#4884d3", tint: "#e8edf3", words: ["verso"],        abbrev: ["v"] },
    { label: "Precoro",      color: "#c6608a", tint: "#f2e3ea", words: ["precoro"],      abbrev: ["pc"] },
    { label: "Coro",         color: "#cb6a10", tint: "#f0ddb8", words: ["coro", "estribillo"], abbrev: ["c", "e", "estribo"] },
    { label: "Puente",       color: "#9571ce", tint: "#eae3f2", words: ["puente"],       abbrev: ["p"] },
    { label: "Solo",         color: "#e74b4b", tint: "#f4d9d9", words: ["solo"],         abbrev: ["s"] },
    { label: "Instrumental", color: "#82829f", tint: "#e2e2e6", words: ["instrumental"], abbrev: ["instr", "instr.", "instrum", "instrum."] },
    { label: "Interludio",   color: "#82829f", tint: "#e2e2e6", words: ["interludio"],   abbrev: ["inter", "interl"] },
    { label: "Outro",        color: "#129485", tint: "#e3f1ee", words: ["outro"],        abbrev: ["o", "out"] },
    { label: "Coda",         color: "#10947e", tint: "#c9ecdf", words: ["coda"],         abbrev: [] },
    { label: "Final",        color: "#7c7ccb", tint: "#d9d9e6", words: ["final"],        abbrev: ["fin"] }
];

// Cadena x2, x3, x4... hereda el color del último marker categorizado
// encontrado antes en la lista, aclarando hacia blanco un paso fijo por
// cada eslabón sucesivo. Usado tanto por el popup como por los indicadores
// de transporte (helper compartido nikResolveMarkerDisplay(), en markers.js).
var NIK_MARKER_CHAIN_PATTERN = /^x\d+$/;
var NIK_MARKER_CHAIN_STEP = 0.18;

// ==== Timing / UX ====
var NIK_FADER_DBLTAP_MS = 300; // ventana de doble-tap para reset de fader a 0dB

// 1 = tamaño original; <1 achica todo el bloque play/pause/stop por igual,
// sin deformar (ver calculateScale() en core/).
var NIK_TRANSPORT_SCALE = 0.55;
