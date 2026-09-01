# Deploy vía ReaPack

Documenta el empaquetado y distribución de scripts a PCs de ensayo (sin
git ni editor de código instalado) usando ReaPack, con `reapack-index`
generando el índice desde el mismo repo `reaper-nik` versionado en
`04_GIT_TOOLING.md`. No duplica convenciones de nomenclatura ni estructura
de carpetas (ver `01_CONVENCIONES.md`).

## Alcance: qué se deploya y qué no

Solo se deploya un subconjunto de `Scripts/Custom/`: hoy, `AutoColor/` y
`RemoteControl/`. El resto (`RenderWorkflow/`, `TempoTools/`,
`MvsepImporter/`, `StemFragment/`, `Tests-Debug/`) es uso local únicamente
y **no necesita exclusión explícita**: `reapack-index` solo indexa
archivos que tienen el header de metadata al principio (ver abajo) — un
script sin header simplemente no se convierte en paquete, sin tener que
listarlo en ningún lado.

La carpeta `_docs/` (los `.md` de este proyecto) se excluye del escaneo
con la flag `--ignore _docs`, para que `reapack-index` ni siquiera la
revise (no tiene sentido como paquete y evita ruido/validaciones sobre
archivos que no son código).

## Prerrequisitos (solo en la PC de desarrollo — las PCs de destino no
necesitan nada de esto, solo ReaPack, que ya viene con REAPER)

- **Ruby**, instalado con RubyInstaller, incluyendo el componente **MSYS2
  development toolchain** (necesario para compilar `rugged`, dependencia
  de `reapack-index` con extensión nativa en C). El componente "RI and
  HTML documentation" no hace falta — es solo documentación de Ruby.
- **`reapack-index`**: `gem install reapack-index`.
- **`pandoc`**: `winget install --id JohnMacFarlane.Pandoc` (o instalador
  en pandoc.org). **Obligatorio, no opcional** — sin él, la conversión
  del `@about` a RTF falla y bloquea la indexación del paquete entero
  (no es solo un warning cosmético, a pesar de cómo se ve el mensaje).

## Header de metadata

Cada script a deployar necesita este bloque al principio del archivo,
antes del código:

```lua
-- @description Nombre corto / descripción visible en ReaPack
-- @version 1.0
-- @author Nik
-- @about
--   Descripción más larga, puede tener varios párrafos.
--   Para separar párrafos, no dejar una línea `--` completamente vacía
--   (el parser la interpreta como fin del header) — si hace falta
--   separación visual, usar contenido real en esa línea.
```

Reglas duras:
- No puede haber líneas vacías en ningún punto del header (ni siquiera
  `--` sin contenido después, dentro de un bloque multilínea como
  `@about`) — corta el parseo ahí mismo.
- El header tiene que estar comiteado en git para que `reapack-index` lo
  vea (escanea el historial de commits, no el working directory).

Ejemplo real aplicado: `Scripts/Custom/AutoColor/reaper_autocolor_live.lua`.

## Generar y publicar el índice

Desde la raíz del repo (`%APPDATA%\REAPER`):

```powershell
reapack-index --rebuild --ignore _docs -n "reaper-nik"
```

- `-n "reaper-nik"` solo hace falta en la primera corrida (fija el nombre
  del repo mostrado en ReaPack).
- `--rebuild` fuerza un re-escaneo completo; en corridas normales alcanza
  con `reapack-index --ignore _docs`.
- Al final pregunta `Commit the new index? [y/N]` — confirmando con `y`,
  `reapack-index` comitea el `index.xml` por su cuenta (no hace falta
  `git add`/`git commit` manual para ese archivo puntual).

Después, push manual (`reapack-index` no pushea):

```powershell
git push
```

## Import en una PC de destino

`Extensions > ReaPack > Import a repository`, con la URL:

```
https://github.com/<usuario>/reaper-nik/raw/main/index.xml
```

Repo tiene que ser **público** — `raw.githubusercontent.com` no soporta
la autenticación que necesitaría un repo privado, y ReaPack no tiene UI
para eso. Sin datos sensibles en el repo, no hay problema de exponerlo
(no queda listado en ningún directorio público de ReaPack salvo
submission manual, que no se hizo).

`Browse packages` → instalar. Si el script queda auto-registrado en el
Action List sin tocar nada más, el circuito funcionó completo.

**No instalar vía ReaPack en la PC de desarrollo** — generaría una copia
duplicada del script en otra ruta (`Scripts/reaper-nik/...`), separada de
la que se edita y versiona en `Scripts/Custom/...`. El import se prueba
en una PC de destino real (o una PC de ensayo), nunca sobre la de dev.

## Gotchas conocidos

- **`Rugged::ConfigError: ... is not owned by current user`**: ver
  `04_GIT_TOOLING.md`, gotcha de `safe.directory`.
- **Caracteres acentuados con mojibake al hacer `cat index.xml` en
  PowerShell**: casi siempre es solo un problema de visualización de la
  consola (codepage), no del archivo. Antes de asumir que el archivo está
  corrupto, abrirlo en VS Code (`code index.xml`) — si ahí se ve bien, no
  hay nada que arreglar.
- **Categoría anidada en vez de corta** (`Scripts/Custom/AutoColor` en
  vez de `AutoColor`): limitación conocida por cómo `reapack-index`
  deriva la categoría (ruta completa desde la raíz del repo). No afecta
  funcionalidad — ver pendiente documentado en `00_CONTEXTO_GENERAL.md`.
- Mover/renombrar un script después de generarle header no cambia nada
  del lado de ReaPack, pero sí invalida el Command ID local si ya estaba
  registrado en el Action List de la PC de dev — mismo gotcha de siempre,
  documentado en `01_CONVENCIONES.md`.

## Pendiente

- `RemoteControl/`: scripts que consumen módulos de `_Shared/` vía
  `dofile` van a necesitar el tag `@provides` en el header para que
  ReaPack instale también esos módulos junto con el script principal —
  no resuelto todavía, es el próximo paso.
- Ver reestructuración de carpetas pendiente (categoría corta) en
  `00_CONTEXTO_GENERAL.md`.