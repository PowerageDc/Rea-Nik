# Deploy vía ReaPack

Empaquetado y distribución de scripts a PCs sin git ni editor de código,
vía `reapack-index` generando el índice desde el mismo repo `Rea-Nik`. No
duplica convenciones de nomenclatura/estructura (`01_CONVENCIONES.md`) ni
setup de git (`04_GIT_TOOLING.md`).

## Alcance: qué se deploya y qué no

Solo un subconjunto del repo: hoy, `AutoColor/` (script suelto) y
`RemoteControl/` (metapaquete + `.www`, ver abajo). El resto
(`RenderWorkflow/`, `TempoTools/`, `MvsepImporter/`, `StemFragment/`,
`Tests-Debug/`) es uso local: no necesita exclusión explícita, porque
`reapack-index` solo indexa lo que tiene header de metadata — sin header,
no hay paquete, sin tener que listarlo en ningún lado.

`_docs/` se excluye siempre del escaneo (ver `.reapack-index.conf` más
abajo) — no tiene sentido como paquete.

## Prerrequisitos (solo PC de desarrollo; destino solo necesita ReaPack)

- **Ruby** (RubyInstaller) con el componente **MSYS2 development
  toolchain** — necesario para compilar `rugged`, dependencia nativa de
  `reapack-index`. ("RI and HTML documentation" no hace falta.)
- **`reapack-index`**: `gem install reapack-index`.
- **`pandoc`**: `winget install --id JohnMacFarlane.Pandoc`. Obligatorio:
  sin él, la conversión del `@about` a RTF falla y bloquea la indexación
  del paquete entero (no es un warning cosmético).

## Header de metadata — script individual

```lua
-- @description Nombre corto / descripción visible en ReaPack
-- @version 1.0
-- @author Nik
-- @about
--   Descripción más larga, puede tener varios párrafos.
--   No dejar una línea `--` completamente vacía en ningún punto del
--   header (ni dentro de `@about`) — el parser la interpreta como fin
--   del header y corta ahí. Si hace falta separación visual, poner
--   contenido real en esa línea.
```

El header tiene que estar **comiteado** — `reapack-index` escanea el
historial de git, no el working directory.

Ejemplo real: `AutoColor/reaper_autocolor_live.lua`.

## Metapaquete — varios scripts + módulos bajo una sola entrada

Usar cuando un dominio tiene varios scripts ejecutables que comparten
módulos `dofile` (caso `RemoteControl/`, hoy con 13 ejecutables + 5
módulos `common_logic` en una sola entrada de ReaPack).

Un script "ancla" lleva el header con `@metapackage` + `@provides`
listando **todos** los archivos del grupo:

```lua
-- @description Nik RemoteControl — Suite completa (control remoto web)
-- @version 1.4
-- @author Nik
-- @metapackage
-- @provides
--   [main] OtroScript_1.lua
--   [main] OtroScript_2.lua
--   Modulo_common_logic.lua
--   ../_Shared/OtroModulo_common_logic.lua
```

- `[main]` en los ejecutables (se registran en Action List); sin tag en
  los módulos (solo se instalan como archivo, no como acción).
- **Ningún otro script del grupo lleva header propio** — un archivo target
  solo puede pertenecer a un paquete.

**Cuidado — migrar un script existente a un metapaquete:** sacarle el
header propio tiene que ir **en el mismo commit** en que se agrega al
`@provides` del ancla. Si el header se saca un commit después, o el
`@provides` se agrega uno antes, `reapack-index` tira
`'X' conflicts with 'X'` y descarta esa versión entera del índice (no
aborta el rebuild completo, solo esa entrada).

**Cuidado — scripts legacy que quedan fuera del índice pero siguen en el
historial de git:** si un path viejo (pre-metapaquete) sigue apareciendo
como paquete suelto en el rebuild, agregarlo a `.reapack-index.conf`
(`--ignore <path>`, uno por línea) — se comitea, es config del proceso de
indexado. No confundir con archivos de config local de cada PC
(`config.local.js`), que sí son gitignoreados.

## Paquete `.www` — interfaces web (`web/`)

Tipo separado, no efecto colateral de indexar los scripts Lua del mismo
dominio. El manifiesto necesita **extensión `.www`** (no `.html`):

```
-- @description Nombre de la interfaz
-- @author Nik
-- @version 1.0
-- @provides
--   config.js
--   nombre_interfaz.html
--   styles.css
--   core/*.js
--   modals/*/*.{html,js}
```

- Wildcards y subcarpetas soportados en `@provides` — no listar archivo
  por archivo si un patrón cubre la carpeta entera.
- **ReaPack resuelve solo contra `reaper_www_root/` en destino**,
  preservando la estructura de subcarpetas del `@provides` — no hace
  falta redirección (`Original > Target`) ni junction en la PC de
  destino (el junction de dev es solo porque el repo de dev vive fuera
  de `%APPDATA%\REAPER`, ver `00_CONTEXTO_GENERAL.md`).
- Archivos generados por PC (ej. `config.local.js`) van **excluidos** del
  `@provides` y del repo (gitignore) — nunca deploy de esto vía ReaPack.
- Al instalar/actualizar, queda como **entrada separada** en el listado
  de ReaPack junto al metapaquete de scripts del mismo dominio — es
  esperado, no un bug. Tildar ambas casillas antes de dar Install para
  instalarlas juntas en un solo paso.

## Mecanismo de config por PC (`config.local.js` + generador)

Cuando el JS de una interfaz `.www` necesita Command IDs que cambian por
PC (`_RS<hash>`, distinto según dónde ReaPack instaló los scripts en esa
máquina), un script del propio metapaquete resuelve los IDs reales vía
`AddRemoveReaScript` + `ReverseNamedCommandLookup` y escribe
`reaper_www_root/config.local.js` (ver `Nik_RemoteControl_GenerateConfig.lua`
como implementación de referencia).

- **No se autoejecuta.** Correrlo a mano desde el Action List una vez por
  PC, después de cada instalación o actualización del paquete.
- El HTML/JS de la interfaz debe cargar `config.local.js` **después** de
  cualquier default hardcodeado, y cualquier valor derivado de esos IDs
  (strings compuestos, closures) debe recalcularse on-demand después de
  esa carga — no capturarlo en una variable al momento de definir el
  default, o queda con el valor viejo sin error visible.
- Pendiente abierto (no bloqueante): buscar alternativa a correr esto
  manualmente sin caer en "regenerar en cada arranque de REAPER"
  (Startup Actions de SWS/S&M funciona pero reescribe siempre).

## Generar y publicar el índice

Desde la raíz del repo:

```powershell
reapack-index --rebuild
```

- `--rebuild` fuerza re-escaneo completo del historial; con
  `.reapack-index.conf` ya en el repo no hace falta repetir `--ignore` a
  mano.
- Al final pregunta `Commit the new index? [y/N]` — con `y` comitea
  `index.xml` solo (no hace falta `git add`/`commit` manual para ese
  archivo).
- Push manual después (`reapack-index` no pushea).

**Regla dura, sin excepción:** `reapack-index` versiona por el tag
`@version` del header, no por contenido ni por commit. **Cualquier
cambio a un archivo ya indexado exige bump de `@version` en el mismo
commit** — sin esto, el `index.xml` sigue sirviendo la versión anterior
en silencio, sin error.

**Squash merge de una rama de deploy a `main`:** el `index.xml` de la
rama queda inválido después del squash (sus `<source>` apuntan a hashes
de commit que el squash elimina). Correr `reapack-index --rebuild` **de
nuevo, parado en `main`** — no reusar el `index.xml` de la rama — y
comitear ese resultado ahí.

## Import en una PC de destino

`Extensions > ReaPack > Import a repository`, URL:

```
https://github.com/PowerageDc/Rea-Nik/raw/main/index.xml
```

Repo público (`raw.githubusercontent.com` no soporta auth de repo
privado). Sin datos sensibles en el repo, no hay problema.

`Browse packages` → tildar lo necesario → instalar. Confirmar
auto-registro en Action List (scripts) y/o aparición en
`reaper_www_root` (interfaces web).

**No instalar vía ReaPack en la PC de desarrollo** — generaría una copia
duplicada en `Scripts/Rea-Nik/...`, separada de la que se edita en
`C:\dev\Rea-Nik\...`. Probar siempre en una PC de destino real.

## Cuidados generales (rápidos, no bloqueantes salvo que se dé el caso)

- **`index.xml` desactualizado tras un push reciente:** antes de asumir
  bug, esperar unos minutos y reimportar el repo en ReaPack — puede ser
  cache de CDN de `raw.githubusercontent.com`, se resuelve solo con
  tiempo. Si seguís viendo esto sistemáticamente varias horas después
  (no minutos), sospechar primero que el push no llegó a hacerse o
  quedó en otra rama, antes que cache.
- **`Rugged::ConfigError: ... is not owned by current user`**: ver
  `04_GIT_TOOLING.md`, gotcha de `safe.directory`.
- **Mojibake en `cat index.xml` desde PowerShell**: casi siempre es la
  consola (codepage), no el archivo — confirmar abriendo con
  `code index.xml` antes de asumir corrupción.
- **"missing tag 'version'"** al indexar: preexistente en todos los
  paquetes, no bloqueante, ignorar.
- Mover/renombrar un script después de generarle header no afecta a
  ReaPack, pero sí invalida su Command ID local si ya estaba registrado
  en el Action List de la PC de dev (gotcha de siempre, ver
  `01_CONVENCIONES.md`).
- **Command ID duplicado en Action List para el mismo script:** si
  `Nik_RemoteControl_GenerateConfig.lua` resuelve la ruta de un script
  que vive fuera de `RemoteControl/` concatenando un `dir` con `..` sin
  normalizar (ej. `RemoteControl/../MusicState/archivo.lua`), REAPER
  registra esa ruta como una identidad distinta a la ruta canónica con
  la que ReaPack ya había instalado el mismo archivo — resultado: dos
  entradas en Action List para el mismo script, con Command IDs
  distintos, y el `commandId` que termina en `config.local.js` puede no
  ser el estable. El generador debe colapsar `..` antes de llamar a
  `AddRemoveReaScript`.

## Rama temporal + squash para deploys iterativos

Cuando un deploy requiere varias iteraciones de prueba en destino real
(sala de ensayo, PC de test) antes de confirmar que todo funciona, no
conviene iterar directo en `main` — cada fix intermedio exige su propio
bump de `@version` (regla dura, ver más abajo), y esos bumps transitorios
quedan como ruido permanente en el `index.xml` de producción aunque el
bug que los motivó ya no exista.

Patrón: rama temporal para toda la iteración, squash merge a `main` al
confirmar.

1. Crear rama, deployar ahí, iterar (fix → bump → rebuild → push → probar
   en destino) las veces que haga falta.
2. Al confirmar que funciona: `git checkout main`, luego
   `git merge --squash <rama>`.
3. Sacar el `index.xml` de la rama del stage — se regenera fresco después,
   no se arrastra: `git restore --staged index.xml && git checkout --
   index.xml`.
4. Commit único en `main` describiendo el estado final (no el camino).
5. `reapack-index --rebuild` parado en `main`.
6. Push, luego borrar la rama (local y remoto).

Por qué esto no genera inconsistencia entre el commit final y las
versiones que terminan en el índice: el número de `@version` vive en el
header del archivo fuente, no en el mensaje de commit ni en el
`index.xml`. El squash trae los archivos con el valor de versión que
tengan en ese momento (el final, tras todas las iteraciones) — no
resetea nada. `reapack-index --rebuild` lee esos headers en `HEAD` de
`main`, así que el índice resultante coincide exactamente con el commit
final, sin rastro de las versiones intermedias que solo existieron en la
rama descartada.

## Auditar alcance de un deploy sin doc confiable

Cuando la documentación de una feature no refleja todos los cambios
(desarrollo por avance, doc progresiva sin consolidar), no alcanza con
pedir un listado de carpetas — no distingue qué cambió desde el último
deploy ni quién depende de qué. La fuente confiable es git, contra el
commit del último deploy publicado (visible en el propio `index.xml`,
campo `commit` de la versión más reciente de cada paquete afectado).

1. **Diff sin acotar carpeta, primero.** Acotar de entrada a las
   carpetas "esperadas" puede esconder un dominio nuevo entero:
```powershell
   git diff --stat <commit_ultimo_deploy>..HEAD
```
2. **`--name-status` para separar altas/bajas/modificaciones:**
```powershell
   git diff --name-status <commit_ultimo_deploy>..HEAD
```
   `A` = candidato a nuevo `@provides` o paquete nuevo. `M` = ya
   indexado, solo necesita bump de `@version`. `D` = sacar del
   `@provides` si estaba, o `--ignore` si es legacy en el historial.
3. **Grep amplio para encontrar consumidores reales de un módulo
   compartido nuevo — nunca acotar el grep a la carpeta "obvia".**
   Caso real: un módulo en `_Shared/` resultó consumido también por el
   dispatcher de otro dominio ya deployado, no solo por la feature
   nueva — un grep acotado a la carpeta de la feature nueva no lo
   mostró; ampliar a la raíz del repo sí:
```powershell
   git grep -n "<nombre_del_modulo_o_funcion>" -- "*.lua"
   git grep -n "<nombre_de_la_funcion_js>"
```
4. **No asumir "solo consumo" en una UI nueva sin comprobar side-effects.**
   Una UI que parece de solo lectura puede disparar un `commandId` al
   conectarse (one-shot de refresh) — confirmar con el grep del punto 3
   antes de descartar que necesite entrada en el generador de config
   (`Nik_RemoteControl_GenerateConfig.lua`).
5. **Un módulo compartido nuevo puede necesitar resolución de ruta
   distinta en el generador de config** si el script que lo consume no
   vive en la misma carpeta que el generador (`RemoteControl/`) — no
   asumir que `script_dir .. entry.file` alcanza para todo.

## Pendientes

- Alternativa a correr el generador de `config.local.js` a mano por PC
  (ver sección de mecanismo arriba).
- Decidir si los `commandId` hardcodeados como fallback en `config.js`
  deben eliminarse (forzar error visible si falta `config.local.js`) o
  mantenerse con validación explícita — hoy, si falta el archivo
  generado, el sistema corre igual con el default de dev sin avisar.
