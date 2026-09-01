# Convenciones Compartidas

Fuente única de verdad para nomenclatura usada por más de una funcionalidad.
Si una convención cambia, editar **solo acá** — el resto de los documentos
deben referenciar este archivo, no duplicar las tablas.

## Tracks de stems (nombres en inglés, en el proyecto)
```
Drums
Bass
Guitar
Piano
Other
Vocals
```

## Correspondencia: Track (inglés) ↔ Instrumento (español, usado en render) ↔ Snapshot

| Track (inglés) | Instrumento (español) | Snapshot protagonista | Snapshot "muted" (sin instrumento) |
|-----------------|-------------------------|--------------------------|--------------------------------------|
| Drums           | Batería                 | SN_Drums                 | SN_Drums_Muted                        |
| Bass            | Bajo                     | SN_Bass                  | SN_Bass_Muted                         |
| Guitar          | Guitarra                 | SN_Guitar                | SN_Guitar_Muted                       |
| Piano           | Piano                    | SN_Piano                 | SN_Piano_Muted                        |
| Other           | Otros                    | SN_Other                 | SN_Other_Muted                        |
| Vocals          | Voz                      | SN_Vocals                | SN_Instrumental *(excepción, nombre legado — caso "sin Voz")* |

Snapshot adicional: `SN_Base` = mix base (referencia, no protagonista de
ningún instrumento en particular).

**Nota:** `SN_Instrumental` no sigue el patrón `_Muted` porque ya existía con
ese nombre antes de definir la convención `_Muted`. Se documenta como
excepción deliberada, no se renombra.

## Nomenclatura de snapshots (regla general)
- Prefijo fijo: `SN_`
- Protagonista: `SN_<Track>` (nombre de track en inglés, sin espacios)
- Sin instrumento: `SN_<Track>_Muted`
- Separador: guion bajo (`_`), consistente con el prefijo.

## Nomenclatura de regiones de render = nombre de archivo final

Regla: **el nombre de la región es idéntico al nombre de archivo final**
(sin extensión). Esto es necesario porque el wildcard `$region` en el render
toma el nombre tal cual está escrito, sin transformación posible.

### Canción completa
```
🎵 Audio - Master (<Tonalidad> - <BPM> BPM)
🎵 Audio - <Instrumento> (<Tonalidad> - <BPM> BPM)
🎵 Audio - Sin <Instrumento> (<Tonalidad> - <BPM> BPM)
```
Ejemplo: `🎵 Audio - Bajo (G - 95 BPM)`, `🎵 Audio - Sin Batería (G - 95 BPM)`

### Por sección (fragmento con protagonista)
```
🎵 Audio - <Instrumento> - <Sección>
```
Ejemplo: `🎵 Audio - Bajo - Coro 1`

### Por sección (mezcla completa menos un instrumento)
```
🎵 Audio - Sin <Instrumento> - <Sección>
```
Ejemplo: `🎵 Audio - Sin Batería - Coro 1`

### Notas sobre estas regiones
- Estas regiones **no son la sección "limpia"** — incluyen el count-in previo
  más 1 segundo de padding de silencio al inicio y al final (ver
  `features/render_workflow.md`).
- Las secciones limpias (para navegación) se manejan con **markers** simples
  (o, alternativamente, regiones en un lane separado y oculto, gracias a la
  feature de region lanes de REAPER 7.76).

## Nombres de secciones (markers)
Nomenclatura estándar usada en el proyecto actual:
```
INTRO, VERSO 1, PRECORO, CORO 1, INTRO, VERSO 2, PRECORO, CORO 2, PUENTE, PRECODA, CODA
```
Nota: existe una nomenclatura alternativa abreviada usada en otros proyectos
(V1, V2, PC, C1, etc.) — pendiente de considerar un parser a futuro, no
bloqueante hoy.

## Convención de nombres de scripts Lua (raíz del repo, `C:\dev\Rea-Nik\`)

Dos categorías, para poder distinguirlas a simple vista (y para poder
filtrar solo lo ejecutable si algún día se importa la carpeta al Action
List):

**Scripts ejecutables** (se registran en el Action List, se disparan desde
ahí o desde un footswitch MIDI): `Nik_<Dominio>_<Acción>.lua`
- `Nik_` fijo al principio — permite filtrar el catálogo propio en el
  Action List tipeando "nik".
- `<Dominio>` en PascalCase (`ReaPitchBus`, `TabCycle`, `StemFragment`...).
- `<Acción>` el verbo o qué hace (`Next`, `Read`, `SetSemitones`,
  `ToggleEnable`...).

**Módulos de soporte** (solo se cargan vía `dofile`, nunca se registran
como acción): `<Dominio>_common_logic.lua`, **sin** prefijo `Nik_` — así
quedan separados alfabéticamente de los ejecutables.

### Pendiente (no bloqueante)
Los scripts existentes de la familia `NikRemote_*` (`NikRemote_ReaPitch_*`,
`NikRemote_TabNext/Prev`) no siguen esta convención todavía (usan
`NikRemote_<Dominio>_<Acción>` en vez de `Nik_<Dominio>_<Acción>`).
Convención aplica de acá en adelante para scripts nuevos; evaluar rename de
los existentes en otra sesión, sin apuro.

## Estructura de subcarpetas (raíz del repo, `C:\dev\Rea-Nik\`)

Cada dominio funcional vive en su propia subcarpeta, nombrada en PascalCase
igual que el `<Dominio>` usado en el naming de scripts ejecutables
(`Nik_<Dominio>_<Acción>.lua`), para que carpeta y prefijo de archivo queden
alineados a simple vista. El repo vive fuera de `%APPDATA%\REAPER` (ver
"Entorno de desarrollo" en `00_CONTEXTO_GENERAL.md`) — los scripts se
registran en el Action List apuntando directo a esta ruta, sin necesidad de
vivir bajo `Scripts\` del resource path de REAPER:

```
C:\dev\Rea-Nik\
├── _Shared/ módulos *_common_logic.lua consumidos por más de un dominio
├── RemoteControl/ control remoto web (poll, tabs, playrate, ReaPitch remoto)
├── ReaPitchBus/ panel nativo ReaImGui de ReaPitch
├── MvsepImporter/ importador de stems desde MVSEP
├── RenderWorkflow/ generación de regiones + batch render
├── TempoTools/ utilidades de tempo/compás
├── AutoColor/ auto-color de tracks
├── StemFragment/ captura/UI de fragmentos de stem
├── Tests-Debug/ scripts de diagnóstico y prueba (sin dominio propio)
├── web/ control remoto web servido como `reaper_www_root` (vía junction)
└── _docs/ documentación del proyecto (este archivo y los demás `.md`)
```

`_Shared/` lleva el prefijo `_` para ordenar primero en el explorador y para
poder excluirla fácilmente si algún día se importa la carpeta completa al
Action List (no contiene scripts ejecutables, solo módulos).

Un módulo entra a `_Shared/` cuando lo consume más de un dominio (hoy:
`StemBus_common_logic.lua` y `ReaPitchBus_common_logic.lua`, usados por
`RemoteControl/` y por `ReaPitchBus/`). Un módulo usado por un solo dominio
se queda dentro de la carpeta de ese dominio (ej.
`ActiveProject_common_logic.lua`, `ProjectTabs_common_logic.lua` y
`MarkerBars_common_logic.lua` viven dentro de `RemoteControl/`, no en
`_Shared/`, porque solo los consume ese dominio).

**Importante:** mover o renombrar un script ya registrado en el Action List
(o mapeado a un footswitch MIDI) invalida su Command ID — hay que sacarlo
de la lista y volver a hacer "Load ReaScript" desde la ubicación nueva.
Esto es aparte de git; git solo versiona el archivo, no el registro interno
de REAPER.

## Patrón de módulos de lógica compartida (`dofile`)

Para centralizar lógica usada por más de un script (evitar copiar/pegar
funciones idénticas en cada uno), el patrón es `dofile` con ruta resuelta
en base al propio archivo — no `require` (depende de `package.path`, que
no apunta a la carpeta del script por defecto en el contexto de REAPER):

```lua
local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Modulo = dofile(script_dir .. "NombreDelModulo_common_logic.lua")
```

Esto resuelve la ruta absoluta del script que lo invoca sin importar desde
dónde se dispare (Action List, footswitch MIDI, etc.).

Cuando el módulo vive en la misma carpeta que quien lo consume, la ruta es
directa. Cuando el módulo vive en `_Shared/` (consumido por más de un
dominio), los scripts consumidores suben un nivel en la ruta relativa:

```lua
local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local StemBus = dofile(script_dir .. "../_Shared/StemBus_common_logic.lua")
```

Cada módulo expone una tabla (`local M = {}` ... `return M`), nunca
funciones/variables sueltas en el entorno global, para no contaminar el
namespace de los scripts que lo cargan.

Caso implementado: `StemBus_common_logic.lua` (discovery genérico del Stem
Bus y sus tracks hijos) + `ReaPitchBus_common_logic.lua` (específico de
ReaPitch, consume el módulo anterior). Ambos viven en `_Shared/`, consumidos
por `RemoteControl/NikRemote_ReaPitch_Read/SetSemitones/ToggleEnable.lua` y
por `ReaPitchBus/Nik_ReaPitchBus_Knob.lua` (ver `03_PANEL_REAPITCH_KNOB.md`).