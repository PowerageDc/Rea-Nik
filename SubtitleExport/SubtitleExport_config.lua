-- Config de SubtitleExport. Se edita a mano; no contiene lógica.
return {
    -- Hueco entre un subtítulo y el siguiente (ms), para que los fades no se pisen.
    gap_ms = 10,

    -- Si el item arranca en medio de un acorde sostenido: true lo muestra desde el
    -- inicio del item; false espera al primer evento que caiga dentro del item.
    carry_in = false,

    -- Marca de orden de bytes UTF-8 al inicio del archivo (la usa el SRT guardado por SE).
    bom = true,

    -- Fin de línea del archivo.
    newline = "\r\n",

    -- Sufijo del archivo de salida: <nombre del proyecto><sufijo>.srt, junto al .rpp.
    output_suffix = "_Armonia",

    -- Desfase (s) entre el inicio de la ventana y el inicio del video: se suma a todos los tiempos.
    video_offset_s = 1.0,

    -- Tags de ASS dentro del SRT (posición, fuente, color, efectos). false genera
    -- un SRT limpio, sin ningún tag.
    tags = true,

    -- Resolución del video: base de las coordenadas de pos y de los efectos de clip.
    video_width = 1920,
    video_height = 1080,

    -- Efectos: duración base de la fase (ms) y fracción máxima de la duración de la
    -- línea que puede ocupar una fase. Las líneas más cortas que short_ms salen
    -- sin efecto (conservan posición, fuente y color).
    effect_ms = 300,
    effect_max_ratio = 0.25,
    short_ms = 1000,
    slide_px = 400, -- distancia de entrada del efecto "slide"

    -- Perfil activo: uno por escena o VSTi. Cada tipo de línea acepta:
    --   an     alineación 1-9 del teclado numérico (2 abajo al centro, 7 arriba a la izquierda...)
    --   pos    { x, y } en coordenadas de video; an pasa a ser el punto de anclaje
    --   fn     nombre de la fuente
    --   fs     tamaño de la fuente
    --   color  "RRGGBB"
    --   effect "fade", "grow", "bounce", "wipe" o "slide" (slide requiere pos)
    -- Lo que no se define hereda el estilo que aplica SE al quemar.
    profile = "keysight",
    profiles = {
        keysight = {
            chord = { an = 2, pos = { 960, 800 }, fn = "Arial", fs = 64, color = "FFD400", effect = "fade" },
        },
        base = {
            chord = { effect = "fade" },
        },
    },

    -- Reglas de display de acordes, aplicadas en orden: { patrón Lua, reemplazo }.
    -- Trabajan sobre la grafía guardada (b y # en ASCII). La regla de espaciado va
    -- antes de las conversiones a símbolo, porque los patrones de Lua operan por byte.
    chord_rules = {
        { "^([A-G][b#]?)(%d)", "%1 %2" },  -- F7 -> F 7 (separa el número de la raíz)
        { "([A-G])b",          "%1♭"   },  -- Bb -> B♭
        { "(%d)b",             "%1♭"   },  -- 7b9 -> 7♭9
        { "#",                 "♯"     },  -- C#m -> C♯m
        { "%s*/%s*",           " / "   },  -- C/G -> C / G
    },
}