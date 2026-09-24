# Feature — MusicState: publicación y puente (Lua)

Cómo los datos que carga el Helper llegan al `ExtState` global que el web
control de REAPER puede servir. Relevante al tocar el guardado, la
publicación, o el ciclo de vida por cambio de proyecto. El formato de
cada dato está en `musicstate_data_model.md` §4, no se repite acá.

Este doc describe **cómo está hecho hoy**, no cómo se llegó ahí.

## 1. El puente (`MusicStateBridge_common_logic.lua`)

Módulo compartido en `MusicState/` (no en `_Shared/`, ver
`01_CONVENCIONES.md`: hoy solo lo consumen scripts de este dominio).
Centraliza el copiado `ProjExtState → ExtState` para que el Helper y
`PublishAll` no dupliquen la lógica.

- `M.NAMESPACE = "NSAUDIOMUSIC"` (ProjExtState, por proyecto),
  `M.BRIDGE_NAMESPACE = "NikMusicState"` (ExtState global).
- `M.KEYS`: las cinco keys de `musicstate_data_model.md` §2, en orden fijo.
- `M.bridgeKey(proj, key)`: copia una key. **Si no hay dato para ese
  proyecto, borra la key del lado global** (`DeleteExtState`) en vez de
  dejar pegado el valor del proyecto anterior. Sin este borrado, un
  proyecto nuevo sin datos propios (pestaña "sin guardar") heredaría los
  valores de la sesión anterior, silenciosamente.
- `M.bridgeAll(proj)`: recorre `M.KEYS` con `bridgeKey`, devuelve cuántas
  se copiaron y cuáles fallaron.

## 2. `Nik_MusicState_PublishAll.lua`

One-shot, sin generar datos: el Helper es la única fuente de verdad de
las cinco keys. El script llama a `Bridge.bridgeAll(proj)` y reporta por
consola cuántas se copiaron. Cubre el caso en que el puente global quedó
desactualizado sin que el Helper haya vuelto a guardar nada (por ejemplo,
un cambio de pestaña de proyecto): un refresco de puente, no una carga de
datos. Se dispara on-demand (conexión de UI, cambio de proyecto), igual
que `Nik_Playrate_ReadTempoMap.lua`; no vive en el poll de fondo.

## 3. Guardado desde el Helper (`nikMusicStateSaveAndPublish`)

El botón "Guardar y Publicar" arma los cinco JSON compactos (`musicstate_data_model.md`
§4) a partir
del estado en memoria del Helper (`H.key`, `H.roles`, `H.harmony`,
`H.cues`) y hace su propio ciclo de guardado, **sin pasar por
`PublishAll`**:

1. Convierte cada fila de `H.harmony`/`H.cues` (compás + beat +
   centésimas) a `qn_offset` con `nikMusicStateBeatToQnOffset`, agrupa por
   compás y ordena por `qn_offset` dentro de cada uno — mismo formato que
   consume el cliente (`musicstate_data_model.md` §4.1, §4.4). Un acorde
vacío se escribe como
   `null` (silencio explícito).
2. Incrementa `H.publish_version` (`(H.publish_version or 0) + 1`).
3. Escribe las cinco keys en `ProjExtState` (`SetProjExtState`).
4. Puentea las cinco, una por una, con `Bridge.bridgeKey` (no
   `bridgeAll`, aunque el efecto es el mismo).
5. `H.save_status` refleja el resultado: `'Guardado OK.'` solo si las
   cinco copias devolvieron `true`.

`publish_version` se carga al abrir el Helper
(`nikMusicStateLoadFromProjExtState`, desde `ProjExtState`, default 0 si
no hay dato) y solo se incrementa al guardar; no cambia por edición en
memoria sin publicar.

## 4. Ciclo de vida por proyecto

**Lado Helper:** en cada iteración del loop, si `reaper.EnumProjects(-1)`
difiere de `H.last_proj`, recarga todo desde `ProjExtState` del proyecto
activo (`nikMusicStateLoadFromProjExtState`) y actualiza `H.last_proj`.
Es detección por polling dentro del propio loop de ImGui, no un callback
de REAPER.

**Lado cliente:** el reset y re-pedido al detectar cambio de proyecto, y
la limitación de que `ExtState` es un store global sin ninguna forma de
etiquetar a qué proyecto corresponde una respuesta, están descritos en
`features/musicstate_instrumentista.md` §6 (ciclo de vida por proyecto) y
no se duplican acá.

## 5. `publish_version` y refresco automático

Sirve para que una UI abierta detecte que hay armonía nueva sin necesitar
que el músico recargue la página. El cliente guarda el último valor
visto y compara: si cambió, vuelve a pedir las cuatro keys de datos con
`nikMusicStateRequestAll()`. El valor se resetea a `null` en cada cambio
de proyecto para que la comparación nunca cruce entre proyectos (detalle
de esa lógica, en `features/musicstate_instrumentista.md` §6).

Como el store de publicación es global y no versionado por proyecto,
`publish_version` tampoco distingue proyectos por sí solo: un valor de 5
en el proyecto A y un valor de 5 en el proyecto B se ven idénticos para
el cliente. Lo que evita una lectura cruzada es que el reset del cambio
de proyecto ya dispara un `nikMusicStateRequestAll()` propio (§4); el
chequeo de `publish_version` es una capa aparte, para el caso de que la
armonía cambie mientras la UI ya está conectada al proyecto correcto.


## 6. Cómo testear: round-trip manual

Con el Helper (`musicstate_helper.md`) y `nsaudio_musicstate_test.html`
(o la consola del navegador) abiertos a la vez:

1. Cargar un acorde, una sección con markers y una cue de prueba.
   "Guardar y Publicar".
2. Verificar en consola: `JSON.parse` de cada `EXTSTATE` de
   `NikMusicState/*` debe reflejar lo cargado, con `qn_offset` coherente
   con la fórmula de `musicstate_data_model.md` §4.6.
3. Editar el mismo dato desde el Helper (por ejemplo, mover un acorde de
   compás) y volver a "Guardar y Publicar" sin recargar el cliente: el
   `publish_version` debe subir y, si `nikMusicStateRequestAll()` corrió
   por la UI, los datos deben refrescarse solos (§5).
4. Cambiar de pestaña de proyecto en REAPER y volver: `H` del Helper debe
   recargarse con los datos de cada proyecto (§4), sin arrastrar nada del
   anterior.

Protocolo de bajo nivel (`Nik_Tests_ExtStateProbe.lua`) y qué mirar
cuando un dato no llega a ninguna UI: `musicstate_data_model.md` §5.

## 7. Pendientes

Sin pendientes propios de esta capa hoy. El header `@provides` del
Helper, que afecta al empaquetado de `MusicStateBridge_common_logic.lua`
y `MusicStateRowInputs_common_logic.lua` vía ReaPack, está anotado en
`musicstate_helper.md` §9 (es el header del script del Helper, aunque el
bug afecte a estos dos módulos).
