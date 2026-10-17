# MVSEP Importer

Importa a un proyecto los zips descargados de MVSEP: los stems base (Drums,
Bass, Guitar, Piano, Other, Vocals, más el instrumental) y, en un paso
posterior, zips con un stem separado en partes (hoy: la voz en lead y
backing). Es un script local: no se distribuye por ReaPack (ver
`05_REAPACK_DEPLOY.md`). Los nombres de tracks y snapshots están en
`01_CONVENCIONES.md`.

## 1. Flujo

1. **Zip base**: `Nik_MvsepImporter_ImportStems.lua` llena el folder Stem Bus
   con los stems, recorta el item del click y deja la vista lista.
2. **Zips de split** (posterior, uno por ejecución): hoy
   `Nik_MvsepImporter_ImportVocalSplit.lua`, que suma `Vocals Lead` y
   `Vocals Back` debajo del track `Vocals` y silencia el original.

Son scripts separados a propósito: el importer base no crece con cada tipo de
zip y cada script nuevo reutiliza el módulo.

## 2. Archivos

| Archivo (en `MvsepImporter/`) | Responsabilidad |
|---|---|
| `Nik_MvsepImporter_ImportStems.lua` | Importer base: flujo completo del zip de stems, recorte del Beep, zoom y screenset. |
| `Nik_MvsepImporter_ImportVocalSplit.lua` | Zip de voz separada (lead/back). |
| `MvsepImporter_common_logic.lua` | Módulo compartido (ver más abajo). |
| `MvsepImporter_config.lua` | Valores editables: patrones de nombres, extensiones, recetas. Solo datos. |

El módulo carga el config y `_Shared/StemBus_common_logic.lua` (discovery del
Stem Bus y sus hijos). `Tests-Debug/Nik_Test_CloseDialogProbe.lua` es la sonda
con la que se resolvió la confirmación del diálogo de screenset.

### Módulo `MvsepImporter_common_logic.lua`

Expone `M.config` (la tabla del config) y dos grupos de funciones:

- **Sistema**: `to_powershell_encoded_command`, `is_windows`, `run_powershell`,
  `get_downloads_path`, `get_project_dir`, `ensure_media_folder`,
  `list_zip_entries`, `extract_zip_entries`, `find_locked_files`,
  `build_missing_peaks`.
- **Dominio**: `detect_stem`, `is_instrumental`, `get_extension`,
  `is_audio_file`, `get_stem_bus_children`, `insert_audio_item`,
  `insert_tracks_after`, `get_source_info`, `count_fx_by_name`,
  `find_track_with_fx`, `copy_fx_by_name`.

## 3. Config (`MvsepImporter_config.lua`)

| Clave | Qué es |
|---|---|
| `media_subfolder` | Subcarpeta de medios, relativa al `.rpp`. |
| `stems` | Familias reconocidas: `{ name, patterns }`, con patrones de Lua sobre el nombre en minúsculas. |
| `instrumental_patterns` | Patrones del instrumental (cubre `instrum` e `instrumental`). |
| `audio_extensions` | Extensiones válidas (`wav`, `mp3`, `flac`). |
| `zoom_padding_bars` | Compases de aire a la derecha del zoom-fit. |
| `save_screenset_command_id` | Acción "Screenset: Save track view #01" (pisa el screenset "ALL"). |
| `click_folder_pattern`, `click_track_pattern` | Discovery del track de Beep (ver 4.5). |
| `vocal_split` | Receta del zip de voz separada (ver 5). |

Si MVSEP cambia sus nombres de archivo, se ajustan los patrones acá, sin tocar
lógica. Los patrones son de Lua: el guion va escapado (`%-`).

## 4. Importer base

### 4.1 Pasos

1. Diálogo de archivo, abierto en la carpeta de Descargas.
2. Carpeta del proyecto y discovery de los hijos del Stem Bus.
3. Listado del zip **sin extraer** y clasificación de cada audio: instrumental,
   familia de stem o no reconocido. Un segundo audio de una misma familia se
   omite.
4. Carpeta Media (creación y vista de Explorer), chequeo de archivos en uso y
   extracción **solo de los audios reconocidos, ya con su nombre final**
   (`Drums.mp3`, `Instrumental.flac`...).
5. Colocación: cada stem va al primer hijo del bus cuyo nombre lo detecta; el
   instrumental, a un track cuyo nombre lo detecta. Los items se insertan en 0
   con el archivo completo.
6. Recorte del Beep, build de peaks, zoom y screenset.

Todo ocurre en un único bloque de deshacer. Los avisos de lo omitido o sin
track se vuelcan a la consola.

### 4.2 Stem Bus

El discovery usa `StemBus_common_logic.lua`: acepta los alias `stem bus` y
`stems bus` sin distinguir mayúsculas. `get_stem_bus_children` además exige que
el bus sea un folder (`I_FOLDERDEPTH > 0`).

### 4.3 Carpeta del proyecto y Descargas

- La carpeta del proyecto sale de `EnumProjects` (la ruta del `.rpp`), no de
  `GetProjectPath`, que devuelve el recording path (`.../Media`).
- La ruta de Descargas se lee del registro de Windows, porque puede estar
  redirigida a otra unidad.
- `ensure_media_folder` aplica el `desktop.ini` ("Elementos generales" en
  Explorer) solo cuando falta.

### 4.4 Archivos en uso

REAPER mantiene abiertos los archivos de los items y Windows no deja
sobrescribirlos. `find_locked_files` lo detecta abriendo cada destino existente
antes de extraer; si alguno está en uso se muestra la lista y no se extrae nada.
Para reimportar hay que borrar antes los items que usan esos archivos.

### 4.5 Recorte del Beep

El extremo derecho del item del track de Beep (hijo del folder Click) se recorta
al extremo mayor de los items importados. El track se descubre por nombre: contiene
`click_track_pattern` y su padre directo contiene `click_folder_pattern`, ambos
sin distinguir mayúsculas. En la plantilla ese item es el único del track y dura
10 minutos.

### 4.6 Zoom y screenset

Tras importar se ajusta la vista al largo del item de referencia más
`zoom_padding_bars` compases y se guarda el screenset con la acción
configurada. Esa acción abre un diálogo ("Save Track View Screenset #1") que
espera confirmación:

- `Main_OnCommand` bloquea al script hasta que el diálogo se cierra, así que
  con JS_ReaScriptAPI la acción se **postea** (`JS_WindowMessage_Post`) y el
  script queda libre.
- Un vigilante con `reaper.defer` busca la ventana del diálogo y la confirma con
  `JS_Window_OnCommand(hwnd, 1)` (retardo corto y reintento, tope de 10 s).
  Otros métodos (`BM_CLICK` al botón Save, IDOK, clics de mouse) no cerraron el
  diálogo.
- Sin JS_ReaScriptAPI se lanza la acción directa y el diálogo pide Enter.

## 5. Script de voces separadas

Zip esperado (modelo karaoke de MVSEP): `...vocals-lead.mp3`,
`...vocals-back.mp3`, más `back-instrum` e `instrum-only`, que no se usan.

### 5.1 Receta `vocal_split`

```lua
vocal_split = {
  outputs = {
    { pattern = "vocals%-lead", file = "Vocals_Lead", track = "Vocals Lead" },
    { pattern = "vocals%-back", file = "Vocals_Back", track = "Vocals Back" },
  },
  source_stem = "Vocals",
  mute_source = true,
  copy_fx = "reapitch",
}
```

Cada salida toma el primer audio del zip cuyo nombre coincide con su `pattern`.
Si falta alguna, el script aborta sin extraer nada. Los demás audios del zip no
se extraen. `source_stem` es la familia de `stems` cuyo track sirve de origen
(posición, color, FX) y se silencia.

### 5.2 Pasos

1. Chequeos previos a extraer: bus con hijos, zip legible, una entrada por
   salida, tracks de salida sin items, destinos libres.
2. Extracción de los dos audios con nombre final y colocación.
3. **Posición**: el origen del source del track de voz existente
   (`D_POSITION - D_STARTOFFS`), así los items siguen cualquier desplazamiento
   hecho antes (count-in, tempo mapping). Si no hay track o item, los orígenes de
   varios items difieren, el playrate no es 1 o el origen es negativo, se coloca en 0
   y se avisa.
4. **Tracks**: se crean justo debajo del track de voz; si no hay track de voz,
   quedan como últimos hijos del bus. Si el track de referencia cerraba el
   folder, el cierre pasa al último track nuevo para que queden dentro. Copian
   el color del original.
5. **Mute**: el original se silencia solo cuando se crean los tracks, para no
   pisar un unmute manual en una reejecución.
6. **ReaPitch**: se copia la instancia desde el track de voz o, si no la tiene,
   desde el primer hijo que sí. La copia lleva el valor de semitonos actual. Si
   ningún hijo la tiene, se avisa.
7. **Peaks y vista**: se construyen los peaks y se refresca el arrange. No se
   reaplican zoom, screenset ni `desktop.ini`.

### 5.3 Reejecución

Si `Vocals Lead` o `Vocals Back` ya existen con items, el script aborta con el
aviso y no extrae. Si existen vacíos, los reutiliza. Un solo bloque de deshacer
cubre tracks e items; la extracción de archivos no se deshace.

### 5.4 Avisos

La consola muestra: posición que no se pudo derivar, duración de un audio que
difiere en más de 50 ms de la del track de voz, ReaPitch ausente y source que no
se pudo crear.

## 6. Decisiones y gotchas

- **Media tiene archivos ajenos** (la canción original, sobregrabaciones,
  otros mp3). Por eso el importer nunca enumera Media: clasifica solo las entradas
  del zip. Con el escaneo anterior, un `Bass take 2.wav` propio se habría
  renombrado y pisado.
- **Solo se extrae lo reconocido**, con el nombre final calculado antes de extraer.
  Los demás audios del zip no tocan el disco.
- **Listado del zip**: se filtra por extensión dentro de PowerShell y se corta en
  200 entradas. Sin filtro, zips con muchos archivos no-audio colgaban el
  listado hasta el timeout (probable saturación de la salida).
- **PowerShell por `-EncodedCommand`** (Base64 de UTF-16LE): el comando nunca
  viaja como argumento con tildes o ñ, así que la codepage ANSI no lo corrompe.
  Los errores de PowerShell se vuelcan a la consola (View > Show console
  output).
- **Peaks**: los items insertados por script no generan picos hasta cambiar de
  ventana; `build_missing_peaks` ejecuta "Peaks: Build any missing peaks" tras
  insertar.
- **MP3**: la versión gratuita de MVSEP entrega mp3, también en los stems base.
  Las voces separadas alinean con los stems sin drift ni offset detectado.
- **Folder**: al insertar tracks debajo del último hijo hay que mover el cierre
  del folder (`I_FOLDERDEPTH` negativo); `insert_tracks_after` lo resuelve y se
  niega a insertar debajo de un folder.
- **Nombre exacto antes que patrón**: al buscar el track de voz, el nombre exacto
  gana sobre la detección por patrón, y los tracks de salida de la receta nunca
  cuentan como origen (`Vocals Lead` también detectaría "vocal").

## 7. Pendientes

- **Snapshots `SN_*`**: guardan el estado por track; los tracks nuevos no están en
  ningún snapshot ya guardado y un recall puede volver a desilenciar el `Vocals`
  original. Hay que definir cómo entran `Vocals Lead` y `Vocals Back` en
  `SN_Vocals` y `SN_Instrumental` y cuándo se regeneran. Ver
  `01_CONVENCIONES.md` y `features/render_workflow.md`.
- **Volumen de los tracks nuevos**: igualarlo al de los demás tracks del bus o, si
  difieren, al mayor de ellos. Normalmente se baja el volumen de todos los tracks
  cuando alguno clipea, así que los nuevos deberían seguir ese nivel.
- **Más tipos de import** (tres o más): splits de guitarras o vientos, y un
  instrumento solo desglosado del track Other. Cada uno es una receta nueva en el
  config; falta un motor que lea la receta en lugar de tenerla fija en el script de
  voces.
- **Bus (folder) para los splits** (voz, guitarras): crear un folder que agrupe
  las partes. A resolver: el efecto sobre `get_folder_children`, que devuelve todos
  los descendientes del Stem Bus, el lugar de ReaPitch (en el folder o en los hijos)
  y el sentido del mute.
- **Despachador de multiselección**: un diálogo que acepte varios zips
  (`JS_Dialog_BrowseForOpenFiles` con selección múltiple), detecte cada receta por
  el contenido del zip y procese primero el zip base, porque los splits necesitan
  los tracks y items ya creados.
- **Motor de recetas**: pasar al módulo la lógica de colocación del script de
  voces (origen, tracks, FX, alineación, items) como una función que reciba la
  receta. Cada tipo de zip queda como una entrada del config más un wrapper corto,
  y el despachador llama a la misma función.
- **Vista previa antes de extraer**: un cuadro de confirmación con el mapeo
  archivo → track y destino, al menos cuando haya algo omitido o ambiguo. Los datos
  ya existen antes de la extracción.
- **Sonda de clasificación**: un script en `Tests-Debug/` que reciba una lista de
  nombres de archivo y muestre cómo los clasifican `detect_stem` y las recetas, para
  probar cambios de nombres de MVSEP sin hacer un import real.
- **Dividir este doc**: separar el importer base de las recetas y el despachador en
  docs distintos cuando haya tres o más recetas o exista el despachador. El nombre
  del doc nuevo se define al crearlo.

## 8. Qué adjuntar según la tarea

| Tarea | Docs | Código |
|---|---|---|
| Ajustar patrones o agregar una receta | `mvsep_importer.md` | `MvsepImporter_config.lua`, `Nik_MvsepImporter_ImportVocalSplit.lua` |
| Importer base (zip de stems, Beep, zoom, screenset) | `mvsep_importer.md` | `Nik_MvsepImporter_ImportStems.lua`, `MvsepImporter_common_logic.lua`, `MvsepImporter_config.lua` |
| Módulo (zips, PowerShell, tracks) | `mvsep_importer.md` | `MvsepImporter_common_logic.lua`, `_Shared/StemBus_common_logic.lua` |
| Snapshots y render de los tracks nuevos | `mvsep_importer.md`, `01_CONVENCIONES.md`, `features/render_workflow.md` | scripts de snapshots |