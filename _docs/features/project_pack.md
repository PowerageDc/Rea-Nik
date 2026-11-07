# ProjectPack

Acción de menú contextual de Windows que comprime con clave (WinRAR) las
carpetas de proyecto de REAPER, para subirlas a la carpeta de Drive compartida
que consume ReapFetch (documentado en el repo de ese proyecto). No es parte del
stack de ReapFetch: es la herramienta previa e independiente, en la punta
contraria del mismo flujo. ReapFetch resuelve la descarga y apertura; ProjectPack,
la preparación y subida del lado de quien comparte.

No son scripts de REAPER (son `.bat`, `.vbs` y `.reg`), por eso no siguen la
convención `Nik_<Dominio>_<Acción>`.

## 1. Flujo de uso

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
   ajustar `set "WINRAR=..."` en el `.bat`.
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

## 4. Decisiones y gotchas

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
- **Clave fuera del repo**: aunque el repo es privado, se trata como público.
- **ReaPack no indexa `ProjectPack/`**: es una herramienta de la PC de desarrollo y
  no se distribuye a las salas.

## 5. Diagnóstico abierto: `desktop.ini` pierde atributos

Los `desktop.ini` llegan al zip con el atributo de archivo pero sin oculto y
sistema. No es un problema de compresión: uno comprimido con este `.bat` y
descomprimido con el propio WinRAR conserva los atributos. El problema está del lado
de la extracción, a revisar en `extract_zip` y el crate `zip` de Rust en ReapFetch
(documentación de arquitectura en el repo de ese proyecto). En la sala, la carpeta 
`Samples` pierde la vista Documentos por lo mismo. Alternativa simple: excluir 
`desktop.ini` con `-x`.

## 6. Pendientes

- **Empaquetado en lote desde REAPER** (`Nik_ProjectPack_*.lua`): recorrer las
  pestañas, correr la recolección de samples y zipear cada proyecto sin su carpeta de
  render. No puede pasar por la cola del `.bat`, que fusionaría todos los proyectos
  en un solo zip: Lua llamaría a WinRAR directo, uno por proyecto, leyendo
  `ProjectPack.key`. A definir: guardar o saltear pestañas con cambios; la carpeta de
  render se deriva de `RENDER_FILE` de cada proyecto con la lógica de ProjectFolder
  (hoy local en `ProjectFolder_common_logic.lua`; habría que moverla a `_Shared/`),
  más una lista de exclusiones en `ProjectPack_config.lua`; evaluar excluir los
  `.reapeaks` y backups.
- **Aviso por samples fuera del proyecto**: antes de zipear, detectar en el `.rpp`
  rutas absolutas de samples fuera de la carpeta del proyecto.
- **Decidir qué hacer con `desktop.ini`**: excluirlo con `-x` o preservar sus
  atributos en la extracción de ReapFetch.
- **Recuperación automática del lock** colgado por un corte abrupto (hoy expira solo
  tras unos 10 s en la siguiente corrida).
- **Desacoplar del preset `RPPStems`**: antes de reintentar `-afzip`, confirmar si el
  preset tiene activada la ejecución inmediata.
- **Clave visible en la lista de procesos** mientras corre WinRAR. Se acepta para este
  uso.

## 7. Qué adjuntar según la tarea

| Tarea | Docs | Código |
|---|---|---|
| Menú contextual, cola, nombre del zip, clave | `project_pack.md` | `ProjectPack/*` |
| Empaquetado en lote | `project_pack.md`, `project_folder.md` | `ProjectPack/*`, `ProjectFolder_common_logic.lua` |