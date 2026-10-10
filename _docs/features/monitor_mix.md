# Feature — Monitor Mix (mezcla de monitoreo por músico)

Complementa `remote_control.md`, `musicstate_lyrics.md` y `01_CONVENCIONES.md`.
Reemplaza en la práctica a la Línea C de `click_bus.md` (documento de
investigación, no está en el repo; la Línea M, metrónomo nativo global,
queda aparte).

**Estado:** investigación de ruteo cerrada (pasos 1–3). Diseño en curso.
Sin código de producto todavía.

---

## 1. Objetivo

Que el baterista (y a futuro otros músicos) ajuste su propia mezcla de
monitoreo mientras toca, sin afectar la mezcla principal ni los renders.

- Interfaz web separada, servida por un segundo Web Control (puerto propio
  y página por defecto propia).
- Sin controles de transporte: solo una lista filtrada de tracks, cada uno
  con volumen y mute propios.
- El click es un folder con hijos (beep, percusión, palillos...); el
  baterista elige cuál escucha con el fader/mute de cada hijo.
- La salida se resuelve dinámicamente según la placa de cada PC.

---

## 2. Arquitectura

```
Tracks filtrados ──send──▶ Monitor Bus - Batería ──hardware out──▶ par secundario (ej. 3/4)
                           (B_MAINSEND = 0)
```

- Un track bus por músico, con `B_MAINSEND = 0` y su única salida de
  hardware en el par secundario. El código maneja una **lista de buses**
  desde el inicio, aunque hoy haya uno. En v1 hay un único bus por
  músico, sin maestros (ver 6 y 8).
- Los tracks elegidos le hacen sends de track normales.
- El volumen del baterista es **volumen de send**, nunca del track (el
  fader del track cambia la mezcla de todos).
- El mute del baterista es **mute del send**, nunca del track.
- El volumen del bus es el control general y el lugar del limitador de
  seguridad. La salida "Hardware" del bus queda fija en 0 dB.
- Los sends se crean por Lua, de forma idempotente, con nivel inicial bajo
  (seis stems más clicks a 0 dB suman fuerte en auriculares).
- El count-in que se graba en el render conserva su send al master y es
  independiente de los clicks de monitoreo (un mismo track no mezcla ambos
  usos).

---

## 3. Hallazgos verificados

Probado en REAPER 7.79, Windows 10, Fast Track Ultra 8r (dev).
Scripts de prueba en `Tests-Debug/`: `Nik_MonitorMix_ProbeOutputs.lua` y
`Nik_MonitorMix_ProbeBus.lua`.

### 3.1 Salidas de audio

- `GetNumAudioOutputs()` devuelve solo el rango habilitado en
  Preferences > Audio > **Last output** (cambia sin reiniciar REAPER).
  El "2 salidas" de `click_bus.md` era ese rango, no el límite de la placa.
- Los nombres son genéricos (`Software Out N Fast Track Ultra`); la UI los
  muestra tal cual.
- La hardware output del master se lee con `GetTrackSendInfo_Value(master,
  1, i, "I_DSTCHAN")`. Codificación: `0` = par 1/2, `1024 + i` = mono
  salida `i`.

### 3.2 Regla del par secundario

**Primer par alineado (índice par) cuyos dos canales no usa el master.**
En dev resuelve a `I_DSTCHAN=2` (salidas 3/4, base 1) con 4, 6 y 8 salidas
habilitadas. Pares no alineados (`3/4`, `5/6` base 0) se descartan.

- El software no sabe a qué está conectada la bajada de auriculares:
  hace falta una constante de override en código, y la UI muestra el par
  resuelto para verificar a ojo.
- Si no hay par disponible, la UI avisa. **Nunca cae al master.**

### 3.3 Bus de prueba

- Bus con `B_MAINSEND=0` + hardware send al par resuelto: suena solo por
  3/4, no toca el master ni el render.
- `CreateTrackSend(src, bus)` crea el send con `vol=1.0`, `mute=0`,
  `I_SENDMODE=0` (post-fader).
- Mute del send y mute del track son independientes en el estado, pero
  **mutear el track silencia sus sends incluso en pre-fader (post-FX)**.
  Bajar el fader del track no afecta a un send pre-fader.
- Modo por defecto: `I_SENDMODE=3` (post-FX, pre-fader), constante en
  código.
- Undo: crear/borrar el bus deja una sola entrada. `dirty` no se pudo
  concluir (el proyecto ya estaba modificado); baja prioridad.

### 3.4 Feed nativo del Web Control

Línea `TRACK`: los tres contadores antes del color son `sendcnt`,
`recvcnt`, `hwoutcnt`. Un bus de monitoreo se detecta con `recvcnt > 0` y
`hwoutcnt > 0`.

Línea `SEND` (se pide con `GET/TRACK/<x>/SEND/<y>`, con ambos índices; sin
`<y>` no devuelve nada):

```
SEND  <track>  <idx>  <flags>  <vol lineal>  <pan>  <track destino>
```

| Dato | Valor |
|---|---|
| Hardware output | destino `-1` (el cliente lo ignora en la lista) |
| Mute del send | `flags & 8` (nunca `flags == 8`, es una máscara) |
| Volumen, lectura | lineal |
| Volumen, escritura | `SET/TRACK/x/SEND/y/VOL/<dB>` |
| Mute, escritura | `SET/TRACK/x/SEND/y/MUTE/-1` (alterna) |

El índice de send es por origen: los receives no cuentan. El orden de
índices cuando un mismo track tiene sends de track y de hardware no está
verificado; no afecta al diseño (los hardware viven en el bus).

El remoto principal ya usa estos comandos (`trackSendSvg`): volumen y mute
del baterista pueden ir por comandos nativos, sin Lua.

---

## 4. Filtro de tracks (en código, sin UI)

Lo configura el coordinador editando Lua. El filtro es **presentación, no
seguridad**: cualquiera con acceso HTTP puede disparar acciones. Por eso
vive en Lua, el cliente recibe la lista ya filtrada y los scripts de
escritura validan que el GUID pedido esté en esa lista.

### 4.1 Carpetas válidas

El filtro distingue **qué folders son fuente de tracks**. Hoy:

- Stem Bus (`role = "stems"`): se descubre con `StemBus_common_logic`.
- Click (`role = "click"`): folder propio con los hijos de click.

Cada entrada define alias de nombre (case-insensitive) y si toma solo
hijos directos o todo el árbol (`recursive`, por defecto `true`: incluye
subcarpetas). Un folder fuera de la lista no aporta tracks. El filtro
devuelve, para cada track admitido, el `role` de la carpeta que lo aportó
(`stems`, `click`) o `nil` si entró por `include`/GUID.

### 4.2 Orden de decisión

1. `exclude` (palabra clave o GUID) **gana siempre**.
2. `guid_include`: admite el track aunque sea un folder o un bus de
   monitoreo. Es la única forma de rescatarlos.
3. Folders (`I_FOLDERDEPTH == 1`) y buses de monitoreo (`recvcnt > 0` con
   `hwoutcnt > 0`; además se excluyen por nombre los de `buses`): afuera.
4. Palabra clave de `include` (aplica aunque el track esté fuera de una
   carpeta válida).
5. Pertenencia a una carpeta válida.
6. Si nada aplica, queda afuera.

### 4.3 Comparación de nombres

- Case-insensitive, **subcadena** (no patrón de Lua): `string.find(nombre,
  kw, 1, true)`, así un `-` o `.` no se interpreta como comodín.
- `string.lower` no convierte mayúsculas acentuadas UTF-8: el módulo
  normaliza `Á É Í Ó Ú Ñ` antes de comparar y las palabras clave van sin
  acentos.
- Falsos positivos (`bass` coincide con `Bass Drum`): se resuelven con
  `exclude` o con un GUID puntual.

### 4.4 Overrides por proyecto

Los proyectos se parecen mucho; el config tiene una base y una lista de
overrides para las excepciones. Cada override se activa si su `match`
(subcadena, case-insensitive) aparece en el nombre del proyecto. Las
listas (`include`, `exclude`, GUIDs) se **suman** a la base; `folders`, si
se define, **reemplaza** a la base.

### 4.5 Forma tentativa del config (`MonitorMix_config.lua`)

```lua
return {
  buses = {
    { name = "Monitor Bus - Bateria", pair_override = nil },
  },
  folders = {
    { role = "stems", aliases = nil, recursive = true },  -- nil = BUS_ALIASES
    { role = "click", aliases = { "click", "metronomo" }, recursive = true },
  },
  include = {},
  exclude = { "lyrics", "monitor bus" },
  guid_include = {},
  guid_exclude = {},
  overrides = {
    -- { match = "nombre del proyecto", include = {...}, exclude = {...} },
  },
}
```

---

## 5. Riesgos anotados

- **Snapshots `SN_*`:** si mutean tracks, ese mute silencia también el
  monitoreo (confirmado en 3.3). Por ejemplo `SN_Drums_Muted` dejaría al
  baterista sin batería. Falta ver si los snapshots mutean o bajan
  volúmenes. No urgente.
- **Rango de salidas:** si Last output no llega a la 4, el script dirá
  "ninguno disponible" aunque la placa lo tenga. Revisar primero en sala.
- **Crear sends en runtime** ensucia Undo y marca el proyecto. Mitigación:
  creación idempotente, en un único bloque de Undo, al abrir la UI o al
  primer uso.
- **Render:** sin riesgo, el bus no va al master.
- **Plantilla:** debe estar sin `METRONOMEOUT` (ver `click_bus.md` 2.3) si
  se usa la Línea M.

---

## 6. Interfaz web (borrador)

- Segundo Web Control, con puerto y página por defecto propios.
- Reutiliza del lyrics el header (título, tonalidad + tempo). El stage del
  mixer se calcula según viewport y **scrollea solo él**; header y footer
  quedan fijos.
- Lista vertical con sliders horizontales (evita el conflicto
  scroll/arrastre y da blancos táctiles grandes), mute por track y
  etiqueta con el par de salida resuelto.
- Solo se ve la lista filtrada; ningún control de playback.
- Un solo bus por músico en v1, sin maestros. La lista se separa
  visualmente en dos secciones según `role`: música/instrumentos y click.
  Cada track tiene su propio fader y mute de send.
- A futuro: dos volúmenes maestros (música y click), ver 8.

---

## 7. Plan y estado

| Paso | Contenido | Estado |
|---|---|---|
| 1 | Probe de salidas y par secundario | Cerrado |
| 2 | Probe de bus, mute y modo de send | Cerrado |
| 3 | Probe del feed nativo (`TRACK`/`SEND`) | Cerrado |
| 4.1 | Config y módulo del filtro (Lua, testeable) | Verificado en dev (carpetas, exclude); sin probar: recursive, GUIDs, overrides, regla de bus |
| 4.2 | Creación idempotente de sends (Lua) | Pendiente |
| 4.3 | Canal de datos: lectura nativa filtrada vs. ExtState | Abierto |
| 4.4 | Segunda interfaz web | Abierto |

Estructura prevista: carpeta de dominio `MonitorMix/` en la raíz del repo
(`Nik_MonitorMix_<Acción>.lua`, módulos `MonitorMix_common_logic.lua` y
`MonitorMix_config.lua`). Alta de la carpeta en `01_CONVENCIONES.md`
pendiente.

---

## 8. Pendientes y decisiones abiertas

- Resuelto: cada folder válido toma todo el árbol (`recursive = true` por
  defecto), porque puede haber subcarpetas (voces, guitarras, etc.). Los
  folders mismos quedan fuera de la lista; solo aportan sus hijos.
- Futuro (fuera de v1): dos volúmenes maestros para el baterista
  (música/instrumentos y click). Un send no tiene volumen de grupo, así
  que requiere un bus por `role` y por músico (ej. `Monitor Bus - Batería
  - Música` y `Monitor Bus - Batería - Click`), ambos con hardware output
  al mismo par secundario y cada track mandando al bus de su `role`. El
  limitador quedaría repetido en cada bus. En v1 el filtro ya devuelve el
  `role` para separar la UI en secciones; `buses` en el config pasaría a
  ser un bus por `role` y por músico.
- Dónde filtra el canal de datos: Lua (preferido) o JS (4.3).
- `find_bus_track` de `StemBus_common_logic` necesita un parámetro
  opcional de alias (default `BUS_ALIASES`) para reutilizarse sin romper a
  `RemoteControl/` ni `ReaPitchBus/`; `get_folder_children` no valida que
  el parent sea un folder y devuelve todos los descendientes.
- Validar en sala (U-Phoria, pares 1/2, 2/3, 3/4): salidas listadas,
  `I_DSTCHAN` del master y par resuelto.
- Mute en la mezcla principal: mutear un track en el remoto del
  coordinador también silencia su send al monitoreo (3/4), ver 3.3. A
  futuro se quiere que el baterista lo siga recibiendo, con la "M" roja
  visible solo en el remoto del coordinador. Sin investigar, baja
  prioridad.
- Canal de datos para faders continuos: `_RS` por movimiento es pesado;
  evaluar el feed nativo o un script en background con `reaper.defer`.
- Probar `dirty` y Undo con el proyecto limpio.
- Actualizar `00_CONTEXTO_GENERAL.md` (mapa y tabla de estado) al arrancar
  el código.
