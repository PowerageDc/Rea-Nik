# VstiControl — keyswitches y curvas CC por VSTi

UI ReaImGui que inserta en el MIDI Editor activo keyswitches y curvas de CC (o
de pitch wheel) para controlar un VSTi. Cada botón arma los eventos a partir de
la posición del cursor y, según el control, de la selección de tiempo o de
notas. Los controles de cada VSTi salen de un config en código
(`VstiControl_<Vsti>_config.lua`, ver `01_CONVENCIONES.md`); el motor y la UI
son comunes a todos. La UI resuelve la inserción: los ajustes finos se siguen
haciendo en el piano roll.

## 1. Scripts

Carpeta `C:\dev\Rea-Nik\VstiControl\`.

| Script | Qué hace |
|---|---|
| `Nik_VstiControl_ModoBass.lua` | Abre la UI con el config de MODO Bass 2 |
| `Nik_VstiControl_AmpleGuitar.lua` | Abre la UI con el config de Ample Guitar (probado con Luthier; sirve de base para los demás modelos) |

Cada wrapper carga `VstiControlUi_common_logic.lua` y el config de su VSTi, y
llama a `run(cfg)`. La ventana queda en `defer` hasta cerrarla. Registro: un
wrapper por VSTi en el Action List.

Módulos de soporte (solo `dofile`, no se registran):

| Módulo | Rol |
|---|---|
| `VstiControl_common_logic.lua` | Motor: `get_context`, `exec(cfg, spec)`, planners por tipo de spec, `note` (nombre de nota a MIDI), `describe_source`, `value_at_cursor` |
| `VstiControlMap_common_logic.lua` | Cálculo sin ImGui: `scale_to_raw`, `raw_to_scale`, `position_value`, `position_spec` |
| `VstiControlUi_common_logic.lua` | Ventana ReaImGui: `run(cfg)` |

Configs: `VstiControl_ModoBass_config.lua` y `VstiControl_AmpleGuitar_config.lua`.

Compartidos en `_Shared/`: `ImGuiButtonStyle_common_logic.lua` (estilo de
botones) e `ImGuiHostFocus_common_logic.lua` (`toHwnd` devuelve el foco del
teclado al MIDI Editor).

Sonda: `Tests-Debug/Nik_VstiControl_ProbeInsert.lua` ejecuta una spec del motor
sin UI (se elige con la constante `TEST`). Sirve de regresión manual al tocar
`VstiControl_common_logic.lua`.

Dependencias: ReaImGui, y SWS (`BR_Win32_SetFocus`) o js_ReaScriptAPI para
devolver el foco. Hace falta un MIDI Editor abierto con un item MIDI para que un
botón inserte.

## 2. Config del VSTi

Un archivo por VSTi que devuelve una tabla. El mapa de controles de cada VSTi
vive ahí, no en este doc.

| Campo | Valor |
|---|---|
| `name` | Título de la ventana |
| `channel` | Canal MIDI, 1 a 16 (1 por defecto) |
| `middle_c` | Octava con la que el VSTi nombra el MIDI 60. REAPER usa 4; los dos VSTi implementados usan 3 |
| `defaults` | `ks_offset` (ticks, 0), `ks_length` (ticks, 60), `ks_velocity` (100), `ramp_shape` (`"linear"`), `ramp_tension` |
| `groups` | Lista de `{ title, controls }` |

Cada control tiene un `kind`:

| `kind` | Campos |
|---|---|
| `ks` | `label`, `pitch` (nombre de nota o número), `steps` (lista de `{ pitch, offset, length, velocity }`), `offset`, `stagger`, `length`, `velocity`, `channel`, `mode` (fija el modo; sin él rige el selector de la UI), `variants` (lista de `{ label, ... }` que pisan campos del control) |
| `cc` | `label`, `cc` (número, o `"pw"` para pitch wheel), `min` y `max` (0 y 127; -8192 y 8191 en `"pw"`), `scale`, `presets` (lista de `{ label, value }` en valor crudo) |
| `position` | `label`, `count`, `first` (número visible de la primera posición, 1 por defecto) y `via`: `"cc"` con `cc`, `step` y `values`, o `"ks_pair"` con `enable`, `base`, `lead`, `stagger` y `offset` |

`scale` convierte unidades a valor crudo: `{ center, unit, neg, pos }`, con
`neg` y `pos` las unidades que abarcan el extremo inferior y el superior.

Precedencia: campo del control, después slider de la UI (reemplaza el valor de
`defaults`), después `defaults` del config, después el valor por defecto del
motor.

```lua
{ kind = "cc", label = "Bend", cc = 5, min = 0, max = 127,
  scale = { center = 64, unit = "st", neg = 4, pos = 4 } }
```

## 3. Comportamiento

### Contexto y validación
- El editor activo se resuelve en cada clic (`get_context`): `MIDIEditor_GetActive`
  devuelve el editor aunque el foco esté en la ventana de ImGui. Sin editor o
  sin take MIDI, avisa y no inserta.
- Cursor y selección de tiempo se pasan a PPQ del take y se redondean al tick.
- Cada botón planifica primero todos sus eventos. Si alguno queda fuera del
  item (antes del inicio o desde el final), no inserta nada y lo avisa: la
  validación es del botón completo.
- Un botón es un bloque de undo (`VstiControl: <label>`). Las notas se insertan
  con `noSort` y el take se ordena una vez; si hubo shapes de curva se ordena de
  nuevo después de asignarlas.

### Keyswitches
- Posición de cada step: ancla + `offset`, con el `offset` base más
  `(i - 1) * stagger` salvo que el step traiga el suyo. `offset` en ticks, negativo
  = antes del ancla; con `steps` se componen keyswitches conjuntos, anticipados
  y escalonados.
- `pitch` acepta nombre de nota: `60 + (octava - middle_c) * 12 + semitonos`,
  con `#` y `b`.
- Tres modos (selector de la UI, o `mode` fijo en el control):

| Modo | Ancla y largo |
|---|---|
| `cursor` | Una nota en el cursor, de `length` ticks |
| `per_note` | Una nota de `length` ticks en cada inicio distinto de la fuente |
| `range` | Una nota larga desde el inicio de la fuente hasta su final (se recorta al final del item); `length` no se usa |

- Fuente de `per_note` y `range`: las notas seleccionadas si hay (en `range`, del
  primer inicio al último final); si no, la selección de tiempo (en `per_note`,
  las notas que empiezan dentro); si no hay ninguna, avisa. El `offset` mueve
  solo el inicio en `range`. No se filtran notas muteadas ni canal. El mensaje de
  resultado nombra la fuente usada.

### CC y pitch wheel
- `cc_point`: un evento en el cursor, más `offset`.
- `cc_ramp`: dos eventos, en el inicio y el final de la selección de tiempo (sin
  selección, avisa). El primero lleva la curva (`linear`, `slow`, `fast_start`,
  `fast_end`, `bezier` o `square`) y, para `bezier`, la tensión (-1 a 1).
- Pitch wheel (`cc = "pw"`): el valor va centrado, de -8192 a 8191, y se envía
  como valor de 14 bits (`valor + 8192`). El lane del editor muestra el valor
  crudo.
- `value_at_cursor`: último evento de ese control en el canal del config, en o
  antes del cursor, sin interpolar la curva. Para pitch wheel lo devuelve
  centrado.

### Escala y posiciones
- `scale_to_raw`: con `u >= 0`, `center + (u / pos) * (max - center)`; con
  `u < 0`, `center + (u / neg) * (center - min)`. Se redondea y se limita a
  `min` y `max`. `raw_to_scale` es la inversa. Los presets quedan en valor crudo.
- `position` vía `cc`: un punto de CC con el centro del tramo de la posición,
  `round((p - 0.5) * step)`; `step` por defecto es `128 / count`. `values` fija
  los valores a mano.
- `position` vía `ks_pair`: dos notas, la que habilita el modo (`enable`) y la
  de la posición (`base + p - 1`). La segunda cae `lead` ticks antes del ancla
  (1 por defecto), más el `offset`; la primera, `stagger` ticks antes que la
  segunda (1 por defecto). Usa el modo de keyswitch vigente.

## 4. UI

Ventana de ReaImGui con la raíz en `WindowFlags_NoNav` y el contexto en
`config_flags = 0`. De arriba abajo:

| Zona | Contenido |
|---|---|
| Modo KS | Cursor, Por nota, Rango |
| Parámetros | Sliders Offset (-240 a 240), Largo (1 a 960) y Vel (1 a 127), que reemplazan los `defaults` del config en vivo; combo de curva y slider de tensión (deshabilitado salvo con `bezier`) |
| Estado | Línea con el resultado del último botón (verde o rojo) y, fuera del modo Cursor, la fuente vigente (se refresca cada `SOURCE_REFRESH_S`) |
| Grupos | Un bloque por grupo del config |

Dentro de un grupo, en este orden:
- `ks` sin `variants`: botones en flujo (`KS_BUTTON_W`).
- `ks` con `variants`: tabla con un botón por variante, que inserta el keyswitch
  con los campos de la variante.
- `cc`: tabla con sliders Desde y Hasta (en unidades si hay `scale`), `<>`
  (intercambia), Tomar (carga en Desde el valor del cursor), Punto (usa Desde),
  Rampa (Desde a Hasta) y los `presets`. Desde arranca en 0 y Hasta en
  `scale.pos` o `max`.
- `position`: slider de `first` a `first + count - 1` y Aplicar.

Foco: `return_focus_if_idle` le devuelve el foco al MIDI Editor
(`toHwnd(MIDIEditor_GetActive())`) cuando termina cualquier interacción
(`IsAnyItemActive` pasa a falso) y cuando la ventana tiene el foco y el mouse
salió de ella; nunca con un ítem activo ni con un popup abierto. La constante
`RETURN_FOCUS_TO_EDITOR` lo apaga. Patrones de ReaImGui aplicados (sliders en
vez de `InputInt`, IDs con `PushID`, líneas reservadas, `BeginDisabled`):
`08_REAIMGUI_PATTERNS.md`.

## 5. Notas por VSTi

### MODO Bass 2
- Los nombres de nota del plugin están una octava por debajo de REAPER (A-1 en
  el plugin es A0 en el editor): `middle_c = 3`.
- El latch del plugin es un switch: con latch en on, un keyswitch corto cuenta
  como apretado hasta su próxima aparición. Se usa en off, así que un keyswitch
  vale mientras suena. Para forzar una cuerda hay dos formas: uno corto por nota
  (modo `per_note`) o uno largo sobre toda la frase (modo `range`).
- Bend (CC 5): 4 semitonos fijos, centro en 64. Slide (pitch wheel): 12
  semitonos equivalen a 8192 hacia cada lado.
- Posición de mano izquierda (CC 4): cada posición abarca unos 5,3 valores de CC
  (`posición = min(17, floor(CC / 5.3) + 1)`) y la 17 arranca en CC 85, de ahí
  `step = 5.3`. Medido con las posiciones 3, 5, 7, 9, 11 y 13.
- Legato Slide (CC 65), Let Ring (CC 64) y Chord Mode (CC 2) llevan presets On y
  Off en 127 y 0.

### Ample Guitar
- Los nombres de nota del plugin están una octava por debajo de REAPER
  (`middle_c = 3`).
- Legato Slide, Hammer-On / Pull-Off y la asignación de cuerda (G0 a C1, cuerda
  6 a 1) cambian la posición de mano izquierda con velocity mayor a 63; Open
  String First es on con velocity mayor a 63 y off con menor. De ahí las
  `variants`.
- Palm Mute: a menor velocity, mayor profundidad del apagado; se controla con el
  slider Vel.
- Stroke Noise es on/off por CC 15 y Vibrato Wheel es el CC 1 (0 sin vibrato).
- Posición: el par C#1 (habilita el modo) y una nota de E1 a G#2 (17 posiciones,
  mostradas de 0 a 16). La segunda nota tiene que empezar 1 tick antes del
  ancla; si no, no funciona.
- Bend por pitch wheel; el rango de semitonos del plugin es configurable y
  tiene que coincidir con `scale.neg` y `scale.pos`.
- Los FX (F5 a G6) son notas sueltas: llevan `mode = "cursor"` para ignorar el
  selector.

## 6. Decisiones

- **Dominio propio, separado de MidiEdit:** MidiEdit modifica lo seleccionado
  sin UI; este dominio inserta eventos nuevos desde una UI. Se descartó `Keys`
  como nombre (en `MusicStateKeys_config.lua` significa atajos de teclado, y el
  dominio también cubre curvas).
- **Motor, cálculo y UI separados:** el motor no conoce ImGui y la matemática de
  escala y posiciones vive en su módulo; un VSTi nuevo es un config y un wrapper.
- **El config declara datos, la UI decide el comportamiento por `kind`:**
  un tipo nuevo agrega un dibujo y una forma de compilarse a specs del motor,
  sin tocar el motor (el par de posición de Ample reutiliza `steps`).
- **Editor resuelto en cada clic:** el handle de un MIDI Editor cambia al
  cerrarlo y reabrirlo, y `MIDIEditor_GetActive` responde también con el foco
  en ImGui (medido con un editor flotante).
- **Validación atómica:** si un evento queda fuera del item no se inserta
  ninguno, para no dejar un keyswitch sin su par.
- **Rampa de dos puntos con curva nativa:** menos eventos y editable en el
  piano roll, en vez de puntos densos.
- **Fuente única con prioridad fija:** notas seleccionadas antes que selección de
  tiempo, con la fuente a la vista en la UI para que no sorprenda.
- **Foco devuelto en vez de reenviar teclas:** ReaScript no ofrece una forma
  limpia de reinyectar un press en el editor, y declarar teclas una por una
  (como el despacho del Helper de MusicState) no escala a "casi todas". Devolver
  el foco al terminar cada interacción deja los atajos del editor funcionando.
- **`middle_c` en el config:** cada VSTi nombra las octavas a su manera.
- **Un wrapper por VSTi:** `Nik_VstiControl_<Vsti>.lua` usa el VSTi donde otros
  scripts llevan un verbo; excepción documentada en `01_CONVENCIONES.md`.
- **Sin ReaPack por ahora:** el dominio es de uso local.

## 7. Pendientes

- Config por modelo de Ample: un archivo que cargue la base y cambie solo lo
  necesario, con un helper para buscar un control por nombre. Primer caso, el
  SJ200: el Palm Mute sigue en D0, pero con velocity alta es palm mute y con
  baja es nota muerta.
- Verificar en MODO Bass los presets On y Off (127 y 0) de Legato Slide, Let
  Ring y Chord Mode, que son valores de partida sin confirmar. Los keyswitches de
  force string no mostraron diferencia entre velocity alta y baja.
- Verificar las velocities de las variantes de Ample (40 mantiene y 100 cambia la
  posición; 100 y 30 en Open String First) y el `stagger` del par de posición en
  otros modelos.
- Definir el rango de semitonos del Bend de Ample (hoy 4 en `scale.neg` y
  `scale.pos`) y alinearlo con el plugin.
- Alta en ReaPack si el dominio llega a otras PCs.

### Ideas

- Mostrar el valor crudo resultante junto a cada slider con `scale`, para
  cruzarlo con el lane.
- Validar el config al cargarlo (pitch inválido, tipo desconocido, campos que
  faltan): hoy el error aparece al hacer clic o el control se ignora.
- Presets en unidades cuando hay `scale` (hoy van en valor crudo).
- Posición vía `cc`: botón Tomar y rampa entre dos posiciones.
- Reemplazar en vez de sumar: quitar keyswitches o CC existentes del mismo
  control en el rango antes de insertar, y un botón de limpieza del rango.
- Clamp opcional al inicio del item cuando un offset negativo deja un evento
  antes de él (hoy se rechaza el botón entero).
- Filtro por canal y por notas muteadas en los modos `per_note` y `range`.
- Selector manual de la fuente (notas o selección de tiempo).
- Acciones one-shot para los controles más usados, asignables a atajos, sobre el
  mismo motor.
- Plan B de foco si la regla actual no alcanza: ventana sin activación
  (`WS_EX_NOACTIVATE`) con js_ReaScriptAPI, sin probar.