# Panel nativo — Semitonos ReaPitch (Stem Bus)

Panel ReaImGui corrido dentro de REAPER (no vía web remote) para controlar
en vivo el semitono de todas las instancias de ReaPitch en los hijos del
Stem Bus, más reset y toggle ON/OFF. Misma funcionalidad que la sección
`nikReaPitchSection` de `fancier.html`, pero sin el viaje por ExtState —
habla directo con la API de REAPER porque corre en el mismo proceso.

## Setup técnico
- REAPER v7.79, ReaImGui, SWS/S&M Extensions, Windows 10.
- Script: `Nik_ReaPitchBus_Knob.lua`, en `Custom/` junto con los módulos
  de lógica compartida.

## Dependencias (lógica centralizada)
- `StemBus_common_logic.lua`: discovery genérico del Bus y sus hijos
  (`find_bus_track`, `get_folder_children`).
- `ReaPitchBus_common_logic.lua`: específico de ReaPitch (`find_reapitch_fx`,
  `find_all_instances()`, `SEMITONE_PARAM`, `semitones_to_normalized`,
  `normalized_to_semitones`). Consume el módulo anterior vía `dofile`.
- Mismos módulos consumidos por `NikRemote_ReaPitch_Read/SetSemitones/
  ToggleEnable.lua` (familia del web remote) — ver `01_CONVENCIONES.md`
  para el patrón de `dofile` y `02_REMOTO_FANCIER_CONTEXTO.md` para el
  detalle de esos tres scripts.

## Funcionalidad
- **Knob de semitonos** (rango -12/+12): arco de progreso + aguja, dibujado
  con `ImGui_DrawList` (círculo simple por ahora, ver "Pendiente" abajo).
  - Interacción: drag vertical (arriba = sube semitonos). `Ctrl` durante
    el drag = modo fino (sensibilidad reducida).
  - Doble click sobre el knob = reset a 0 (mismo efecto que el botón
    Reset).
  - Un solo `Undo_BeginBlock`/`Undo_EndBlock` por gesto completo (no por
    frame).
  - Estados: valor numérico normal, `mixed` (instancias con semitonos
    distintos entre sí — un drag iguala todas al mismo valor), `—` /
    `none` (no hay Bus o ningún hijo tiene ReaPitch).
  - Lectura pasiva: mientras no estás arrastrando, releo el estado real
    cada ~0.3s (throttle simple con `reaper.time_precise()`), así si
    tocás el semitono desde la ventana nativa de ReaPitch el knob se
    actualiza solo. Mientras hay un drag en curso, la lectura pasiva se
    suspende para no pisar el gesto.
- **Botón Reset**: aplica 0 semitonos a todas las instancias.
- **Botón Toggle ReaPitch ON/OFF**: mismo comportamiento que
  `NikRemote_ReaPitch_ToggleEnable.lua` — si no todas están encendidas,
  enciende todas; si ya estaban todas encendidas, apaga todas. Estados
  ON/OFF/mixed/—.

## Bugs encontrados y resueltos durante el desarrollo
- **Ventana aparecía en (0,0)**: faltaba `ImGui_SetNextWindowPos` (solo
  se seteaba el tamaño). Agregado con `Cond_FirstUseEver`, igual que el
  tamaño — solo aplica la primera vez; después REAPER recuerda posición
  y tamaño entre sesiones.
- **Doble click no resetaba de forma estable (volvía al valor anterior)**:
  el segundo click de un doble click deja el item "activo" (mouse
  apretado) durante varios frames más allá del frame donde se detecta el
  doble click. La rama de drag entraba en esos frames siguientes con
  `active=true` y `double_clicked=false`, pisando el reset con un
  `drag_start_value` obsoleto de un gesto anterior. Fix: la rama de drag
  solo corre si `drag_undo_open` está `true`, flag que únicamente se
  activa en un `activated` normal (nunca en la rama de doble click) — así
  un gesto de doble click nunca "cae" en la lógica de arrastre por más
  frames que el botón siga apretado.

## Pendiente
- **Centrado del contenido**: knob y botones quedan apilados a la
  izquierda de la ventana, sin centrar — parte del pulido visual, no
  bloqueante para el uso funcional.
- **Estética "rack de hardware"** (pulido visual, diseño original
  acordado antes de programar):
  - Relleno degradado tipo metal cepillado en el cuerpo del knob (hoy es
    un círculo con color plano).
  - Textura sutil en el panel de fondo (líneas finas horizontales).
  - Posibles rivets/tornillos decorativos en las esquinas.
  - Readout con fuente monoespaciada tipo display LED (hoy usa el texto
    default de ImGui).
- Mismos casos sin probar que en el remoto web (compartido por depender
  de la misma lógica): un hijo con ReaPitch bypasseado antes de correr el
  toggle, y un hijo con más de una instancia de ReaPitch en la cadena.