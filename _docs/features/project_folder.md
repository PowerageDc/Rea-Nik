# ProjectFolder

Acciones del Action List para trabajar con las carpetas del proyecto activo:
abrir la raíz, Media o Render, y juntar dentro del proyecto los samples que
usan sus FX para que viajen en el zip. Los nombres de carpetas y scripts
siguen `01_CONVENCIONES.md`.

## 1. Acciones

| Acción | Script | Qué hace |
|---|---|---|
| Abrir raíz, Media o Render | `Nik_ProjectFolder_Open*.lua` | Abre la carpeta en el Explorador. Si falta, ofrece crearla. |
| Juntar samples | `Nik_ProjectFolder_CollectSamples.lua` | Copia a `Media\Samples` los archivos que usan los FX de las pestañas abiertas y que están fuera del proyecto. |

## 2. Archivos

| Archivo | Responsabilidad |
|---|---|
| `ProjectFolder/ProjectFolder_common_logic.lua` | Módulo de las acciones de abrir carpeta: `run(modo)`. Su cabecera lista lo aprendido con sondas. |
| `ProjectFolder/ProjectFolder_config.lua` | Valores editables. Hoy: `render_default`, la carpeta de render cuando el proyecto no tiene una configurada. |
| `ProjectFolder/Nik_ProjectFolder_CollectSamples.lua` | Recolección de samples. Constantes editables al inicio. |
| `_Shared/FolderView_common_logic.lua` | Crear una carpeta y fijar su vista de Explorer; ejecutar PowerShell sin ventana. |
| `Tests-Debug/Nik_ProjectFolder_Probe*.lua` | Sondas con las que se resolvieron las rutas y la verificación de existencia. |

## 3. Abrir carpetas

La ruta sale de la configuración del proyecto (`RECORD_PATH` para Media,
`RENDER_FILE` para Render), sin consultar nada que cree carpetas. Si el
proyecto no tiene render configurado se usa `render_default`. Si la carpeta no
existe se ofrece crearla y, en Windows, se le escribe un `desktop.ini` con vista
Documentos. El detalle de los gotchas (tildes en rutas, caché de
`EnumerateSubdirectories`, atributos del `desktop.ini`) está en la cabecera del
módulo.

## 4. Juntar samples

Un RS5k guarda la ruta absoluta de su sample, aunque el archivo esté dentro de
la carpeta del proyecto. Al abrir el proyecto en otra PC esa ruta no existe, pero
REAPER encuentra el archivo por nombre dentro de la carpeta del proyecto. Por eso
alcanza con que el sample viaje en el zip: no hace falta relinkear al abrir.

El script recorre todas las pestañas abiertas:

1. Omite las pestañas sin guardar (no tienen carpeta de destino) y las lista.
2. Consulta `FILE0`, `FILE1`... en cada FX de cada pista, sin filtrar por nombre
   de FX: una instancia renombrada ("Sticks (RS5K)") igual responde. Cubre
   cualquier FX con lista de archivos, como una IR de ReaVerb.
3. Omite los archivos que no existen y los que ya están dentro de la carpeta del
   proyecto.
4. Copia el resto a `<carpeta del .rpp>\Media\Samples\` con una sola llamada de
   PowerShell por proyecto. Estados: `COPIED`, `SAME` (mismo nombre y tamaño),
   `DIFF` (mismo nombre, otro tamaño: no se pisa), `ERROR`.
5. Dos samples distintos con el mismo nombre en un proyecto: se omite el segundo.

La carpeta de destino se deriva de la ruta del `.rpp`, no de `GetProjectPath`,
que puede apuntar a otro lado según las opciones del proyecto. `Samples` se crea
con vista Documentos.

`RELINK` (constante al inicio, `false`) apunta además el FX a la copia con
`TrackFX_SetNamedConfigParm` (`FILE<n>` seguido de `DONE`). No está probado; con
`false` el script no modifica ningún proyecto.

Se corre a mano antes de empaquetar, con las pestañas del día abiertas.

## 5. FolderView

`FolderView.ensure_folder(path, folder_type)` crea la carpeta (y los padres que
falten) y, si no tiene `desktop.ini`, lo escribe y fija los atributos. Escribe el
ini desde PowerShell y no con `io.open`, que falla con tildes en rutas UTF-8.
Pone ReadOnly y System en la carpeta, y Hidden y System en el ini. Solo la carpeta
final recibe vista; los padres nuevos quedan con la vista por defecto.
`folder_type` es `Documents`, `Generic`, etc. `FolderView.run_powershell` ejecuta
un comando por `-EncodedCommand` (Base64 de UTF-16LE), para que tildes y ñ no
pasen por la codepage ANSI.

## 6. Decisiones y gotchas

- **Relink descartado**: con la ruta absoluta rota y el sample dentro de la
  carpeta del proyecto, en otra unidad y otra carpeta padre, REAPER lo resolvió
  solo.
- **Sin filtro por nombre de FX**: el RS5k del track de Count In está renombrado.
- **Copia por PowerShell** (`Copy-Item -LiteralPath`), por el mismo problema de
  `io.open` con tildes.
- **Solo FX de pistas**: no se recorren la pista master, los FX de entrada ni los
  FX de items.

## 7. Pendientes

- **Verificar el flujo completo en la PC de la sala**: zip con clave, descarga,
  extracción y apertura, confirmando que el sample se resuelve.
- **Empaquetado en lote desde REAPER**: hoy el zip se arma con el menú contextual
  (ver `STEMS_ZIPPER.md`), seleccionando a mano todo menos la carpeta de render.
  Evaluar un `Nik_ProjectFolder_Pack.lua` que recorra las pestañas y excluya la
  carpeta de render. Puntos: reutilizar el zipper (la clave vive en su `.bat`) en
  lugar de comprimir desde Lua; ver cómo el `.bat` recibe varias rutas por
  invocación; calcular la carpeta de render con la lógica de este dominio (hoy
  local en el módulo, habría que extraerla); guardar o saltear pestañas con
  cambios; correr la recolección de samples antes. Alternativa más barata:
  excluir la carpeta de render con un switch `-x` en el `.bat`.
- **Aviso en el empaquetado**: detectar en el `.rpp` rutas absolutas de samples
  fuera de la carpeta del proyecto, para cubrir el olvido de correr la
  recolección.
- **Migrar a `FolderView`** la vista de Explorer y el ejecutor de PowerShell de
  `MvsepImporter_common_logic.lua` y de `ProjectFolder_common_logic.lua`. Dejar un
  único tipo de vista por carpeta (hoy Media queda en Generic si la crea el
  importer y en Documents si la crea ProjectFolder). Detalle del lado de Mvsep en
  `features/mvsep_importer.md` §7.
- **Probar `RELINK`** y decidir si hace falta.
- **Cobertura**: pista master, FX de entrada y FX de items.
- **ReaPack**: decidir si `CollectSamples` y `FolderView` entran al paquete
  publicado de ProjectFolder, ya que la recolección solo tiene sentido en la PC
  de desarrollo. Ver `05_REAPACK_DEPLOY.md`.

## 8. Qué adjuntar según la tarea

| Tarea | Docs | Código |
|---|---|---|
| Abrir carpetas | `project_folder.md` | `ProjectFolder_common_logic.lua`, `ProjectFolder_config.lua` |
| Recolección de samples | `project_folder.md` | `Nik_ProjectFolder_CollectSamples.lua`, `_Shared/FolderView_common_logic.lua` |
| Empaquetado en lote | `project_folder.md`, `STEMS_ZIPPER.md` | `Stems Zipper.bat`, `ProjectFolder_common_logic.lua` |
| Migrar la vista de carpetas | `project_folder.md`, `mvsep_importer.md` | `_Shared/FolderView_common_logic.lua`, `MvsepImporter_common_logic.lua` |