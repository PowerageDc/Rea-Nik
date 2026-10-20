# WIP — MusicState: siguientes etapas (después del Paso 6)

Cola de trabajo, no historia. Un hecho vive en un solo lugar: los docs de
feature y `08_REAIMGUI_PATTERNS.md` dicen cómo está hecho hoy; este archivo
dice qué falta; git dice qué pasó y cuándo. Solo se achica: al cerrar una
etapa se borran su fila, su mini-spec y sus decisiones ya absorbidas. Sin
fechas ni narrativa.

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
- Al cerrar cada etapa, en este orden: (1) commit del código; (2) lo
  aprendido a los docs de feature y los patrones genéricos de ReaImGui a
  `08_REAIMGUI_PATTERNS.md`, en otro commit; (3) en este archivo, borrar la
  fila de la etapa, su mini-spec y las decisiones de §3 ya absorbidas, y
  reescribir la línea "Próximo" de §2. No se agrega nada más.
- Subir siempre: este archivo, `musicstate_keys.md`, `musicstate_keys_inputs.md` y
  `MusicStateKeys_common_logic.lua`, más los de la etapa (tabla de §4). El
  Proyecto trae `00` y `01` como copias de solo lectura: resubirlos si
  cambiaron en el repo.

## 2. Estado de partida

Pasos 1 a 6c del refactor de atajos hechos y documentados
(`musicstate_keys.md` y `musicstate_keys_inputs.md` §2, §3, §9). Sonda de teclas 
en `Tests-Debug/Nik_Test_KeyProbe.lua`.

**Próximo:** etapa 4.

## 3. Decisiones aún no absorbidas por los docs

Solo lo decidido que todavía no está en un doc de feature. Lo ya documentado
(anillo de foco, perfiles, `SetKeyboardFocusHere`, `InputInt` activo) vive en
`musicstate_keys_inputs.md` §3 y en `08`, y no se repite acá. Al absorberse, la
fila se borra.

| Tema | Decisión |
|---|---|
| Undo por tab | Vive en `MusicState/` (no `_Shared/`: Armonía, Cues y Lyrics son el mismo dominio). Núcleo puro (pila: apilar, deshacer, rehacer, etiquetas, tope; sin ImGui ni `reaper.*`) separado del adaptador de cada tab. La pila se vacía al cambiar de proyecto (`H.last_proj`) |

## 4. Etapas

| # | Etapa | Estado | Subir además | Tamaño | Conversaciones |
|---|---|---|---|---|---|
| 4 | Undo por tab (piloto Lyrics) | Pendiente | Lyrics (tab, Sync, Edit), Helper, `musicstate_lyrics.md` | Medio a grande | 2 o 3 (4a, 4b, 4c) |
| 5 | 6d y revamp de Cues | Pendiente | Cues, Armonía, `RowInputs`, Keys, `musicstate_helper.md` | Grande | 2 o 3 (5a, 5b, 5c) |

Estimación a ojo: tope práctico de 5 o 6 sub-pasos por conversación cuando
hay que leer archivos Lua grandes. Cada conversación termina en commit y docs
actualizados, y no mezcla temas de prueba distintos. Orden sugerido: 4, 5. 
La 5 sube primero si los bugs de Cues molestan en sala.

## 5. Mini-specs de las etapas chicas

Sin etapas chicas pendientes.

## 6. Etapas grandes (el spec sale de una conversación de diseño)

Al cerrar la etapa, su SPEC propio se reescribe como doc de feature (cómo
está hecho hoy, sin plan) o se absorbe en uno existente y se borra.

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
  de estilo (`ImGuiButtonStyle_common_logic.lua`).
- **Cues:** sticky header (`musicstate_helper.md` §3), `drawPositionInputs`
  con `get_max_beats`, `ring` y `arrow_values`, "Usar selección de tiempo"
  para `duration_qn`, y el módulo de lista posicionada solo si hay dos
  implementaciones reales.
- 5a: diseño y `ring_button`. 5b: Cues estructural. 5c: Cues sobre el anillo
  y copiar y pegar.

## 7. Pendientes sueltos

- Entrar al anillo por la fila del cursor, no por la primera
  (`musicstate_keys_inputs.md` §9).
- Bugs conocidos del mouse en `updateMouseGesture`
  (`musicstate_keys_inputs.md` §9).
- Tonalidad "sin definir" como valor real, sin publicar `project_key`
  (`musicstate_helper.md` §8).
- Lyrics refresca datos cuando una tab vacía carga proyecto. Las demás
  no lo hacen hasta reabrir helper, o cambiar de tab y volver.
- Teclas globales ´ y ç: habilitar la repetición, como ←|→
- Fuente centralizada del color de secciones (opciones A y B en
  `musicstate_helper.md` §8).

## 8. Cierres y sync

**Apertura de una conversación nueva** (dentro del Proyecto):

```
Retomo MusicState. Leé primero WIP-MusicState_Siguientes.md y
musicstate_keys_inputs.md (§3 y §9). Hoy: etapa <N>, sub-paso <x>.
```

**Cierre de conversación:** no hay registro, la historia es git. Se sigue
§1 y lo único que se escribe acá es la línea "Próximo" de §2.

**Conversación de sync** (cada 2 o 3 etapas cerradas, o ante un cambio de
arquitectura): lee este archivo junto con `00`, `01` y los docs de feature, y
verifica que no haya hechos duplicados entre este archivo y los docs, que lo
ya hecho no siga acá, que las decisiones de §3 sigan vigentes, que no haya
contradicciones entre docs y que no queden comentarios de código
desactualizados. Es una auditoría: borra y corrige, no agrega historia.
