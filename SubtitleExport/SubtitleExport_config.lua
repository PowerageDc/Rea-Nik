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