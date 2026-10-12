# WIP — MusicState: siguientes etapas (después del Paso 6)

Documento de trabajo para retomar en conversaciones nuevas. **No describe
cómo está hecho hoy** (eso vive en `features/musicstate_keys.md`,
`musicstate_helper.md` y `08_REAIMGUI_PATTERNS.md`): describe qué sigue, qué
se decidió y cómo está partido el trabajo. Se adelgaza solo: al cerrar una
etapa, lo aprendido pasa a los docs de feature y su mini-spec se borra.

## 1. Reglas fijas

- Resolver por pasos, esperando confirmación antes de avanzar al siguiente.
  Advertir antes de escribir más de 300 líneas de código.
- Al debuguear o cambiar código existente: nunca regenerar archivos
  completos. Diffs en formato buscar/reemplazar, con las indicaciones fuera
  del bloque; cerca de 4 backticks si el bloque contiene triple backtick.
  Mismo método para actualizar `.md`.
- Ver el archivo fuente real antes de proponer un fix. Sondas temporales con
  `ShowConsoleMsg` antes de tocar lógica si la causa no está medida.
- Commits: Conventional Commits, tipo y dominio en inglés, resto en español
  sin tildes, multilínea. Código y docs en commits separados.
- Al cerrar cada etapa: diffs a los docs de feature, bloque de cierre (§8) y
  commit. Los patrones genéricos de ReaImGui van a `08_REAIMGUI_PATTERNS.md`.
- Subir siempre: este archivo, `musicstate_keys.md` y
  `MusicStateKeys_common_logic.lua`, más los de la etapa (tabla de §4). El
  Proyecto trae `00` y `01` como copias de solo lectura: resubirlos si
  cambiaron en el repo.

## 2. Estado de partida

Hecho y commiteado: Pasos 1 a 5 y 6a a 6c del refactor de atajos (`Keys.input`,
anillo de foco con Tab y Shift+Tab, repetición, flechas por perfil; en
Armonía: Acorde mueve de fila, Compás, Beat y Cent. cambian el valor).
Docs al día: `musicstate_keys.md` §4.6, §4.7 y §9; `08` §2, §3, §7;
`musicstate_helper.md` §1, §5, §9. Sonda de teclas en
`Tests-Debug/Nik_Test_KeyProbe.lua`.

## 3. Decisiones tomadas

| Tema | Decisión |
|---|---|
| Anillo de foco | Por tab; orden por defecto = dibujado, `ring_config` con orden propio; sin wrap-around; foco aplicado el frame siguiente; destino por identidad `(owner, col)` |
| `SetKeyboardFocusHere` | `0` antes del widget (`ring_focus`); `-1` después solo en `InputText` |
| Cambio de valor con `InputInt` activo | ID versionado (`row._ver_<campo>`) + refoco con `hold`; `ring_item` va después de volcar el valor |
| Perfil por input | `{ on_up, on_down }` declarado por input; cada tab decide qué hacen las flechas |
| Enter y Esc | Cierran el campo (los resuelve ImGui); `keep_focus` solo donde se declara (Roles: `'always'`) |
| Teclas ´ y ç | En ReaImGui: `Apostrophe` y `Slash` (medido con la sonda, este teclado) |
| Undo por tab | Vive en `MusicState/` (no `_Shared/`: Armonía, Cues y Lyrics son el mismo dominio). Núcleo puro (pila: apilar, deshacer, rehacer, etiquetas, tope; sin ImGui ni `reaper.*`) separado del adaptador de cada tab. La pila se vacía al cambiar de proyecto (`H.last_proj`) |
| `_Shared/` | Un módulo sube cuando lo consume otro dominio o es genérico para otras UIs (`01_CONVENCIONES.md`) |

## 4. Etapas

| # | Etapa | Estado | Subir además | Tamaño | Conversaciones |
|---|---|---|---|---|---|
| 1 | Tonalidad: mayor/menor en un click | Pendiente | `MusicStateTonalidad_common_logic.lua`, `musicstate_helper.md` | ~10 líneas | Junto con la 2 |
| 2 | Lyrics: ↑/↓ por ´ y ç | Pendiente | `MusicStateKeys_config.lua`, `MusicStateLyricsTab_common_logic.lua` | Config, ~10 a 20 líneas | Junto con la 1 |
| 3 | Módulo de estilo de botones | Pendiente | `Nik_MusicState_Helper.lua`, Armonía | ~80 a 100 líneas, aplicación gradual | Una |
| 4 | Undo por tab (piloto Lyrics) | Pendiente | Lyrics (tab, Sync, Edit), Helper, `musicstate_lyrics.md` | Medio a grande | 2 o 3 (4a, 4b, 4c) |
| 5 | 6d y revamp de Cues | Pendiente | Cues, Armonía, `RowInputs`, Keys, `musicstate_helper.md` | Grande | 2 o 3 (5a, 5b, 5c) |

Estimación a ojo: tope práctico de 5 o 6 sub-pasos por conversación cuando
hay que leer archivos Lua grandes. Cada conversación termina en commit y docs
actualizados, y no mezcla temas de prueba distintos. Orden sugerido: 1 y 2,
3, 4, 5. La 4 sube primero si los bugs de undo molestan en sala.

## 5. Mini-specs de las etapas chicas

### Etapa 1 — Tonalidad: mayor/menor en un click

- **Alcance:** reemplazar el dropdown de modo (mayor/menor) por dos
  `RadioButton`. Propuesta, a confirmar contra el código: exclusivo por
  construcción; con dos checkboxes habría que evitar los estados "ambos" y
  "ninguno". El selector de tónica no cambia.
- **Riesgo a verificar primero:** si el combo de modo usa `KeyCombo` (Paso 5),
  el radio pierde el teclado hasta el 6d. Opciones: un binding de tab que
  alterne el modo, o aceptarlo hasta el 6d.
- **Pruebas:** elegir cada modo con un click; Guardar y Publicar; recargar y
  cambiar de proyecto (el modo se restaura); sin errores en consola.

### Etapa 2 — Lyrics: ↑/↓ por ´ y ç

- **Datos que faltan:** (a) qué acciones de REAPER tienen asignadas ´ y ç
  (ID de comando; preferir nativo o de SWS, un `_RS` cambia entre PCs y
  `Keys` lo avisa); (b) alcance: solo Lyrics (binding de tab con `override`)
  o global.
- **Alcance:** bindings en la config con `key = 'Apostrophe'` y
  `key = 'Slash'`. Si el cambio es solo en Lyrics, ↑/↓ quedan libres en esa
  tab para otro uso (por ejemplo, perfil de flechas entre líneas).
- **Riesgos:** colisión de teclas (`register` la reporta en consola); el
  mapeo físico depende del layout del teclado, así que verificar con la sonda
  en la PC de sala; `MusicStateKeys_config.lua` se despliega por ReaPack.
- **Pruebas:** ´ y ç en Lyrics hacen lo mismo que en REAPER; con un input
  activo no disparan; ↑/↓ en Lyrics se comportan según la decisión (a).

### Etapa 3 — Módulo de estilo de botones

- **Alcance v1:** módulo en `_Shared/` (nombre por convención, por ejemplo
  `ImGuiButtonStyle_common_logic.lua`) con tipos semánticos (propuesta:
  primario, neutro, peligro) que hacen `PushStyleColor` y
  `PushStyleVar(FrameRounding)`. Primero Armonía (Borrar = peligro, Ir y Usar
  cursor = neutro, Agregar = primario), después el resto.
- **Fuera de v1:** degradé (no es nativo, requiere `DrawList`) e íconos (la
  fuente debe traer los glifos; los emoji a color no se renderizan).
- **Relación con la etapa 5:** `ring_button` (6d) tiene que dibujar a través
  de este módulo, para tener un solo camino de dibujo.
- **Riesgos:** balance de `Push` y `Pop` dentro de tablas; colores de
  hover y active por tipo.
- **Pruebas:** apariencia en las cuatro tabs, sin cambio de comportamiento ni
  de ancho de columnas.

## 6. Etapas grandes (el spec sale de una conversación de diseño)

### Etapa 4 — Undo por tab

Spec propio, `SPEC-MusicState_Undo.md`, como salida de la 4a (lectura del
código de Lyrics). Síntomas reportados: la selección de tiempo no se
restablece o desaparece; nudges que deshacen bien pero reportan mal; choques
entre el undo de REAPER y la operación de la tab. Hipótesis, sin haber visto
el código: cada operación toca dos estados (datos de la tab y proyecto de
REAPER) y el undo restaura solo uno; el estado derivado (texto de estado,
acumuladores) no se recalcula; las preferencias de undo de REAPER pueden no
incluir la selección de tiempo (verificar). Diseño base en §3. Idea de
integración: Ctrl+Z y Ctrl+Shift+Z como bindings de tab con `override`; con la
pila vacía la `fn` devuelve `false` y corre el undo global (a confirmar contra
la config).

- 4a: lectura y diseño → sale el SPEC.
- 4b: núcleo más adaptador de Lyrics.
- 4c: bugs puntuales.

### Etapa 5 — 6d y revamp de Cues

Spec propio, `SPEC-MusicState_Cues.md`, como salida de la 5a.

- **6d:** foco por teclado y activación con Space o Enter de checkbox y
  botones. Con `NoNav` hay que dibujar el recuadro de foco a mano y evitar que
  Space dispare Play/Pause (`Keys.consume`). `ring_button` pasa por el módulo
  de estilo (etapa 3).
- **Cues:** sticky header (`musicstate_helper.md` §3), `drawPositionInputs`
  con `get_max_beats`, `ring` y `arrow_values`, "Usar selección de tiempo"
  para `duration_qn`, y el módulo de lista posicionada solo si hay dos
  implementaciones reales.
- 5a: diseño y `ring_button`. 5b: Cues estructural. 5c: Cues sobre el anillo
  y copiar y pegar.

## 7. Pendientes sueltos

- Entrar al anillo por la fila del cursor, no por la primera
  (`musicstate_keys.md` §9.5).
- Bugs conocidos del mouse en `updateMouseGesture` (`musicstate_keys.md`
  §9.3).
- Oferta de grafías del Helper (depende de `musicstate_client.md` §4,
  `musicstate_helper.md` §9).
- Fuente centralizada del color de secciones (opciones A y B en
  `musicstate_helper.md` §9).

## 8. Cierres y sync

**Apertura de una conversación nueva** (dentro del Proyecto):

```
Retomo MusicState. Leé primero WIP-MusicState_Siguientes.md y
musicstate_keys.md (§4.7 y §9). Hoy: etapa <N>, sub-paso <x>.
```

**Bloque de cierre** (se agrega al final, por diff, al terminar cada
conversación): fecha, etapa y sub-pasos hechos, commits, decisiones nuevas
(también a §3), gotchas nuevos (también al doc que corresponda), próximo paso.

**Conversación de sync** (cada 2 o 3 etapas cerradas, o ante un cambio de
arquitectura): lee este archivo junto con `00`, `01` y los docs de feature, y
verifica que lo marcado como hecho esté reflejado en los docs, que las
decisiones de §3 sigan vigentes, que no haya contradicciones entre docs, y que
no queden comentarios de código desactualizados. Actualiza estados y borra
mini-specs cerrados.

### Registro de cierres

- 2026-10-12 — Paso 6 completo (6a a 6c) y docs (`musicstate_keys.md`, `08`,
  `musicstate_helper.md`); sonda de teclas agregada. Gotchas: `08` §2, §3,
  §7. Próximo: etapas 1 y 2.
