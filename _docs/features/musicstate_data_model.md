# Feature — MusicState: modelo de datos y protocolo

Contrato de datos de la feature MusicState: qué se publica, con qué
formato, y las reglas de protocolo que cualquier lector o escritor tiene
que respetar. **Punto de entrada de la feature** — leer antes de tocar
cualquiera de los otros docs.

Este doc describe **cómo está hecho hoy**, no cómo se llegó ahí (para eso,
`git log`). Convenciones generales en `01_CONVENCIONES.md` y
`00_CONTEXTO_GENERAL.md`; no se duplican acá.

Documentos relacionados:
- `features/musicstate_client.md`: capa cliente JS (consultas,
  transposición) — para quien construye o extiende una UI.
- `features/musicstate_bridge.md`: puente y publicación (Lua) — para
  quien toca el lado de guardado/publicación.
- `features/musicstate_helper.md`: el panel ReaImGui de carga.
- `features/musicstate_instrumentista.md`: UI de instrumentista
  (prompter), modelo de sincronización con el transporte.
- `07_RED_SALA_ENSAYO.md`: diagnóstico e infraestructura de red para la
  sala (no es parte de esta feature, pero la UI de instrumentista
  depende de que la red aguante).
- `08_REAIMGUI_PATTERNS.md`: patrones y gotchas de ReaImGui usados en el
  Helper, no específicos de esta feature.
- `REAPER Musical Metadata & Web Controller — Specification.md`: spec
  conceptual original (objetivo y arquitectura, sin editar).

## 1. Objetivo y principios

Tres capas, cada una con una sola responsabilidad:

1. **Carga:** el Helper (panel ReaImGui) guarda los datos en el proyecto.
2. **Publicación:** un script one-shot copia esos datos a un store que el
   servidor web de REAPER puede leer.
3. **Consumo:** el cliente JS resuelve, en cada tick de su poll, qué acorde,
   sección o indicación corresponde a la posición actual.

**Sin scripts residentes.** Todo el mecanismo del lado REAPER es
*one-shot*: se dispara, escribe `ExtState` y termina; el cálculo por
posición vive en el cliente. Si nadie tiene abierta una UI web, no corre
nada de esta feature (mismo patrón que `tempo_map`, publicado por
`Nik_Playrate_ReadTempoMap.lua`). El único proceso residente es el propio
Helper mientras el usuario lo tiene abierto.

**Los datos se publican sin transponer.** El servidor publica acordes y
tonalidad tal como fueron cargados; la transposición por semitonos de
ReaPitch la aplica el cliente al leer (ver `musicstate_client.md` §2).


## 2. Flujo de datos y keys

```
Helper (ReaImGui) ── guarda ──► ProjExtState  NSAUDIOMUSIC/<key>
                                (dentro del .rpp, por proyecto)
                                        │
             Nik_MusicState_PublishAll.lua (one-shot, vía Bridge)
                                        ▼
                             ExtState global  NikMusicState/<key>
                                        │  GET/EXTSTATE (web control)
                                        ▼
        Cliente JS: core/music-state.js ──► UIs (prompter, ...)
```

| Key | ProjExtState (`NSAUDIOMUSIC`) | ExtState global (`NikMusicState`) | Contenido |
|---|---|---|---|
| `harmony_data` | sí | sí | eventos de acorde por compás (§4.1) |
| `project_key` | sí | sí | tonalidad del proyecto (§4.2) |
| `project_roles` | sí | sí | lista de roles de intérprete (§4.3) |
| `cues_data` | sí | sí | indicaciones por rol (§4.4) |
| `publish_version` | sí | sí | contador entero que el Helper incrementa en cada "Guardar y Publicar"; el cliente lo usa para detectar datos nuevos (ver `musicstate_bridge.md` §5) |

Además, la capa cliente consume dos keys que **no** pertenecen a este
namespace: `NikRemote/tempo_map` y `NikRemote/timesig_map` (§4.5).

`ProjExtState` es por proyecto y persiste en el `.rpp`. `ExtState` es un
store **global**, compartido por todos los proyectos abiertos: no
distingue a qué proyecto pertenece lo que guarda (consecuencia para el
puente en `musicstate_bridge.md` §1).


## 3. Gotchas de protocolo

**`GET/EXTSTATE` no lee `ProjExtState`.** El web control de REAPER solo
lee el `ExtState` global. Un dato guardado en `ProjExtState` (lo correcto
por ser por proyecto) es invisible para el cliente hasta que un script lo
copia a `ExtState`. De ahí el puente. Reproducible con
`Tests-Debug/Nik_Tests_ExtStateProbe.lua`, que escribe el mismo valor en
ambos stores y compara lo que devuelve el endpoint.

**El web control escapa los saltos de línea.** Un valor con saltos de
línea reales vuelve como `\n` literal (dos caracteres), porque el
protocolo es una línea por registro
(`EXTSTATE\t<ns>\t<key>\t<valor>`). Regla: todo valor que se publique
para este mecanismo se arma **compacto en una sola línea** en el script
Lua, sin whitespace ni saltos; no se confía en que el cliente limpie el
escape. Mismo criterio que los strings planos de `tempo_map` y
`timesig_map`.


## 4. Modelo de datos

Convenciones comunes: los compases son **1-indexed**; las posiciones
dentro de un compás se expresan en **`qn_offset`** (negras desde el
downbeat del compás) con grilla de 0.25 (semicorchea, independiente del
compás).

### 4.1. `harmony_data`

JSON compacto en una sola línea, keyed por número de compás (string),
con un array de eventos por compás:

```json
{"12":[{"qn_offset":0.0,"chord":"Cmaj7"},{"qn_offset":2.5,"chord":"Dm7"}],"13":[{"qn_offset":0.0,"chord":"G7"},{"qn_offset":3.75,"chord":"Cmaj7"}]}
```

- Un solo JSON (no una key por compás) para que sea un único pedido y
  encaje con el poll existente.
- `qn_offset` en vez de beat + subdivisión: no depende del denominador,
  así que cubre compases simples, compuestos e irregulares (5/4, 7/8,
  5/8) sin casos especiales ni validación de rango por tipo de compás.
- **Sparse por diseño:** hay una entrada solo donde el acorde cambia. Un
  compás sin entrada propia hereda el acorde anterior (carry-over, lo
  resuelve el cliente, `musicstate_client.md` §1.2).
- **`"chord": null` es silencio explícito:** corta el carry-over. Se
  guarda sin comillas.

**Convención de autoría.** Una sección todavía sin armonía cargada debe
empezar con una fila de silencio explícito (acorde vacío, que el Helper
guarda como `null`). Sin ella, el carry-over sigue repitiendo el acorde
anterior compás a compás hasta el próximo evento real, y no hay forma de
distinguir "sostenido a propósito" de "sección sin cargar": ambos se ven
igual (ausencia de eventos en el medio).

### 4.2. `project_key`

```json
{"tonic":"G","mode":"major"}
```

`mode` es `major` o `minor`, sin casos exóticos. La tónica se guarda con
la grafía que eligió el usuario (Db y C# son tonalidades distintas en
notación real aunque suenen igual); no se normaliza ni se deriva.

### 4.3. `project_roles`

Array de strings, lista de roles de intérprete **configurable por
proyecto**:

```json
["coordinador","cantantes","guitarristas","bajistas","bateria","organo"]
```

No está atada a los nombres de track de los stems: el stem `Other` varía
de canción a canción (puede ser órgano, vientos, etc.), y por lo tanto el
rol también. `"todos"` **no** forma parte de la lista: es un valor
reservado, siempre disponible como destinatario de una indicación sin
configurarlo por proyecto.

### 4.4. `cues_data`

Indicaciones para intérpretes. A diferencia de un acorde ("estado siempre
vigente"), cada una es un evento con inicio y fin propios. Mismo keyed por
compás que `harmony_data`:

```json
{"12":[{"qn_offset":0.0,"roles":["cantantes"],"text":"respirar","duration_qn":2.0}]}
```

- `roles`: array de strings; puede apuntar a más de un rol
  (`["guitarristas","bajistas"]`) o a `["todos"]`.
- `duration_qn`: duración en negras desde `qn_offset`. La indicación está
  activa en el intervalo `[inicio, inicio + duration_qn)`, medido en QN
  **absoluto**, así que puede cruzar el límite de un compás sin caso
  especial. La misma duración cae en lugares distintos según el compás:
  2 QN cortan a mitad de un compás 4/4 (beat 3) y justo en el downbeat del
  siguiente en un 2/4.
- El apagado es **por duración explícita**, fijada al crear la
  indicación. Se descartaron "hasta la próxima indicación del mismo rol" y
  "hasta el siguiente marker".
- La grilla de 0.25 es un requisito de **posición** (`qn_offset`), no de
  duración: `duration_qn` es libre. Ningún consumidor asume que caiga en
  la grilla.

### 4.5. Mapas de tempo y de compás

Los publica `Nik_Playrate_ReadTempoMap.lua` (un solo script, dos keys),
disparado on-demand (boot, cambio de proyecto, popup de Playrate), no en
el poll de fondo. Funciona sobre el proyecto activo aunque no esté
guardado.

**`NikRemote/tempo_map`:** `pos1:bpm1,pos2:bpm2,...`, posiciones en
segundos, orden ascendente. Genera una entrada por cada tempo/time-sig
marker (un cambio de compás sin cambio de tempo repite el bpm; el cliente
solo usa el bpm). Sin markers: un único punto en `pos=0` con
`Master_GetTempo()`. No lleva flag de rampa: en un cambio gradual el
cliente usa el bpm del marker de inicio.

**`NikRemote/timesig_map`:** `compás1:num1:den1,compás2:num2:den2,...`.

- El compás va 1-indexed; la API (`measurepos` de
  `GetTempoTimeSigMarker`) es 0-indexed y el script suma 1. `measurepos`
  es confiable y monotónico.
- Se agrega una entrada solo cuando el marker declara un cambio real de
  compás: la API devuelve `tnum = -1, tden = -1` en los markers puramente
  de tempo. El filtro correcto es `tnum ~= -1`.
- **Siempre hay una entrada en el compás 1.** Si el primer marker con
  cambio de compás está más adelante, o no existe ninguno, el script
  siembra la entrada inicial con `TimeMap_GetTimeSigAtTime(proj, 0)`. (No
  usar `GetProjectTimeSignature2`: devuelve `(bpm, bpi)`, no `(num, den)`.)
  Sin esa entrada, el cliente asigna a los compases iniciales el compás
  del primer marker.

La duración de un compás en QN es `numerador × (4 / denominador)`. Con
este mapa cada compás resuelve su propia duración, así que los cambios de
métrica a mitad de canción no necesitan tratamiento aparte.

### 4.6. Relación con la posición del transporte

El `TRANSPORT` de REAPER entrega la posición como `compás.beat.centésimas`
(`tok[5]`), donde el beat está en unidades del **denominador** del compás,
no siempre negras:

```
qn_offset = (beat − 1 + centésimas / 100) × (4 / denominador)
```

Verificado en 2/4, 4/4 y 6/8, y en ambas direcciones (posición → QN en el
cliente, QN → beat en el Helper). El resultado tiene un pequeño error de
redondeo porque el display de REAPER trunca a centésimas.


## 5. Cómo testear

### 5.1. Protocolo `ProjExtState` → `ExtState`

`Tests-Debug/Nik_Tests_ExtStateProbe.lua` es la herramienta para
reproducir problemas de protocolo (§3): escribe el mismo valor en
`ProjExtState` y en `ExtState` y compara lo que devuelve el endpoint del
web control. Útil para confirmar de entrada si un dato "no llega" es un
problema de protocolo, del puente (`musicstate_bridge.md` §1) o de otra
capa.

### 5.2. Qué mirar cuando "el dato no llega" a una UI

En este orden, de más a menos probable:

1. `config.local.js` desactualizado o ausente en esa PC (Command IDs
   viejos, `NIK_LUA_COMMANDS.musicStatePublishAll` sin resolver).
2. Caché del navegador (recarga forzada antes de sospechar del código,
   mismo gotcha que en `musicstate_instrumentista.md`).
3. El puente nunca corrió para ese proyecto (nadie disparó
   `PublishAll`/"Guardar y Publicar" desde que se abrió esa pestaña) —
   ver `musicstate_bridge.md` §2-3.
4. Valor realmente vacío del lado `ProjExtState` (proyecto sin datos
   cargados, o "sin guardar" — el puente limpia el global a propósito en
   ese caso, `musicstate_bridge.md` §1).

Pruebas de round-trip completo (cargar en el Helper → publicar → leer en
el cliente) están en `musicstate_bridge.md` §6, porque ejercitan el
Helper y el puente juntos.

## 6. Pendientes de esta capa

Ningún bug de protocolo o de modelo de datos sin corregir hoy. Los
pendientes de la feature están repartidos por capa, en el doc que los
toca resolver:

- `musicstate_client.md` §4: bug de grafía con delta 0 en la
  transposición.
- `musicstate_bridge.md`: sin pendientes propios hoy.
- `musicstate_helper.md` §9: header `@provides` desactualizado, backlog
  de UX (Cues sin sticky header, highlight sin calibrar, diccionario de
  color de secciones compartido, glitch de Enter en Roles).
- `07_RED_SALA_ENSAYO.md`: router propio para la sala, todavía sin armar.
- `musicstate_instrumentista.md` §11: prueba de estrés en la sala, delta
  de lookahead por tempo, validación en compases no x/4, selector de rol
  en la UI, layout horizontal.
