# Notas ImGui / Lua — infraestructura de testing y gotchas del lenguaje

Doc de trabajo para la exploración de ReaImGui: infraestructura de pruebas
armada en `Tests-Debug/ImGui/` y hallazgos sueltos sobre el lenguaje (Lua)
o la API que no ameritan su propio doc de feature. Sigue las convenciones
de `01_CONVENCIONES.md` — no las duplica.

## Origen

8 archivos `.lua` (+1 adicional) extraídos del demo oficial de ReaImGui
(~10k líneas en el original, partido en pedazos), usados como material de
referencia para extraer/probar fragmentos de cara a la UI del panel
ReaPitch y futuros paneles.

## Estructura

```
Tests-Debug/ImGui/
├── reference/                    ← los 8+1 archivos originales, sin
│                                    modificar, nombres intactos (para
│                                    poder diffear contra el original si
│                                    ReaImGui actualiza su demo)
├── Debug_common_logic.lua        ← Msg() + pcallLoop()
├── Harness_common_logic.lua      ← boilerplate de ventana ImGui
├── Nik_ImGui_Template.lua        ← base para duplicar en tests nuevos
└── Nik_ImGui_DebugSmokeTest.lua  ← referencia de que Debug+Harness andan
```

## Módulos

### `Debug_common_logic.lua`
- `Debug.Msg(...)` — logging a consola de REAPER (concatena args con tab).
  Flag `Debug.enabled` a nivel módulo para silenciar todo de una.
- `Debug.pcallLoop(fn)` — envuelve `fn` en `pcall` + `debug.traceback`.
  Devuelve `false` si hubo error (ya impreso en consola), para que el
  caller corte el `reaper.defer()` en vez de reintentar con el mismo error.

### `Harness_common_logic.lua`
Encapsula el ciclo de vida completo de una ventana de test: carga del shim
de ReaImGui, `CreateContext`, loop de `reaper.defer()` (envuelto en
`Debug.pcallLoop`), y cierre de ventana (`open == false` corta el loop).

`Harness.Run({ title, version, body })` — `body(ImGui, ctx)` recibe `ImGui`
como parámetro (no como global), se llama una vez por frame.

`Harness.LoadImGui(version)` queda expuesta aparte por si algún test
necesita el objeto `ImGui` suelto fuera del loop (leer flags/constantes).

## Workflow para un test nuevo

1. Duplicar `Nik_ImGui_Template.lua` → `Nik_ImGui_<NombreDelTest>.lua`
   (mismo `Tests-Debug/ImGui/`).
2. "Load ReaScript..." en el Action List sobre la copia (Command ID nuevo,
   independiente del template).
3. Copiar/adaptar el fragmento a probar desde `reference/` dentro de `body`.
4. Re-correr la acción desde el Action List cada vez que se edite el
   archivo — no hace falta re-registrar.

## Carga del shim de ReaImGui

`require 'imgui'` **no** funciona out-of-the-box: busca en el
`package.path` estándar de Lua, y la carpeta del shim no está ahí por
defecto. El shim real vive en una ruta fija instalada por ReaPack:

```
<resource_path>\Scripts\ReaTeam Extensions\API\imgui.lua
```

Se carga con `dofile` directo, no con `require`:

```lua
local ImGui = dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.9.3')
```

Guard recomendado antes, para evitar el error críptico si la extensión no
está instalada:

```lua
if not reaper.ImGui_CreateContext then
  reaper.MB('Falta instalar ReaImGui (ReaPack -> ReaTeam Extensions).', 'Error', 0)
  return
end
```

(`Harness.LoadImGui` ya incluye este guard — no hace falta repetirlo a
mano si se usa el harness.)

## Gotchas de Lua encontrados

### Scope al partir un archivo único en varios chunks
El demo original de ReaImGui es un solo archivo de ~10k líneas. Al
partirlo mecánicamente en 8, variables declaradas una sola vez con
`local` cerca del principio del original (ej. `rv` como scratch var
reusada en cientos de lugares, `show_app` como tabla de estado de qué
ventanas de ejemplo están abiertas) dejan de existir como locales en los
archivos donde no fueron declaradas — Lua las trata como globales reales
de `_G` en esos chunks.

**Síntoma en VS Code (lua-language-server):**
- `show_app` → "undefined-global" (no hay ningún `local show_app` en ese
  chunk).
- `rv` → "Global variable in lowercase initial, ¿te olvidaste `local`?"

**Por qué "funcionaba" antes de arreglarlo:** si todos los archivos corren
en el mismo estado de Lua (mismo script de REAPER cargándolos), el primero
en ejecutarse crea la global real en `_G`, y los siguientes la
leen/escriben ahí — funciona por efecto colateral del orden de carga, no
por diseño. Frágil: correr un archivo aislado (el caso de uso real acá)
puede fallar o comportarse distinto según qué otro script corrió antes en
la sesión.

**Solución aplicada:** agregar el `local` faltante en cada archivo que
usa la variable, en vez de silenciar el warning. Ver también: no meter
estos nombres en `.luarc.json` → `diagnostics.globals` — ese campo es para
globals que provee el *host* (ej. `reaper`), no para tapar variables que
en realidad son locales mal scopeadas.

### `nil.algo()` es error de sintaxis, no de runtime
`nil` es palabra reservada, no una variable. `nil.rompeme()` no compila —
Lua lo rechaza antes de ejecutar una sola línea del archivo, y por lo
tanto **no** lo atrapa ningún `pcall` (que solo atrapa errores en
ejecución de código ya compilado). Para simular a propósito un error de
runtime (y probar `Debug.pcallLoop`), usar una variable real:

```lua
local x = nil
x.rompeme()
```

### `diagnostics.globals` en `.luarc.json`
Reservado para globals reales del entorno de ejecución (`reaper`). No usar
para tapar warnings de variables que deberían ser `local` — ver gotcha de
scope arriba.
