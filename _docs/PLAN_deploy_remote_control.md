# Plan — Deploy de RemoteControl vía ReaPack

Sesión de origen: análisis cerrado el 03/09/2026. Objetivo de este archivo:
punto de partida para la sesión de implementación — no repite contenido de
`01_CONVENCIONES.md` ni `05_REAPACK_DEPLOY.md`, solo referencia y agrega lo
específico de este deploy. Documento transitorio: una vez implementado,
fusionar lo que corresponda a `05_REAPACK_DEPLOY.md` (el `@provides` para
`_Shared/` ya está anotado como pendiente ahí) y borrar este archivo,
mismo criterio que ya aplica a los `DEBUG_*.md`.

## Alcance de esta sesión de implementación

Cerrar el deploy de `RemoteControl/` vía ReaPack (`AutoColor/` ya está
deployado, ver `05_REAPACK_DEPLOY.md`). Tres frentes, ninguno bloquea a los
otros dos salvo por orden de conveniencia (ver "Orden propuesto" abajo):

1. `@provides` para los módulos Lua consumidos vía `dofile`.
2. Validar que el named ID (`_RS<hash>`) ya usado en `config.js` se sostiene
   una vez que los scripts llegan por ReaPack en vez de por copia manual.
3. Empaquetar `web/` (HTML/JS/CSS de la interfaz remota) como paquete
   `.www` — hoy sin cubrir en `05_REAPACK_DEPLOY.md`.

## Frente 1 — `@provides` para módulos Lua consumidos vía `dofile`

Módulos sin header propio (por convención, nunca lo tienen — ver
`01_CONVENCIONES.md`) que necesitan viajar igual al deploy:

- `_Shared/StemBus_common_logic.lua`
- `_Shared/ReaPitchBus_common_logic.lua`
- `RemoteControl/ActiveProject_common_logic.lua`
- `RemoteControl/ProjectTabs_common_logic.lua`
- `RemoteControl/MarkerBars_common_logic.lua`

Scripts "header" (registrados en Action List) que los consumen, candidatos
a llevar el `@provides`:

- `Nik_RemoteState_Poll.lua` — consume los cinco (directa o
  indirectamente, vía los módulos `write_aggregated_state()`).
- `Nik_TrackVis_Refresh.lua`
- `Nik_ProjectTabs_Read.lua` / `Nik_ProjectTabs_Select.lua`
- Familia `NikRemote_ReaPitch_Read/SetSemitones/ToggleEnable.lua`

**Pendiente, abierto para la sesión de implementación:** decidir si cada
módulo se declara en el `@provides` del script que más lo usa (ej.
`StemBus_common_logic.lua` bajo `Nik_RemoteState_Poll.lua`), o se
centraliza todo en un único script "ancla" para simplificar el
mantenimiento del header. `reapack-index` exige que cada archivo target
tenga un solo dueño (exclusividad de paquete) — sea cual sea el criterio,
un módulo no puede quedar declarado en el `@provides` de más de un script.

## Frente 2 — Validación de named ID (`_RS<hash>`) contra instalación real ReaPack

**Contexto ya confirmado (no volver a discutir):**
- `config.js` ya dispara todo vía `_RS<hash>`, no vía Command ID numérico.
  Los únicos IDs numéricos en juego son nativos de REAPER (ej. `40671`,
  preserve pitch), estables por diseño — no hay migración de mecanismo
  pendiente, el patrón correcto ya está en uso.
- Validado empíricamente en PC de ensayo: copiar los scripts a mano a una
  ruta relativa igual a la de la PC de dev genera el mismo `_RS<hash>`.

**Punto abierto:** ReaPack instala en `Scripts/Rea-Nik/<categoría>/...`
(ruta relativa distinta a la de dev, que carga desde
`C:\dev\Rea-Nik\RemoteControl\...` vía "Load ReaScript"). No está
confirmado si esa ruta de ReaPack genera el mismo `_RS<hash>` que el ya
hardcodeado en `config.js`.

**Test propuesto (primer paso de la implementación):**
1. Instalar el paquete de `RemoteControl` vía ReaPack en una PC de destino
   (o reinstalar en la misma PC de ensayo usada para el test anterior, en
   una ruta ReaPack real en vez de la copia manual).
2. Comparar el `_RS<hash>` resultante (Action List → clic derecho → copiar
   Command ID) contra el ya hardcodeado en `config.js`.
3. Si coincide: nada que tocar, el pendiente queda cerrado sin más.
4. Si no coincide: actualizar `config.js` una sola vez con el hash real de
   ReaPack — a partir de ahí queda estable para cualquier PC de ensayo
   futura, porque ReaPack siempre instala en la misma ruta relativa.

## Frente 3 — Empaquetado de `web/` como paquete `.www`

**Confirmado por investigación (ver también sección de hallazgos técnicos
más abajo):**
- El tipo `.www` (Web Interfaces) es el mecanismo oficial de
  `reapack-index` para este caso, disponible desde ReaPack v1.1.
- El archivo "raíz" del paquete necesita **extensión `.www`** (no
  `.html`) con el header de metadata arriba — es un manifiesto aparte del
  `index.html` real.
- `@provides` soporta wildcards y subcarpetas, así que la estructura
  completa (`core/`, `modals/`, `markers/`) se puede declarar con
  patrones en vez de listar archivo por archivo.

**No confirmado — validar en la sesión de implementación:** dónde
aterriza en disco el paquete instalado en destino. No quedó claro por
documentación si ReaPack resuelve automáticamente contra
`reaper_www_root/` (análogo a cómo resuelve `Scripts/Rea-Nik/...` para
scripts) o si hace falta indicar la ruta destino explícitamente dentro
del `@provides` (sintaxis `Original > Target Path` que sí soporta el
formato).

**Implicancia ya identificada:** a diferencia de la PC de dev (que
necesita el junction `reaper_www_root → C:\dev\Rea-Nik\web` porque el
repo vive fuera de `%APPDATA%\REAPER`), una PC de ensayo no debería
necesitar ningún junction — ReaPack instala directo en el resource path
de esa PC. Queda sujeto a la validación del punto anterior.

**Test propuesto:** armar un paquete `.www` mínimo (por ejemplo, solo el
shell `nsaudio_remote_control.html` sin el resto del árbol) para
confirmar el destino real de instalación antes de escribir el
`@provides` completo con toda la estructura de `web/`.

## Orden propuesto para la sesión de implementación

1. Test named ID (Frente 2) — rápido, desbloquea si hace falta tocar
   `config.js` antes de seguir.
2. Test `.www` mínimo (Frente 3) — desbloquea el resto del `@provides` de
   `web/`.
3. `@provides` de módulos Lua (Frente 1) — mecánico, sin incógnitas
   técnicas, se puede hacer en paralelo o después de los tests.
4. Armar el `@provides` completo de `web/` con el resultado del punto 2.
5. `reapack-index --rebuild` + validación de instalación end-to-end en
   una PC de ensayo real (no en la PC de dev, ver gotcha ya documentado
   en `05_REAPACK_DEPLOY.md`).

## Hallazgos técnicos de esta sesión (investigación web)

Contexto para no repetir la investigación en la sesión de implementación:

- **Command ID numérico vs. named ID (`_RS<hash>`):** el Command ID
  numérico es válido solo dentro de una sesión/instalación de REAPER —
  dos instalaciones distintas pueden asignar números distintos al mismo
  script. El named ID (`_RS<hash>`) es la alternativa pensada para ser
  estable entre sesiones e instalaciones — es lo que expone
  `reaper.NamedCommandLookup()` y lo que usan scripts que se llaman entre
  sí sin depender de dónde corren. Coincide con el patrón que
  `RemoteControl` ya usa hoy.
- **Tipo de paquete `.www` (Web Interfaces) de `reapack-index`:**
  - Agregado en ReaPack v1.1, junto con soporte a las Web Interfaces
    custom introducidas en REAPER v5.30.
  - `PKG_TYPES` interno de `reapack-index` mapea `webinterface: %w{www}`
    — el archivo que dispara la indexación como paquete web necesita
    extensión `.www`.
  - Ejemplo oficial de la documentación (`Packaging Documentation` /
    `Examples`, wiki de `cfillion/reapack-index`):
    ```
    @description Web Browser Interface Name
    @author YourName
    @version 1.0
    @provides
      my_interface/index.html
      my_interface/*.{css,js,png}
    ```
  - `@provides` general (aplica a cualquier tipo de paquete, no solo
    `.www`): soporta wildcards (globbing), opciones de plataforma entre
    corchetes (`[windows]`, `[darwin]`, etc.), y redirección de destino
    con `Original File.ext > New Directory/Target File.ext`. Cada archivo
    target debe tener un único paquete dueño (exclusividad).
  - Fuentes: wiki de `cfillion/reapack-index` (`Packaging Documentation`,
    `Examples`) y changelog de ReaPack v1.1rc5/rc6 (foro Cockos).
  - **No encontrado en la documentación:** el detalle de resolución de
    ruta de instalación en destino para paquetes `webinterface` — de ahí
    el test empírico propuesto en el Frente 3.

## Decisiones ya cerradas (no volver a discutir)

- No hay migración de mecanismo de Command ID pendiente — `RemoteControl`
  ya usa named ID (`_RS<hash>`) en todo lo custom; los numéricos en juego
  son nativos de REAPER, estables por diseño.
- El named ID es estable frente a copias manuales a la misma ruta
  relativa (validado en PC de ensayo). Lo que falta validar es
  específicamente la ruta que genera ReaPack, no el mecanismo en sí.
- El deploy de `web/` necesita un paquete `.www` separado de los paquetes
  de scripts Lua — no es algo que se resuelva como efecto colateral de
  indexar `RemoteControl/`.

## Referencias

- `01_CONVENCIONES.md` — nomenclatura de scripts, patrón `dofile`,
  estructura de subcarpetas.
- `05_REAPACK_DEPLOY.md` — alcance general del deploy, prerrequisitos,
  header de metadata, gotchas conocidos. El pendiente de `@provides` para
  `_Shared/` ya estaba anotado ahí antes de esta sesión.
- `remote_control.md` — arquitectura de archivos de la interfaz remota,
  patrón Script Lua + ExtState, `config.js`.
