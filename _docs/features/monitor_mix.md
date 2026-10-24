# Feature — Monitor Mix: ruteo, filtro y datos

Mezcla de monitoreo por músico: bus propio con salida de hardware
secundaria, sends por track, filtro de qué tracks se ofrecen y canal de
datos hacia la UI. Lo lee quien toca el ruteo, el filtro, el config o el
contrato de la lista. La interfaz web (shell, render, faders, slider):
`monitor_mix_ui.md`.

Fuera de este doc: ganchos de `ms-dispatch.js`, polls y ciclo de proyecto
(`musicstate_sync.md` §1, §8, §10, §11), patrón "disparar vs solo leer"
(`musicstate_bridge.md` §5), protocolo del web control y tope de `EXTSTATE`
(`musicstate_data_model.md` §3, §6), deploy (`05_REAPACK_DEPLOY.md`),
convenciones (`01_CONVENCIONES.md`).

## 1. Objetivo

Que el baterista (y a futuro otros músicos) ajuste su propia mezcla de
monitoreo mientras toca, sin afectar la mezcla principal ni los renders.

- Interfaz web separada, servida por un segundo Web Control (puerto y
  página por defecto propios), sin controles de transporte.
- Una lista filtrada de tracks, cada uno con volumen y mute propios.
- El click es un folder con hijos (beep, percusión, palillos...): el
  baterista elige cuál escucha con el fader y el mute de cada hijo.
- La salida se resuelve dinámicamente según la placa de cada PC.

## 2. Arquitectura

```
Tracks filtrados ──send──▶ Monitor Bus - Batería ──hardware out──▶ par secundario (ej. 3/4)
                           (B_MAINSEND = 0)
```

- Un track bus por músico, con `B_MAINSEND = 0` y su única salida de
  hardware en el par secundario. El código maneja una **lista de buses**,
  aunque hoy haya uno, y sin maestros.
- Los tracks elegidos le hacen sends de track normales.
- El volumen del baterista es **volumen de send**, nunca del track (el
  fader del track cambia la mezcla de todos). Su mute es **mute del
  send**, nunca del track.
- El volumen del bus es el control general y el lugar del limitador de
  seguridad. La salida de hardware del bus queda fija en 0 dB.
- Los sends los crea `MM.ensure_sends` (módulo común) de forma
  idempotente: solo crea los que faltan, con nivel inicial
  `defaults.send_db` (-12 dB) e `I_SENDMODE=3`, y nunca modifica un send
  existente. Seis stems más clicks a 0 dB suman fuerte en auriculares.
  Opcionalmente los sends nacen muteados, por rol y solo al crear el bus
  (`defaults.mute_*_on_create`, §6.5).
  `Nik_MonitorMix_Publish.lua` lo invoca; `Nik_MonitorMix_EnsureSends.lua`
  es una cáscara para correrlo a mano.
- La mezcla del baterista vive en los sends del proyecto abierto, en
  memoria: se conserva al cambiar de tab y volver; si el coordinador
  cierra sin guardar, se pierde (deseado). La sostienen dos reglas: el
  script nunca toca sends existentes y la UI solo lee al cambiar de
  proyecto.
- El script actúa sobre el proyecto activo: lo dispara el cliente al
  cambiar de proyecto y desde el botón Actualizar, antes de leer la lista
  (§5).
- El count-in que se graba en el render conserva su send al master y es
  independiente de los clicks de monitoreo (un mismo track no mezcla ambos
  usos).

## 3. Ruteo

Sondas en `Tests-Debug/`: `Nik_MonitorMix_ProbeOutputs.lua` y
`Nik_MonitorMix_ProbeBus.lua`.

### 3.1. Salidas de audio

- `GetNumAudioOutputs()` devuelve solo el rango habilitado en
  Preferences > Audio > **Last output** (cambia sin reiniciar REAPER), no
  el límite de la placa.
- Con *Close audio device when stopped and application is inactive*
  (Preferences > Audio), el dispositivo se cierra cuando REAPER pierde el
  foco (p. ej. al abrir la UI en Chrome) y `GetNumAudioOutputs()` devuelve
  `0`. `M.resolve_pair` llama `reaper.Audio_Init()` antes de contar, lo que
  reabre el dispositivo; con el guard `if reaper.Audio_Init`, una versión
  sin esa API no rompe.
- Los nombres son genéricos (`Software Out N <placa>`); la UI los muestra
  tal cual.
- La hardware output del master se lee con
  `GetTrackSendInfo_Value(master, 1, i, "I_DSTCHAN")`. Codificación: `0` =
  par 1/2, `1024 + i` = mono salida `i`.

### 3.2. Par secundario

**Primer par alineado (índice par) cuyos dos canales no usa el master.**
Con 4, 6 y 8 salidas habilitadas resuelve a `I_DSTCHAN=2` (salidas 3/4,
base 1). Los pares no alineados (`3/4`, `5/6` base 0) se descartan.

- El software no sabe a qué está conectada la bajada de auriculares: por
  eso existe `pair_override` en el config, y la UI muestra el par
  resuelto para verificar a ojo.
- El cálculo abre antes el dispositivo (`Audio_Init`, §3.1), así que el
  resultado no depende de si REAPER tiene el foco. `pair_override` también
  se valida contra las salidas habilitadas.
- Sin par disponible, la UI avisa. **Nunca cae al master.**
- Si el master no tiene hardware output no hay canales ocupados que
  descartar y la regla caería en 1/2: se trata como `no_pair`, salvo que
  el config defina `pair_override`.

### 3.3. Bus y sends

- Un bus con `B_MAINSEND=0` y hardware send al par resuelto suena solo por
  ese par: no toca el master ni el render.
- `CreateTrackSend(src, bus)` crea el send con `vol=1.0`, `mute=0`,
  `I_SENDMODE=0` (post-fader). Monitor Mix usa `I_SENDMODE=3` (post-FX,
  pre-fader), constante `defaults.send_mode`.
- Mute del send y mute del track son independientes en el estado, pero
  **mutear el track silencia sus sends incluso en pre-fader (post-FX)**.
  Bajar el fader del track no afecta a un send pre-fader.
- Crear o borrar el bus deja una sola entrada de Undo.

## 4. Feed nativo del Web Control

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
| Volumen, escritura | `SET/TRACK/x/SEND/y/VOL/<lineal>`; sin sufijo mientras se arrastra, con `e` al soltar |
| Mute, escritura | `SET/TRACK/x/SEND/y/MUTE/-1` (alterna) |
| Paneo, lectura | `<pan>` de la línea `SEND`: -1 izquierda, 0 centro, 1 derecha. REAPER no lo acota (un tercero puede dejarlo en 2) |
| Paneo, escritura | `SET/TRACK/x/SEND/y/PAN/<-1..1>`. **Sin sufijo `e`**: REAPER lo ignora en el paneo. REAPER acepta valores fuera de rango (2 = 200 %R), así que el cliente acota a ±1 |

- El índice de send es por origen: los receives no cuentan. El orden de
  índices cuando un mismo track tiene sends de track y de hardware no está
  verificado; no afecta al diseño (los hardware viven en el bus).
- Volumen, mute y paneo van por comandos nativos, sin Lua. El remoto
  principal ya usa volumen y mute (`trackSendSvg`); el paneo lo escribe
  solo esta UI (`nikMmSetSendPan`, `monitor.js`).
- La escritura **no valida el GUID** del track: decisión asumida (el
  filtro es presentación, no seguridad; ver §6).

## 5. Contrato de datos

`Nik_MonitorMix_Publish.lua` (one-shot) corre `MM.ensure_sends`, aplica el
filtro y publica en el ExtState global, namespace `NikMonitorMix`. Volumen
y mute en vivo siguen por el feed nativo (§4), sin pasar por ExtState.

| Key | Contenido |
|---|---|
| `list` | JSON compacto en una línea |
| `list_version` | Entero; cada ejecución del script lo incrementa |

Primero se escribe `list` y después `list_version`: un cliente que ve la
versión nueva siempre encuentra los datos nuevos. El script **siempre
publica**, incluso sin bus o sin tracks: el `status` explica el motivo y
evita datos viejos del proyecto anterior.

Cada corrida escribe en la consola de REAPER, con hora, el log de
`ensure_sends` y una línea final con `status`, cantidad de tracks y
versión. Cuando hay que crear el hardware output agrega una línea `Par:`
con salidas habilitadas, hardware outputs del master, override y par
resuelto (sirve para diagnosticar `no_pair`). Se apaga con `debug = false`
en el config (§6.5); `Nik_MonitorMix_EnsureSends.lua` imprime siempre.

```json
{"status":"ok","bus":"Monitor Bus - Batería","pair":2,"default_db":-12,"tracks":[{"track":3,"guid":"{...}","name":"Drums","role":"stems","send":0}]}
```

- `track`: número del web control, base 1 (`idx + 1`; `0` sería el
  master). Coincide con `GET/TRACK/<track>/SEND/<send>`.
- `send`: índice de send en el track origen hacia el bus, calculado por
  GUID del bus (no depende del orden de índices sin verificar de §4).
- `role`: `stems`, `click` o `null` (entró por `include`/GUID).
- `pair`: `I_DSTCHAN` de la salida de hardware del bus (`2` = salidas
  3/4), o `null`.
- `default_db`: `defaults.send_db` del config (número) o `null` si no está
  definido. Se publica siempre, también sin bus. El cliente lo usa como
  valor del doble tap; si falta usa `nikMmFader.DEFAULT_DB` (-12).

| `status` | Significado | `pair` | `tracks` |
|---|---|---|---|
| `ok` | Bus y sends asegurados | Par del bus | Lista filtrada (vacía si el bus ya existe pero el filtro no admite ninguno) |
| `no_tracks` | No existe el bus y el filtro no admite ningún track (p. ej. una tab nueva y vacía): no se crea nada | `null` | `[]` |
| `no_pair` | No hay par secundario, o el master no tiene hardware output y no hay `pair_override`: no se crea nada | `null` | `[]` |
| `no_bus_cfg` | El config no define ningún bus | `null` | `[]` |

**Capa cliente** (`web/musicstate-ui/monitor/monitor.js`, solo datos, sin
DOM):

- `nikMmRequestList()` DISPARA el script y pide `list` y `list_version`;
  `nikMmFetchList()` solo lee. Un cambio de `list_version` dispara
  únicamente el `GET`, nunca el script (cada ejecución incrementa la
  versión: sería un bucle; patrón en `musicstate_bridge.md` §5).
- Los ganchos de `ms-dispatch.js` y el disparo al cambiar de proyecto:
  `musicstate_sync.md` §1 y §11. Las UIs que no cargan `monitor.js` no
  cambian.
- El web control duplica las `\`: se des-escapa antes del `JSON.parse`
  (`musicstate_data_model.md` §3).

## 6. Filtro de tracks (en código, sin UI)

Lo configura el coordinador editando Lua. El filtro es **presentación, no
seguridad**: cualquiera con acceso HTTP puede disparar acciones. Por eso
vive en Lua y el cliente recibe la lista ya filtrada.

### 6.1. Carpetas válidas

El filtro distingue **qué folders son fuente de tracks**. Hoy:

- Stem Bus (`role = "stems"`): sus alias salen de `BUS_ALIASES` de
  `StemBus_common_logic` (`MM.stem_aliases`; el módulo no usa
  `find_bus_track`).
- Click (`role = "click"`): folder propio con los hijos de click.

Cada entrada define alias de nombre (case-insensitive) y si toma todo el
árbol (`recursive`, por defecto `true`: incluye subcarpetas) o solo los
hijos directos. Los folders mismos quedan fuera de la lista; solo aportan
sus hijos. Un folder fuera de la configuración no aporta tracks. El filtro
devuelve, para cada track admitido, el `role` de la carpeta que lo aportó
o `nil` si entró por `include`/GUID.

### 6.2. Orden de decisión

1. `exclude` (palabra clave o GUID) **gana siempre**.
2. `guid_include`: admite el track aunque sea un folder o un bus de
   monitoreo. Es la única forma de rescatarlos.
3. Folders (`I_FOLDERDEPTH == 1`) y buses de monitoreo (`recvcnt > 0` con
   `hwoutcnt > 0`; además se excluyen por nombre los de `buses`): afuera.
4. Palabra clave de `include` (aplica aunque el track esté fuera de una
   carpeta válida).
5. Pertenencia a una carpeta válida.
6. Si nada aplica, queda afuera.

### 6.3. Comparación de nombres

- Case-insensitive, **subcadena** (no patrón de Lua):
  `string.find(nombre, kw, 1, true)`, así un `-` o `.` no se interpreta
  como comodín.
- `string.lower` no convierte mayúsculas acentuadas UTF-8: el módulo
  normaliza `Á É Í Ó Ú Ñ` antes de comparar y las palabras clave van sin
  acentos.
- Falsos positivos (`bass` coincide con `Bass Drum`): se resuelven con
  `exclude` o con un GUID puntual.

### 6.4. Overrides por proyecto

El config tiene una base y una lista de overrides para las excepciones.
Cada override se activa si su `match` (subcadena, case-insensitive)
aparece en el nombre del proyecto. Las listas (`include`, `exclude`,
GUIDs) se **suman** a la base; `folders`, si se define, **reemplaza** a la
base.

### 6.5. Config (`MonitorMix_config.lua`)

```lua
return {
  -- false = Publish.lua no escribe en la consola de REAPER.
  debug = true,
  buses = {
    { name = "Monitor Bus - Batería", pair_override = nil },
  },
  -- pair_override: I_DSTCHAN de un par estéreo (par, ej. 2 = salidas 3/4);
  -- nil = regla automática del par secundario. Si el master no tiene
  -- hardware output la regla no deduce el par (status no_pair): definir
  -- el override.
  defaults = {
    send_db = -12,
    send_mode = 3,
    -- true = los sends nacen muteados, solo al crear el bus.
    mute_click_on_create = false,
    mute_music_on_create = false,
  },
  folders = {
    { role = "stems", aliases = nil, recursive = true },  -- nil = BUS_ALIASES
    { role = "click", aliases = { "click", "metronomo" }, recursive = true },
  },
  include = {},
  exclude = { "lyrics" },  -- los nombres de `buses` se excluyen solos
  guid_include = {},
  guid_exclude = {},
  overrides = {
    -- { match = "nombre del proyecto", include = {...}, exclude = {...} },
  },
}
```

**Mute al crear** (`mute_click_on_create`, `mute_music_on_create`, ambas
`false` por defecto):

- Los sends nacen con `B_MUTE=1` según su rol, solo en la corrida que
  crea el bus (`res.created_bus` en `MM.ensure_sends`). Con el bus
  existente no modifican ningún mute, ni de sends actuales ni de tracks
  agregados después (nacen sin mutear).
- Click es `role = "click"`; música es todo lo demás, incluido `role = nil`
  (mismo criterio que usa la UI para armar sus dos áreas).
- Es mute a nivel de send, el mismo que alterna la UI (§4); el feed lo
  refleja y la M se pinta sola.
- Viven en `defaults`, así que los `overrides` no las pisan: valen para
  todos los proyectos.
- Si se borra el bus a mano, la próxima corrida lo recrea y vuelve a
  aplicarlas. Un config sin las claves se comporta como antes.

Una edición local del config en una PC de destino se pierde en cada
update de ReaPack: `05_REAPACK_DEPLOY.md`, Pendientes.

## 7. Riesgos

- **Snapshots `SN_*`:** si mutean tracks, ese mute silencia también el
  monitoreo (§3.3). Por ejemplo, `SN_Drums_Muted` dejaría al baterista sin
  batería. Falta ver si los snapshots mutean o bajan volúmenes.
- **Dispositivo cerrado:** con la opción de cerrar el dispositivo por
  inactividad, la API informa 0 salidas y el publish aborta con `no_pair`
  (síntoma: proyecto abierto y después la UI falla, y la UI abierta antes
  funciona). Mitigado con `Audio_Init` (§3.1). Sin verificar: qué pasa si
  otro programa tiene tomado el driver de la placa.
- **Rango de salidas:** si Last output no llega a la 4, el script dirá
  "ninguno disponible" aunque la placa lo tenga.
- **Crear sends en runtime** ensucia Undo y marca el proyecto.
  Mitigación: creación idempotente en un único bloque de Undo, sin crear
  el bus en proyectos sin tracks admitidos (`no_tracks`) ni deducir el par
  si el master no tiene hardware output (`no_pair`).
- **Render:** sin riesgo, el bus no va al master.

## 8. Archivos

- `MonitorMix/Nik_MonitorMix_Publish.lua` — publicador one-shot (§5).
- `MonitorMix/Nik_MonitorMix_EnsureSends.lua` — cáscara para correr
  `MM.ensure_sends` a mano.
- `MonitorMix/MonitorMix_common_logic.lua` — filtro, par secundario,
  `MM.ensure_sends`.
- `MonitorMix/MonitorMix_config.lua` — config en código (§6.5).
- `Tests-Debug/Nik_MonitorMix_ProbeOutputs.lua`,
  `Tests-Debug/Nik_MonitorMix_ProbeBus.lua` — sondas de ruteo (§3).
- `web/musicstate-ui/monitor/monitor.js` — capa cliente de datos (§5).
- Interfaz web: `monitor_mix_ui.md`.

## 9. Pendientes

- **Dos volúmenes maestros** (música y click) para el baterista. Un send
  no tiene volumen de grupo, así que requiere un bus por `role` y por
  músico (ej. `Monitor Bus - Batería - Música` y `Monitor Bus - Batería -
  Click`), ambos con hardware output al mismo par secundario y cada track
  mandando al bus de su `role`. El limitador quedaría repetido en cada
  bus. `buses` en el config pasaría a ser un bus por `role` y por músico.
- **Mute en la mezcla principal:** mutear un track en el remoto del
  coordinador también silencia su send al monitoreo (§3.3). Se quiere que
  el baterista lo siga recibiendo, con la "M" roja visible solo en el
  remoto del coordinador. Sin investigar.
- Validar en sala el ruteo con la U-Phoria (pares 1/2, 2/3, 3/4): salidas
  listadas, `I_DSTCHAN` del master y par resuelto.
- Probar `dirty` y Undo con el proyecto limpio.
- Probar el filtro: `recursive` con subcarpetas, `guid_include`,
  `guid_exclude`, overrides por proyecto y la regla `recvcnt` + `hwoutcnt`
  aislada.
- **Distinguir el motivo de `no_pair`:** hoy el publish informa solo
  `status`, y `no_pair` cubre tres causas: dispositivo sin salidas
  (`GetNumAudioOutputs() == 0`), master sin hardware output y falta de un
  par alineado libre. La UI no puede explicar cuál ocurrió. Agregar un
  campo de motivo al JSON (§5) y documentarlo en la tabla de `status`.
- Pendientes de la interfaz: `monitor_mix_ui.md`.
