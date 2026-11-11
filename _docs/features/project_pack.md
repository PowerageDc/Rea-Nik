# ProjectPack

Comprime con clave (WinRAR) las carpetas de proyecto de REAPER, para subirlas a la
carpeta de Drive compartida que consume ReapFetch (documentado en el repo de ese
proyecto). No es parte del stack de ReapFetch: es la herramienta previa e
independiente, en la punta contraria del mismo flujo. ReapFetch resuelve la descarga
y apertura; ProjectPack, la preparación y subida del lado de quien comparte.

Tiene dos entradas: una acción de REAPER que empaqueta en lote las pestañas abiertas
(`Nik_ProjectPack_PackTabs.lua`, §4) y una acción de menú contextual de Windows para
una selección del Explorador. El menú contextual (`.bat`, `.vbs` y `.reg`) no son
scripts de REAPER, por eso no siguen la convención `Nik_<Dominio>_<Acción>`.

## 1. Flujo de uso

**Desde REAPER:** correr `Nik_ProjectPack_PackTabs.lua` con las pestañas del día
abiertas (detalle en §4).

**Desde el Explorador**, para una carpeta o una selección:

1. Con las pestañas del día abiertas, correr la recolección de samples (ver
   `features/project_folder.md` §4) y revisar que la consola no muestre `DIFF` ni
   archivos inexistentes.
2. Click derecho sobre la carpeta de un proyecto → **"Project zip with password"**
   → genera un `.zip` con clave en Descargas, con el nombre de la carpeta.
3. Para dejar afuera la carpeta de render: entrar a la carpeta del proyecto,
   seleccionar todo menos esa carpeta y usar la misma acción. Sale un único `.zip`
   con el nombre de la carpeta contenedora, con subcarpetas incluidas.
4. Si el `.zip` ya existe se borra y se regenera: cada ejecución deja una foto
   completa y actual, nunca un merge sobre un zip viejo.
5. No se ve ventana de consola.

## 2. Archivos

| Archivo (en `ProjectPack/`) | Rol |
|---|---|
| `ProjectPack.bat` | Toda la lógica: cola y lock de invocaciones, nombre del zip, llamada a WinRAR. |
| `ProjectPack_Hidden.vbs` | Relay: reenvía los argumentos al `.bat` y oculta la consola. Lo busca en su propia carpeta. |
| `ProjectPack_ContextMenu.reg` | Registra la acción en `HKCU\Software\Classes\AllFilesystemObjects\shell\ProjectPackZip`. Borra antes las claves viejas (`StemsZipWithPassword` bajo `*`, `Directory` y `AllFilesystemObjects`, y la nueva). |
| `ProjectPack_config.lua` | Valores editables del lote: clave, WinRAR, perfil, destino, exclusiones y espera máxima. |
| `ProjectPack_common_logic.lua` | Lote: chequeos previos, destino, plan de proyectos y zipeo asíncrono con validación. |
| `Nik_ProjectPack_PackTabs.lua` | Acción de REAPER: orquesta el lote sobre las pestañas abiertas. |
| `Tests-Debug/Nik_ProjectPack_Probe*.lua` | Sondas de rutas, del plan, del zipeo de la pestaña activa y del lanzamiento sin bloqueo. |

La clave del zip no está en el repo: vive en `C:\Scripts\ProjectPack.key`, junto
al `.bat` instalado. El `.bat` la lee al arrancar, antes de encolar y de tomar el
lock; si falta, sale sin hacer nada.

## 3. Instalación en una PC nueva

1. Crear `C:\Scripts\` y copiar ahí `ProjectPack.bat` y `ProjectPack_Hidden.vbs`
   (el `.reg` apunta a esa ruta).
2. Crear `C:\Scripts\ProjectPack.key` con la clave, sin salto de línea ni
   espacios finales y sin comillas dobles ni `!`. Con PowerShell:
   `[IO.File]::WriteAllText('C:\Scripts\ProjectPack.key', 'LA_CLAVE')`.
3. Verificar WinRAR en `C:\Program Files\WinRAR\WinRAR.exe`. Si está en otra ruta,
   ajustar `set "WINRAR=..."` en el `.bat` y `winrar` en `ProjectPack_config.lua`.
4. Crear en WinRAR (GUI) un perfil de compresión llamado `RPPStems`, que el `.bat`
   invoca con `-cpRPPStems`. Es un paso manual por PC.
5. Importar el `.reg` con doble click.
6. Probar con una carpeta sola y después con una selección mixta (archivos y
   subcarpetas). Probar también sin `ProjectPack.key`: no debe hacer nada ni dejar
   el lock.

Además, el destino de los `.zip` se resuelve en cada ejecución desde el GUID de
Descargas del usuario logueado. Conviene confirmar que sea la carpeta deseada.

## 3.1 Cambio de nombre

El zipper se llamaba Stems Zipper, con archivos y clave de registro con ese
nombre. En una PC con la versión vieja, al importar el `.reg` nuevo se borra la
entrada vieja; después se pueden borrar `Stems Zipper.bat` y
`Stems Zipper Hidden.vbs` de `C:\Scripts\`.

## 4. Empaquetado en lote desde REAPER

`Nik_ProjectPack_PackTabs.lua` empaqueta cada proyecto guardado de las pestañas
abiertas. Flujo:

1. Chequeos previos: la clave (`key_file`, la misma de §2), WinRAR y el destino.
2. Plan: una entrada por pestaña guardada. Se omiten las sin guardar, el mismo `.rpp`
   en otra pestaña, una carpeta de proyecto repetida y un destino dentro del proyecto.
3. Si hay proyectos con cambios sin guardar: Sí los guarda, No empaqueta lo que hay
   en disco, Cancelar aborta.
4. Recolección de samples de cada proyecto (`features/project_folder.md` §4).
5. Confirmación con el resumen: proyectos, destino, notas, avisos de samples y
   pestañas omitidas.
6. Zipeo asíncrono.

- **Zip:** uno por proyecto, con el nombre de su carpeta y el contenido en la raíz,
  con el formato del perfil `RPPStems`. Se genera como `<nombre>.tmp.zip`, se valida
  y solo entonces reemplaza al `.zip` anterior; si falla, el anterior queda intacto.
- **Validación:** cantidad de archivos y suma de bytes del zip contra los esperados
  en disco, calculados con las mismas exclusiones. Un código de salida de WinRAR
  distinto de 0 también falla el proyecto. El mensaje lista algunos faltantes (con
  acentos pueden ser falsos positivos).
- **Exclusiones:** `exclude_files` (patrones de nombre, en cualquier subcarpeta) y
  `exclude_dirs` (nombre o ruta relativa al proyecto, literal, en la raíz o en 
  cualquier nivel). A las carpetas se suman siempre `render_default`
  (`ProjectFolder_config.lua`) y la carpeta de render configurada en el proyecto si
  está dentro de él (`features/project_folder.md` §3); un render configurado fuera
  del proyecto no excluye nada, pero la carpeta por defecto sí. Las reglas van a
  WinRAR como `-x` e incluyen la entrada de carpeta, para que no quede vacía en el
  zip. Los `.reapeaks` entran.
- **Destino:** `dest_dir`; vacío es Descargas del usuario (`shell:Downloads`).
- **Ejecución:** un solo script de PowerShell, lanzado oculto sin esperar
  (`FolderView.start_powershell`), procesa los proyectos en secuencia y escribe
  `START`, `OK`, `FAIL` y `END` en `%TEMP%\ProjectPack_run.log`. Un `reaper.defer`
  lee el log una vez por segundo y se detiene al recibir `END`, ante un error, si
  PowerShell no responde en 30 s o al superar `max_wait_s`. Un flag en `ExtState`
  impide dos empaquetados a la vez, y el script lo chequea antes de preguntar nada.
  La línea de comandos de Windows admite unos 20 proyectos por lanzamiento; si no
  entra, se avisa.

## 5. Decisiones y gotchas

**Menú contextual:**

- **Multiselección**: Explorer agrupa la selección por tipo y dispara el comando una
  vez por grupo (archivos y carpetas), incluso con `MultiSelectModel=Player`, que
  solo consolida dentro de cada grupo. Cada invocación encola sus ítems en
  `%TEMP%\ProjectPack\queue.txt` y compite por un lock atómico (`mkdir`). La que
  gana espera cerca de 1 s a las hermanas, lee la cola completa y arma un único zip.
  Si el lock queda tomado más de unos 10 s se asume huérfano y se limpia.
- **`-r`** en la llamada a WinRAR fuerza la recursión de subcarpetas. Sin él, al
  mezclar archivos y carpetas no recursaba.
- **Formato por preset**: el `.zip` sale del perfil `RPPStems`. Reemplazarlo por el
  switch `-afzip` reprodujo un bug de dos zips separados. La sospecha principal es la
  opción de ejecución inmediata del preset.
- **UTF-8 (`chcp 65001`)**: la cola pasa por un archivo de texto y el codepage OEM
  corrompe caracteres como el guion largo o las comillas tipográficas. La selección
  única viaja en variables de `cmd` y no tiene ese problema.
- **Nombre del zip**: con un solo ítem, el suyo (si es carpeta, completo; si es
  archivo, sin la extensión); con varios, el de la carpeta padre del primero. Se
  distingue porque `cmd` corta por el último punto y truncaría "Artista ft. Otro".
- **Expansión retardada**: toda la construcción de rutas la usa, para que `&`,
  espacios y acentos no se interpreten como comandos.

**Todo ProjectPack:**

- **Clave fuera del repo**: aunque el repo es privado, se trata como público.
- **ReaPack no indexa `ProjectPack/`**: es una herramienta de la PC de desarrollo y
  no se distribuye a las salas.
- **La clave viaja en la línea de comandos de WinRAR** y se ve en la lista de
  procesos mientras corre. Se acepta para este uso.
- **`desktop.ini` no se excluye del zip.** Llega con sus atributos (comprimido con
  el `.bat` y extraído con WinRAR los conserva); al extraer con ReapFetch se pierden,
  así que en la sala el archivo queda visible y `Samples` sin la vista Documentos.
  Se acepta así.

## 6. Pendientes

- **Menú contextual: archivos que quedan fuera del zip.** A veces falta alguno (por
  ejemplo el `.rpp`); no se logró reproducir. Sospecha: una invocación hermana que
  llega después de que la ganadora leyó la cola. El lote valida cantidad y bytes; el
  `.bat` no.
- **Aviso por samples fuera del proyecto** en el menú contextual, que no corre la
  recolección: detectar en el `.rpp` rutas absolutas fuera de la carpeta del proyecto.
- **Atributos de `desktop.ini` al extraer**, del lado de ReapFetch (`extract_zip` y
  el crate `zip` de Rust).
- **Recuperación automática del lock** colgado por un corte abrupto del menú
  contextual (hoy expira solo tras unos 10 s en la siguiente corrida).
- **Desacoplar del preset `RPPStems`**: antes de reintentar `-afzip`, confirmar si el
  preset tiene activada la ejecución inmediata.
- **Parpadeo de una ventana** al lanzar el lote; se evitaría lanzando PowerShell
  desde un `.vbs` oculto.

## 7. Qué adjuntar según la tarea

| Tarea | Docs | Código |
|---|---|---|
| Menú contextual, cola, nombre del zip, clave | `project_pack.md` | `ProjectPack/*` |
| Empaquetado en lote | `project_pack.md`, `project_folder.md` | `ProjectPack/*`, `_Shared/ProjectPaths_common_logic.lua`, `_Shared/ProjectSamples_common_logic.lua`, `_Shared/FolderView_common_logic.lua` |