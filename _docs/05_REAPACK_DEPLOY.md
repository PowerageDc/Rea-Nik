# Deploy vía ReaPack

Empaquetado y distribución de scripts a PCs sin git ni editor de código,
vía `reapack-index` generando el índice desde el mismo repo `Rea-Nik`. No
duplica convenciones de nomenclatura/estructura (`01_CONVENCIONES.md`) ni
setup de git (`04_GIT_TOOLING.md`). Los cambios en espera de deploy viven
en `DEPLOY_PENDIENTE.md` (ver "Deploy pendiente").

## Alcance y paquetes

Solo un subconjunto del repo se deploya. El resto de los dominios es uso
local y no necesita exclusión explícita: `reapack-index` solo indexa lo
que tiene header de metadata, y sin header no hay paquete. `_docs/` se
excluye siempre del escaneo (`.reapack-index.conf`).

| Paquete | Ancla | Notas |
|---|---|---|
| RemoteControl (scripts) | `RemoteControl/Nik_RemoteState_Poll.lua` | Metapaquete |
| MusicState (scripts) | `MusicState/Nik_MusicState_Helper.lua` | Metapaquete |
| MonitorMix (scripts) | `MonitorMix/Nik_MonitorMix_Publish.lua` | Metapaquete; consume `StemBus` de RemoteControl |
| Interfaz web (`.www`) | `web/Nik_RemoteControl_WebUI.www` | Sirve remoto, prompter, cantante y monitor |
| ProjectFolder (scripts) | `ProjectFolder/Nik_ProjectFolder_OpenRoot.lua` | Independiente: sin otros paquetes ni generador |
| AutoColor | `AutoColor/reaper_autocolor_live.lua` | Script suelto con header propio; fuera de `check_deploy.ps1` y de `DEPLOY_PENDIENTE.md` |

La versión publicada de cada paquete vive en el título de su sección de
`DEPLOY_PENDIENTE.md`; la fuente de verdad es el `index.xml`.

En destino se instalan juntos RemoteControl, MusicState, MonitorMix y el
`.www`, y después se corre `Nik_RemoteControl_GenerateConfig.lua` una
vez (ver "Mecanismo de config por PC").

## Prerrequisitos (solo PC de desarrollo; destino solo necesita ReaPack)

- **Ruby** (RubyInstaller) con el componente **MSYS2 development
  toolchain** — necesario para compilar `rugged`, dependencia nativa de
  `reapack-index`. ("RI and HTML documentation" no hace falta.)
- **`reapack-index`**: `gem install reapack-index`.
- **`pandoc`**: `winget install --id JohnMacFarlane.Pandoc`. Obligatorio:
  sin él, la conversión del `@about` (y del `@changelog`) a RTF falla y
  bloquea la indexación del paquete entero (no es un warning cosmético).

## Flujo de deploy

Se hace en una sesión dedicada, con este doc y `DEPLOY_PENDIENTE.md`
adjuntos.

1. **Punto de partida.** Parado en `main`, con las ramas de feature
   terminadas ya mergeadas y el árbol limpio. Las líneas de cada cambio
   ya están en `DEPLOY_PENDIENTE.md`.
2. **Chequeo.** `.\Tests-Debug\check_deploy.ps1` (ver "Verificación del
   alcance"). Resolver lo que marque: altas sin paquete (al `@provides`
   o a `$Locales`), `dofile` huérfanos, entradas del generador. Hacer a
   mano las comprobaciones que el script no cubre.
3. **Bump.** Por cada paquete en "BUMP NECESARIO": `@version` nuevo y
   `@changelog` armado desde su sección de la lista, ambos en el header
   del ancla. Un commit dedicado (`chore(deploy): <paquete> <versión>`).
4. **Re-chequeo.** `check_deploy.ps1` debe dar "listo para reindexar" en
   lo que se publica, sin avisos.
5. **Índice.** `reapack-index --rebuild`, revisar `index.xml`, `y` y push
   (ver "Generar y publicar el índice").
6. **Cierre de docs.** Commit aparte: títulos `publicado X.Y` en
   `DEPLOY_PENDIENTE.md` y lista vaciada.
7. **Destino.** En una PC de destino (nunca la de dev): Synchronize,
   instalar juntos lo que corresponda y correr el generador si el
   deploy tocó RemoteControl o el `.www`.

Si hace falta probar en destino antes de confirmar, los pasos 3 a 5 se
hacen en una rama temporal con squash (ver "Rama temporal + squash para
deploys iterativos").

## Cuándo bumpear

**Regla dura:** `reapack-index` versiona por el tag `@version` del
header, no por contenido ni por commit. Un cambio a un archivo ya
indexado solo llega a destino si el `@version` de su paquete sube antes
de indexar; sin bump, el `index.xml` sigue sirviendo la versión anterior
en silencio, sin error. "Synchronize packages" no lo reemplaza: ReaPack
solo baja archivos cuando el índice trae una versión nueva del paquete.

El bump es **uno por paquete, en un commit dedicado al deploy**, junto
con su `@changelog`. Mientras se desarrolla no se bumpea: en la PC de dev
los scripts corren desde `C:\dev\Rea-Nik\` y la `.www` por el junction,
sin ReaPack de por medio. Probar en una PC de destino sí exige bump, y
para eso se usa rama temporal.

Cada versión queda atada al commit donde aparece su `@version`: ese
commit publica el estado completo del paquete en ese momento, incluida
una feature a medias, y todo cambio posterior al paquete necesita otro
bump. Lo que no esté listo no se comitea en `main` (rama de feature o
sin comitear), o el bump espera.

Un header con bump todavía no indexado, si el archivo cambia después del
commit de ese bump (aunque sea para sumar el `@changelog`), se sube a
otro número: es lo más seguro, y como esa versión nunca llegó al índice,
el salto no deja rastro.

Lo que decide si hay bump es si el archivo figura en el `@provides` de
algún paquete:

| Cambio | Acción |
|---|---|
| Se modifica un archivo que está en un `@provides` | Bump del paquete que lo lista |
| Archivo nuevo en el dominio (script o `common_logic`), aunque no se lance desde el Action List | Línea en el `@provides` del ancla, al crearlo; bump en el deploy |
| Se renombra, mueve o borra un archivo del `@provides` | Ajustar el `@provides`; bump |
| `.html` nuevo en la raíz de `web/` | A mano en el `@provides` del `.www`; bump del `.www` |
| Archivo web nuevo cubierto por un wildcard | Bump del `.www` |
| Módulo de `_Shared/` | Bump del paquete que lo lista; los consumidores solo si cambió su propio código; anotar "instalar juntos" |
| UI web que dispara un script nuevo por Command ID | Entrada en `SCRIPTS` del generador y key en `config.js` (ver "Mecanismo de config por PC"); bump de RemoteControl y del `.www`; re-correr el generador en destino |
| Config en el `@provides` | Bump; avisar que pisa la edición local en destino |
| Archivo fuera de todo `@provides` (`_docs/`, `Tests-Debug/`, dominios de uso local, `config.local.js`) | Sin bump |
| Cambio cosmético en un archivo provisto | Sin bump obligatorio: viaja con el próximo |

## Deploy pendiente

Los cambios comiteados o en curso de los paquetes deployables, desde el
último deploy, viven en `_docs/DEPLOY_PENDIENTE.md`, aparte de este doc
(que es de referencia y no cambia con cada feature). Se comitea junto con
el cambio que describe y se vacía al publicar, sin historia (la historia
es git y el `@changelog`). No va en los archivos de proyecto de Claude:
es una foto que se desactualiza; se adjunta al deployar.

- Una sección por paquete, titulada `<paquete> — publicado X.Y`, y una
  línea por cambio, escrita al terminar el cambio, en lenguaje de
  usuario y no con el nombre del archivo tocado: `- A|M|D <qué cambió>`
  (`A` agregado, `M` modificado o corregido, `D` baja). Un refactor sin
  efecto visible también lleva línea ("Refactor interno de X"): es lo
  que permite verificar el diff.
- `→ acción` al final solo cuando hace falta algo que el diff no
  muestra: línea de `@provides`, entrada del generador, "instalar juntos
  con X", config que se pisa en destino.
- Un cambio que toca dos paquetes (Lua y `.www`) lleva una línea en cada
  sección.

Al deployar: las líneas de cada sección pasan al `@changelog` del ancla
de su paquete, se actualiza la versión del título y se vacía la sección,
dejando el título. El `@changelog` va en el header, junto al `@version`,
y se reemplaza en cada bump:

```lua
-- @version 1.8
-- @changelog
--   Agregado: atajos de teclado configurables en el Helper
--   Corregido: el prompter no sincronizaba al cambiar de tab
```

Mismas restricciones de header que `@about`: ninguna línea `--` vacía.

## Verificación del alcance

`Tests-Debug\check_deploy.ps1` (solo lectura) reemplaza el buceo con git
y grep. Por paquete compara el header de `HEAD` contra el `index.xml` y
lista los archivos provistos con `M`, `A` y `D` desde el commit de ese
paquete (el hash de las URLs de `<source>` de su versión más reciente,
con la forma `.../raw/<hash>/...`). Además detecta:

- altas en la carpeta del ancla que ningún `@provides` cubre; los
  archivos de uso local a propósito se declaran en `$Locales`, al inicio
  del script;
- cambios posteriores a un bump ya hecho;
- módulos cargados por `dofile` que no están en ningún `@provides`
  (solo ve rutas literales);
- `@changelog` faltante en una versión nueva;
- desfases contra `DEPLOY_PENDIENTE.md` (título distinto del índice,
  lista vacía con cambios, lista con líneas sin cambios).

Lee `HEAD`: se corre con todo comiteado y, para el bump final, parado en
`main` (avisa si no lo estás). Todo `A` o `D` debe figurar en la lista;
todo archivo provisto con `M` debe pertenecer a un cambio descrito.

Sin el script, por paquete: `git diff --name-status <hash>..HEAD`.
`A` = candidato a `@provides`; `M` = bump; `D` = sacar del `@provides`,
o `--ignore` si es legacy en el historial. Contra el hash de cada
paquete y no contra el más viejo, que marcaría como cambiado lo que
otro paquete ya publicó.

**Lo que el script no ve** (comprobar a mano):

1. **Dominios nuevos enteros.** Solo mira lo provisto y la carpeta del
   ancla; `git diff --stat <hash>..HEAD`, sin acotar carpeta, muestra
   lo que cayó fuera.
2. **Consumidores de un módulo compartido nuevo.** Grep amplio, nunca
   acotado a la carpeta "obvia". Caso real: un módulo de `_Shared/`
   resultó consumido también por el dispatcher de otro dominio ya
   deployado, y un grep acotado a la feature nueva no lo mostró:
   ```powershell
   git grep -n "<nombre_del_modulo_o_funcion>" -- "*.lua"
   git grep -n "<nombre_de_la_funcion_js>"
   ```
3. **Side-effects de una UI nueva.** Una UI que parece de solo lectura
   puede disparar un `commandId` al conectarse (one-shot de refresh):
   confirmarlo con el grep anterior antes de descartar que necesite
   entrada en el generador (`Nik_RemoteControl_GenerateConfig.lua`).
4. **Ruta en el generador.** Un módulo o script que no vive en
   `RemoteControl/` puede necesitar resolución de ruta distinta: no
   asumir que `script_dir .. entry.file` alcanza para todo.
5. **Gotchas de PowerShell.** Para excluir una carpeta con `_` en el
   nombre, usar `':(exclude)_docs'`: la forma corta `':!_docs'` falla
   con `Unimplemented pathspec magic '_'`. Escribir `git log -S "texto"`
   con espacio: pegado (`-S"texto"`) dio error de consola en este
   entorno.

## Anatomía de un paquete

Tres formas: script suelto, metapaquete de scripts y paquete `.www`
(interfaces web), más el mecanismo de config por PC que usa la `.www`.

Reglas de todo header (`@description`, `@version`, `@author`,
`@changelog`, `@about`): tiene que estar **comiteado** — `reapack-index`
escanea el historial de git, no el working directory — y no puede tener
ninguna línea `--` completamente vacía, ni dentro de `@about` o
`@changelog`: el parser la interpreta como fin del header y corta ahí
(si hace falta separación visual, poner contenido real en esa línea).
Un script suelto (ejemplo real: `AutoColor/reaper_autocolor_live.lua`)
lleva solo esos tags, sin `@metapackage` ni `@provides`.

### Metapaquete — varios scripts + módulos bajo una sola entrada

Usar cuando un dominio tiene varios scripts ejecutables que comparten
módulos `dofile` (caso `RemoteControl/`: todos sus ejecutables y módulos
`common_logic` en una sola entrada de ReaPack).

Un script "ancla" lleva el header con `@metapackage` + `@provides`
listando **todos** los archivos del grupo:

```lua
-- @description Nik RemoteControl — Suite completa (control remoto web)
-- @version 1.4
-- @author Nik
-- @changelog
--   Qué cambió en esta versión
-- @metapackage
-- @provides
--   [main] .
--   [main] OtroScript_1.lua
--   [main] OtroScript_2.lua
--   Modulo_common_logic.lua
--   ../_Shared/OtroModulo_common_logic.lua
```

- `[main]` en los ejecutables (se registran en Action List); sin tag en
  los módulos (solo se instalan como archivo, no como acción).
- **El ancla se lista a sí misma con `[main] .`** (primera línea del
  `@provides`). Con `@provides` explícito, sin esa línea ReaPack instala
  los demás archivos pero no el ancla, y no aparece en el Action List.
  Caso real: el Helper de MusicState.
- **Ningún otro script del grupo lleva header propio** — un archivo
  target solo puede pertenecer a un paquete. Vale también para un
  script nuevo creado dentro del dominio (un one-shot): alcanza con su
  línea `[main]` en el `@provides` del ancla. Nunca se comitea con
  header propio: con un solo commit que lo tenga, `reapack-index` lo
  registra como paquete suelto, y ese paquete sigue en el índice aunque
  el header se saque después (ver "Cuidado", abajo). Caso real:
  `Nik_MusicState_FocusHelper.lua`.
- **Dependencia de un módulo que ya es de otro paquete:** no se lista
  en el `@provides` (conflicto de target) y ReaPack no tiene
  declaración de dependencias entre paquetes. Se documenta en el
  `@about` y hay que instalar ambos juntos. Caso real: `MonitorMix/`
  consume `../_Shared/StemBus_common_logic.lua`, que provee el
  metapaquete de RemoteControl — en destino se instalan juntos, y las
  dos carpetas quedan hermanas bajo `Scripts/Rea-Nik/`, por lo que el
  `dofile` relativo funciona igual que en dev.

**Cuidado — `'X' conflicts with 'X'`:** `reapack-index` descarta esa
versión entera del índice (no aborta el rebuild completo, solo esa
entrada) en dos casos:

- *Migrar un script existente a un metapaquete:* sacarle el header
  propio tiene que ir **en el mismo commit** en que se agrega al
  `@provides` del ancla. Si el header se saca un commit después, o el
  `@provides` se agrega uno antes, aparece el conflicto.
- *Script legacy (pre-metapaquete) que sigue en el historial de git:*
  aparece como paquete suelto en el rebuild y, si además está en el
  `@provides` de un metapaquete, este pierde las versiones afectadas.
  `--rebuild` no lo resuelve (relee todo el historial); solo lo
  resuelve agregar el path a `.reapack-index.conf` (`--ignore <path>`,
  uno por línea; se comitea, es config del proceso de indexado).

No confundir con archivos de config local de cada PC
(`config.local.js`), que sí son gitignoreados.

### Paquete `.www` — interfaces web (`web/`)

Tipo separado, no efecto colateral de indexar los scripts Lua del mismo
dominio. El manifiesto necesita **extensión `.www`** (no `.html`):

```
-- @description Nombre de la interfaz
-- @author Nik
-- @version 1.0
-- @changelog
--   Qué cambió en esta versión
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
- Archivos generados por PC (ej. `config.local.js`) van **excluidos**
  del `@provides` y del repo (gitignore) — nunca deploy de esto vía
  ReaPack.
- Al instalar/actualizar, queda como **entrada separada** en el listado
  de ReaPack junto al metapaquete de scripts del mismo dominio — es
  esperado, no un bug. Tildar ambas casillas antes de dar Install para
  instalarlas juntas en un solo paso.
- **Un mismo manifiesto `.www` puede servir más de una feature** si
  conviven bajo el mismo `reaper_www_root/`. Caso real:
  `Nik_RemoteControl_WebUI.www` provee el control remoto y las UIs de
  MusicState (prompter, cantante, monitor y
  `musicstate-ui/*/*.{css,js}`): un solo `@version` y un solo bump
  cubren cambios en cualquiera de ellas. Los metapaquetes de
  **scripts** Lua son anclas separadas por dominio (ver la tabla de
  "Alcance y paquetes").
- **Cada `.html` de la raíz de `web/` se lista a mano en el
  `@provides`:** los patrones `musicstate-ui/*/*.{css,js}` cubren las
  subcarpetas, pero no una página nueva en la raíz. Caso real:
  `nsaudio_monitor.html` faltó en la primera pasada; hoy
  `check_deploy.ps1` lo marca como alta sin paquete.

### Mecanismo de config por PC (`config.local.js` + generador)

Cuando el JS de una interfaz `.www` necesita Command IDs que cambian por
PC (`_RS<hash>`, distinto según dónde ReaPack instaló los scripts en esa
máquina), un script del propio metapaquete resuelve los IDs reales vía
`AddRemoveReaScript` + `ReverseNamedCommandLookup` y escribe
`reaper_www_root/config.local.js` (ver `Nik_RemoteControl_GenerateConfig.lua`
como implementación de referencia).

- **No se autoejecuta.** Correrlo a mano desde el Action List una vez por
  PC, después de cada instalación o actualización del paquete.
- **Cada script que una UI web dispara por Command ID necesita su
  entrada en la tabla `SCRIPTS` del generador** (la `key` es la de
  `NIK_LUA_COMMANDS` en `config.js`; para scripts fuera de
  `RemoteControl/`, `dir` con la ruta relativa, ej. `../MusicState/`).
  Si falta, o si el generador no se volvió a correr tras actualizar, la
  UI usa el default de dev de `config.js` y el pedido falla en silencio
  en destino. Casos reales: `musicStatePublishLyrics` (UI de cantante),
  `monitorMixPublish` (UI de monitor, `dir = "../MonitorMix/"`) y
  `monitorMixPaRoute` (modo PA del remoto principal, mismo `dir`). El
  guard de `nikMusicStateRequestLyrics` solo avisa si la key falta del
  todo, no si trae un ID que no existe en esa PC.
- **El generador colapsa `..` antes de `AddRemoveReaScript`.** Con una
  ruta sin normalizar (`RemoteControl/../MusicState/archivo.lua`)
  REAPER la registra como una identidad distinta de la canónica con la
  que ReaPack instaló el archivo: dos entradas en el Action List con
  Command IDs distintos, y el `commandId` de `config.local.js` puede
  no ser el estable.
- El HTML/JS de la interfaz debe cargar `config.local.js` **después** de
  cualquier default hardcodeado, y cualquier valor derivado de esos IDs
  (strings compuestos, closures) debe recalcularse on-demand después de
  esa carga — no capturarlo en una variable al momento de definir el
  default, o queda con el valor viejo sin error visible.

## Generar y publicar el índice

Desde la raíz del repo, parado en `main` y con todo comiteado:

```powershell
reapack-index --rebuild
```

- `--rebuild` fuerza re-escaneo completo del historial; con
  `.reapack-index.conf` ya en el repo no hace falta repetir `--ignore` a
  mano.
- Al final pregunta `Commit the new index? [y/N]` — con `y` comitea
  `index.xml` solo (no hace falta `git add`/`commit` manual para ese
  archivo). Antes de responder, revisar el resultado (abrirlo con
  `code index.xml`: el mojibake de la consola no indica corrupción).
- Push manual después (`reapack-index` no pushea).

Qué revisar en `index.xml` por cada paquete bumpeado:

1. Existe la versión nueva.
2. El hash de las URLs de sus `<source>` es el del commit del bump
   (`git log --oneline -3`), no el del commit del índice.
3. La lista de archivos incluye las altas y no incluye los de uso local.
4. El `@changelog` aparece en esa versión.

Los paquetes sin bump no deben cambiar. Si el rebuild tira
`'X' conflicts with 'X'` en alguno, no pushear: ver "Cuidado" del
metapaquete.

## Rama temporal + squash para deploys iterativos

Cuando un deploy requiere varias iteraciones de prueba en destino real
(sala de ensayo, PC de test), no conviene iterar directo en `main`: cada
fix intermedio exige su propio bump de `@version` (ver "Cuándo
bumpear"), y esos bumps transitorios quedan como ruido permanente en el
`index.xml` de producción aunque el bug que los motivó ya no exista.

Patrón: rama temporal para toda la iteración, squash merge a `main` al
confirmar.

1. Crear rama, deployar ahí, iterar (fix → bump → rebuild → push →
   probar en destino) las veces que haga falta. La URL de import de la
   rama es la misma que la de `main` cambiando el segmento de rama
   (`.../raw/<rama>/index.xml`); como el índice referencia archivos por
   hash de commit, se descargan bien. En destino, reemplazar el repo de
   ReaPack por esa URL (no dejar los dos importados a la vez).
2. Al confirmar que funciona: `git checkout main`, luego
   `git merge --squash <rama>`.
3. Sacar el `index.xml` de la rama del stage: tras el squash es inválido
   (sus `<source>` apuntan a hashes de commit que el squash elimina) y
   se regenera fresco, no se arrastra:
   `git restore --staged index.xml && git checkout -- index.xml`.
4. Commit único en `main` describiendo el estado final (no el camino).
5. `reapack-index --rebuild` parado en `main`, sin reusar el índice de
   la rama.
6. Push, luego borrar la rama (local y remoto). Local con
   `git branch -D` (mayúscula): tras un squash git no reconoce la rama
   como mergeada y `-d` se niega. Después, en destino, volver el repo de
   ReaPack a la URL de `main`; si las versiones son las mismas que se
   probaron en la rama, ReaPack no reinstala nada, es lo esperado.

El `@version` vive en el header del archivo fuente, no en el mensaje de
commit ni en el `index.xml`: el squash trae los archivos con el valor
final y `--rebuild` lo lee en `HEAD` de `main`, así que el índice
coincide con el commit final, sin rastro de las versiones intermedias.

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
  bug, esperar unos minutos y reimportar el repo en ReaPack (puede ser
  cache de CDN de `raw.githubusercontent.com`). Si persiste varias horas,
  sospechar primero que el push no llegó o quedó en otra rama.
- **`Rugged::ConfigError: ... is not owned by current user`**: ver
  `04_GIT_TOOLING.md`, gotcha de `safe.directory`.
- **"missing tag 'version'"** al indexar: preexistente en todos los
  paquetes, no bloqueante, ignorar.
- Mover/renombrar un script con header no afecta a ReaPack, pero invalida
  su Command ID local en la PC de dev (ver `01_CONVENCIONES.md`).

## Pendientes

- Configs en código que ReaPack pisa en cada update: `MonitorMix_config.lua`
  (filtro de tracks), `MusicStateKeys_config.lua` (atajos del Helper, ver
  `features/musicstate_keys.md`), `MusicStateRoles_config.lua` (catálogo de
  roles, ver `features/musicstate_helper.md`) y `ProjectFolder_config.lua`
  (`render_default`) van en el `@provides` de su paquete, así que cualquier
  edición local en una PC de destino se pierde. Decidir si pasan a un
  archivo local aparte (estilo `config.local.js`, gitignoreado y fuera del
  `@provides`) o si se acepta reeditar tras cada update.
- Teclas de foco del Helper en destino (F4 y F5 se asignan a mano en cada PC;
  dependen de SWS o `js_ReaScriptAPI`): `features/musicstate_keys.md` §6.
- Alternativa a correr el generador de `config.local.js` a mano por PC, sin
  caer en "regenerar en cada arranque de REAPER" (Startup Actions de
  SWS/S&M funciona pero reescribe siempre). No bloqueante.
- Decidir si los `commandId` hardcodeados como fallback en `config.js`
  deben eliminarse (forzar error visible si falta `config.local.js`) o
  mantenerse con validación explícita — hoy, si falta el archivo
  generado, el sistema corre igual con el default de dev sin avisar.
