# Feature — SubtitleExport: subtítulos de armonía para videos de piano

Genera un archivo SRT con la armonía del proyecto (la que carga el Helper de
MusicState), transpuesta si hay ReaPitch en el Stem Bus, para quemarla como
subtítulo con Subtitle Edit (SE) sobre el video de piano que sale de KeySight.
Las convenciones de nombres están en `01_CONVENCIONES.md`; el modelo de los
datos de armonía, en `features/musicstate_data_model.md`.

## 1. Flujo de uso

1. Renderizar un wav de piano con la misma duración que el item MIDI, importar
   MIDI y wav en KeySight y renderizar el video. El item MIDI puede empezar en
   el compás 1, más tarde (donde arranca la música) o ser un fragmento.
2. En REAPER, dejar seleccionado **solo** el item MIDI del video (o, sin item
   seleccionado, definir una time selection) y ejecutar
   `Nik_SubtitleExport_Export.lua`. Escribe `<proyecto>_Armonia.srt` junto al
   `.rpp`, sobrescribiéndolo en cada corrida.
3. En SE, abrir el video y el SRT y quemar con *Video → Generate video with
   burned subtitles*, con los efectos globales de esa ventana desactivados
   (ver §8).

La consola de REAPER informa cantidad de subtítulos, perfil, transposición,
inicio de la ventana, desfase de video y duración mínima y máxima.

Avisos (cuadro de diálogo, no se escribe archivo): proyecto sin guardar, sin
armonía cargada, más de un item MIDI seleccionado, sin item ni time selection,
sin acordes dentro de la ventana, perfil inexistente en el config, semitonos
de ReaPitch ilegibles o distintos entre instancias, transposición sin
`project_key`, y error al escribir el archivo.

## 2. Archivos

| Archivo | Rol |
|---|---|
| `SubtitleExport/Nik_SubtitleExport_Export.lua` | Ejecutable: lee el proyecto, resuelve ventana y transposición, escribe el SRT |
| `SubtitleExport/SubtitleExport_common_logic.lua` | Lógica pura (sin API de REAPER): `parseHarmony`, `parseKey`, `parseSemitones`, `formatChord`, `buildEntries`, `buildTags`, `styleEntries`, `srtTime`, `toSrt` |
| `SubtitleExport/SubtitleExport_config.lua` | Valores editables a mano (§6 y §7) |
| `_Shared/MusicTranspose_common_logic.lua` | Port a Lua de `nikTranspose` (`core/music-transpose.js`): mismas tablas y criterio de grafía |

La conversión de compás a segundos y la lectura de ReaPitch viven en el
ejecutable; todo lo demás es lógica pura, probada por las sondas de §9.

## 3. Datos de armonía

- Origen: `ProjExtState` del proyecto activo, namespace `NSAUDIOMUSIC`, claves
  `harmony_data` y `project_key`. No se usa el `ExtState` global, que refleja
  el último proyecto que publicó. En el `.rpp`, `harmony_data` aparece como
  bloque `BIN` en base64; `GetProjExtState` devuelve el JSON original.
- El parseo usa patrones de Lua (`parseHarmony`, `parseKey`), sin librería
  JSON, con el mismo criterio que el Helper.
- Compás (1-indexado) más `qn_offset` pasan a segundos con
  `TimeMap_GetMeasureInfo` (que indexa desde 0) y `TimeMap2_QNToTime`, así que
  los cambios de tempo y de compás se resuelven con el tempo map.
- Cada evento dura hasta el siguiente evento; un `null` corta el acorde y no
  genera subtítulo. Un acorde sostenido varios compases es un solo subtítulo.
  El último acorde se corta al final de la ventana.

## 4. Ventana y alineación con el video

- Con un único item MIDI seleccionado, la ventana es ese item
  (`D_POSITION` y `D_LENGTH`). Sin item MIDI seleccionado, la time selection.
- Se descartan los eventos anteriores al inicio de la ventana. `carry_in`
  (config) hace que un acorde sostenido que viene de antes se muestre desde el
  inicio.
- `video_offset_s` suma un desfase constante a todos los tiempos. Se necesita
  porque el video de KeySight arranca 1,000 s antes que el item MIDI: se
  verificó con un item que empieza en el compás 1 (los subtítulos calzaban tras
  correrlos exactamente 1,000 s en SE). El origen de ese segundo (un retardo de
  KeySight o un padding de silencio en el wav) no está determinado.
- `gap_ms` deja un hueco entre subtítulos consecutivos para que los efectos de
  uno no se pisen con los del siguiente.

## 5. Transposición

El semitono sale de `ReaPitchBus.read_aggregated_state()`, que devuelve el
valor formateado de ReaPitch, `"none"` o `"mixed"`. `parseSemitones` toma su
parte entera truncada hacia cero, igual que el `parseInt` del cliente JS.

- `"none"` (sin ReaPitch) o delta 0: los acordes salen tal como se cargaron,
  sin reescribir la grafía.
- `"mixed"` (instancias con semitonos distintos): aborta con aviso.
- Delta distinto de 0 sin `project_key`: aborta con aviso.
- Delta distinto de 0 con ReaPitch desactivado o activado solo en algunas
  instancias: el audio no se transpone como indica el semitono, así que un
  cuadro pregunta si transponer igual (Sí), exportar sin transponer (No) o
  cancelar.
- Con delta transponible, `Transpose.key` decide una sola vez la grafía
  (sostenidos o bemoles) según la tonalidad resultante y `Transpose.chord` la
  aplica a cada acorde.

Diferencia con el prompter: el prompter transpone sin mirar si ReaPitch está
activado y deja pasar sin transponer los casos `"mixed"` y sin `project_key`.
Acá se avisa en esos casos porque un subtítulo equivocado en un video
terminado no se detecta después.

## 6. Formato de display de los acordes

`chord_rules` (config) es una lista ordenada de reglas `{ patrón, reemplazo }`
aplicada al acorde ya transpuesto. Hoy: separar el número de la raíz
(`F7` a `F 7`, por legibilidad con la tipografía usada), `b` y `#` a `♭` y `♯`,
y `/` con espacios. El orden importa: los patrones de Lua trabajan por byte, así
que el espaciado va antes de las conversiones a símbolo.

## 7. Estilos y efectos por perfil

Con `tags = true`, `styleEntries` antepone a cada subtítulo un bloque de tags de
ASS dentro del texto del SRT; con `tags = false` el SRT sale limpio. El perfil
activo (`profile`) se elige entre los de `profiles`: uno por escena o VSTi.
Cada perfil define un estilo por tipo de línea; hoy solo se aplica `chord`.

```lua
profiles = {
    keysight = {
        chord = { an = 2, pos = { 960, 800 }, fn = "Arial", fs = 64, color = "FFD400", effect = "fade" },
    },
},
```

- `an`: alineación 1-9 del teclado numérico. `pos`: `{ x, y }` en coordenadas de
  video (1920x1080, `video_width` y `video_height`); `an` pasa a ser el punto de
  anclaje. `fn`, `fs` y `color` (`"RRGGBB"`) son opcionales: lo que no se define
  hereda el estilo que aplica SE al quemar.
- `effect`: `fade`, `grow`, `bounce`, `wipe` o `slide` (este requiere `pos`).
- La fase del efecto dura el menor entre `effect_ms` y `effect_max_ratio` de la
  duración de la línea. Las líneas más cortas que `short_ms` salen sin efecto, y
  conservan posición, fuente y color.
- El perfil `keysight` ubica los acordes por encima del teclado, que ocupa la
  parte inferior del video.

## 8. Hallazgos sobre Subtitle Edit

Verificados con SRT de prueba (`Tests-Debug/SubtitleExport_TagsTest.srt`,
`SubtitleExport_TagsTest2.srt` y `SubtitleExport_TagsTest3.srt`), juzgando
siempre por el video quemado:

- El quemado respeta los tags de ASS escritos en el texto del SRT: `\an`, `\c`,
  `\pos`, `\move`, `\clip` animado, `\t`, `\fscx`/`\fscy`, `\frz`, `\fad`, `\fn`
  y `\fs`. Las coordenadas son las del video.
- Los efectos de *Video → Generate video with burned subtitles* (fade, bounce,
  rotate in, scroll...) son globales: no se configuran ni se aplican por línea.
  Con ese fade activo, el `\fad` del texto no se nota; con los efectos globales
  desactivados, el del script funciona.
- La vista previa de SE no muestra todo lo que muestra el quemado.
- Las posiciones distintas por tipo de línea evitan depender del apilado
  automático de SE para entradas solapadas.
- La celda de duración en rojo en SE marca las líneas de menos de 1 s (mínimo
  de SE). Es un aviso del editor y no afecta el quemado.
- SE no guarda un proyecto (video más subtítulos): recuerda el último estado.
- El SRT con tags solo sirve para quemar: en otro reproductor los tags se verían
  como texto. `tags = false` genera la variante limpia.

## 9. Cómo testear

- `Tests-Debug/Nik_SubtitleExport_ProbeLogic.lua`: asserts de la lógica pura
  (formato de acordes, intervalos, silencios, recorte de ventana, desfase,
  parsers, tags y efectos, SRT).
- `Tests-Debug/Nik_MusicTranspose_ProbeLogic.lua`: asserts del módulo de
  transposición con los casos conocidos del JS.
- Las dos sondas terminan con `N ok, 0 fallas` en la consola de REAPER.
- Manual: exportar un proyecto con el item MIDI seleccionado, cargar el SRT en SE
  junto al video y revisar sincronía y acordes. Validado con un proyecto de tempo
  variable y con transposición de ReaPitch.

## 10. Pendientes

- **Secciones como subtítulos:** leer los markers del proyecto (nombres de
  `01_CONVENCIONES.md`) con estilo `section`, hasta el próximo marker.
- **Cues como subtítulos:** leer `cues_data` con filtro por rol y estilo `cue`.
- Tipografías y tamaños por definir: explorar con más videos y VSTi, y crear
  perfiles para otras escenas.
- El efecto `wipe` barre el ancho de todo el cuadro, no el del texto: un acorde
  centrado empieza a verse a mitad de la fase.
- Determinar el origen del segundo de desfase y confirmarlo con un item que no
  empiece en el compás 1 y con una time selection.
- Casos de prueba compartidos entre `core/music-transpose.js` y el módulo Lua,
  para que no se desalineen.
- El nombre del SRT es solo el del proyecto: dos exportaciones del mismo proyecto
  (un fragmento y la canción completa) se sobrescriben.
- Evaluar acordes como `Cmaj7` con espacio entre raíz y calidad, si la
  tipografía lo pide.
- Posible extensión: letra (track `🎤 Lyrics`) como subtítulos.