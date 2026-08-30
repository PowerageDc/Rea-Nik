# Tempo Mapping con ReaBeat — hechos y gotchas

Documento de contexto técnico, no bitácora. Sintetiza lo aprendido sobre detección de tempo con ReaBeat y edición de tempo markers vía ReaScript. Se actualiza por sesión; no crece indefinidamente (ver sección "Pendiente" al final).

## Comportamiento de ReaBeat

- Trabaja **por item**, con caché individual — cambiar de item no fuerza re-detección salvo que el audio subyacente cambie.
- `Insert Tempo Map` solo reemplaza markers **dentro del rango del item analizado** — no toca el resto del proyecto. Esto permite corregir tramos puntuales sin rehacer todo el mapa.
- El *time signature* **no se tipea**: se infiere automáticamente del espaciado entre downbeats marcados. Para fijar un compás hay que marcar/mover el downbeat correcto (toggle), no hay campo de texto para "3/4".
- Editor de waveform: doble click = agregar beat; click derecho sobre un beat = borrarlo; los beats (líneas azules) no se arrastran, se agregan/borran. El downbeat (línea amarilla) sí se puede mover, pero **solo salta entre beats azules ya existentes** — si el conteo de beats está mal, mover el downbeat no arregla la métrica.
- Gap highlighting: tramos de baja confianza se resaltan, con líneas de sugerencia sobre los transientes más fuertes disponibles (candidatos, no confirmados). Atajo `N` salta al próximo gap.
- Campo de BPM editable: útil para fijar tempo conocido como referencia visual al posicionar beats a mano en tramos de señal débil/ambigua (ej. instrumento solo, bajo nivel).
- **No hay toggle documentado** para evitar que el modo variable-bars/variable-beats marque time signature explícito en cada marker (necesario para poder variar tempo por compás/beat).

## Gotcha: drift por tracking neural continuo

ReaBeat hace tracking continuo — un error de detección en un tramo (ej. señal débil o ambigua) se arrastra en cascada al resto de la canción, aunque tramos posteriores sean perfectamente detectables por sí solos.

**Fix:** tratar cada tramo problemático como detección independiente:
1. Duplicar el item de referencia en un track separado por tramo (no en el mismo track — evita bleed en los cortes).
2. **Glue** cada copia recortada (`Item: Glue items`) — el simple split no alcanza, ReaBeat puede seguir leyendo la fuente de audio completa detrás del recorte si no se glue-a.
3. Tratamiento de señal si hace falta (compresión para parejar niveles, aislar instrumento con transiente más claro para ese tramo).
4. Detectar y `Insert Tempo Map` por separado en cada tramo — al ser análisis por-item independiente, no hereda el drift del tramo anterior.
5. Verificar fase en cada punto de empalme (debería calzar solo si el corte cae en un downbeat real).

## Gotcha: edición manual de compás vía diálogo (doble click)

Editar el time signature de un marker por el diálogo nativo dispara un recálculo interno de posición en términos de compás:beat — esto puede desplazar o "comerse" (fusionar/eliminar) el marker siguiente como efecto colateral, sin que el usuario lo pida. **No usar edición manual por UI para reestructurar compases en cadena.**

## Gotcha: ReaBeat no soporta compases compuestos (6/8, 9/8, 12/8...)

La detección de time signature de ReaBeat solo cubre compases simples con denominador /4, rango 2/4 a 7/4 (confirmado en la documentación del proyecto). No hay soporte nativo para compases ternarios/compuestos.

**Síntoma:** un tramo real en 6/8 (o 12/8) se detecta con los pulsos en la posición correcta — el metrónomo "cae bien" — pero etiquetado como compás simple equivocado (ej. 6/8 real → detectado como 2/4). ReaBeat encontró los pulsos reales correctamente, pero como su vocabulario de salida no tiene denominador /8, aproxima con el simple más parecido en cantidad de pulsos por compás, perdiendo la subdivisión ternaria.

**Fix — fórmula de conversión validada por oído y por prueba en REAPER (ver sesión de referencia):**
Para cada marker mal-etiquetado como `N/4` que en realidad es compuesto ternario:
- `timesig_num` nuevo = `N × 3`
- `timesig_denom` nuevo = `8`
- `bpm` nuevo = `bpm_original × 0.75`

Aplicar directo vía `SetTempoTimeSigMarker` con estos tres valores calculados a partir de lo que devuelve `GetTempoTimeSigMarker` — no usar el campo "BPM basis" del diálogo de REAPER como mecanismo de conversión (ver nota más abajo sobre por qué).

**Sobre "BPM basis" (campo del diálogo, no de la API):** `SetTempoTimeSigMarker` no tiene parámetro de basis — el campo del diálogo de REAPER convierte lo que se tipea a un valor interno distinto antes de guardarlo, y ese valor interno es el que hay que replicar en scripts (no un concepto de "basis" a nivel API). Validado empíricamente: basis "1/8 dotted" con el mismo número visible en pantalla produce internamente `bpm_raw × 0.75`; basis "1/4 dotted" produce `bpm_raw × 1.5` (probado y descartado — daba conteo doble, 12 semicorcheas en vez de 6 corcheas).

**Ruler — ver 6/8 con las 6 corcheas marcadas:** no es el BPM basis lo que controla esto, es un ajuste de grid separado ("Show grid line spacing" en las opciones de grid/ruler) — cambiar de 1/4 a 1/8 resuelve la numeración de la regla en el tramo compuesto.

## Gotcha: `SetTempoTimeSigMarker` y drift en cascada vía API

- La función es mutuamente excluyente: pasar `timepos` requiere `measurepos=-1, beatpos=-1` (o viceversa). Pasar ambos sets de parámetros a la vez causa que REAPER ignore `timepos` y recalcule posición desde compás/beat — replica el mismo bug que la edición manual.
- **Aun pasando `measurepos=-1, beatpos=-1` correctamente**, cambiar el compás de un marker anterior sigue disparando recálculo en cascada de posiciones de markers posteriores — es comportamiento del motor de tempo, no un parámetro mal pasado.
- **Fix confirmado: doble pasada.** Aplicar todos los cambios de compás primero (dispara el drift), después re-aplicar el `timepos` original de cada marker en una segunda pasada (sin volver a tocar el compás) — como la segunda pasada no cambia compás, no dispara nueva cascada, y las posiciones quedan corregidas y estables.
- **Confirmado también para cambios de BPM/basis sin tocar compás:** editar solo el BPM (basis) de un marker, dejando numerador/denominador intactos, igual dispara cascada en markers posteriores (probado en REAPER: no mueve el propio marker editado, pero acorta compases siguientes y adelanta sus posiciones). La doble pasada es obligatoria para cualquier edición de BPM o compás en cadena, no solo para cambios de compás.

## Ruler display (mostrar/ocultar tempo/time sig markers)

Es una preferencia **global** de REAPER (reaper.ini), no se guarda por proyecto — afecta a todos los proyectos incluidos los nuevos. No se encontró confirmación de un toggle nativo por-proyecto. Posible workaround sin confirmar: SWS `Set project startup action`, si existe una acción ejecutable equivalente al toggle de menú contextual (pendiente de verificar en el Action List).

## Marker 1 (1.1.00)

Posición inamovible (comportamiento esperado). El flag de time signature sí se le puede quitar sin problema si la canción es de métrica constante (probado y confirmado). En canciones con métrica variable real, no aplica remover flags en bloque (ver sección scripts).

## Scripts

- **`strip_tempo_timesig_flag.lua`** — recorre todos los tempo markers del proyecto y les quita el flag de time signature (quedan como tempo puro, heredan compás del marker explícito anterior). Uso: canciones de métrica constante donde ReaBeat marcó compás redundante en cada marker. **No usar en canciones con cambios de métrica reales** — borra los cambios legítimos también.
- **`strip_tempo_timesig_in_selection.lua`** — misma lógica pero acotada a una selección de tiempo, para no afectar tramos con cambios de métrica reales fuera del rango. Límite de selección: usa `>=` / `<` (no `<=`) en el borde final para no incluir de más el marker límite.
- **`bulk_edit_timesig_markers.lua`** — lista en consola los markers con compás explícito dentro de la selección (o todo el proyecto), y permite editar todos de una vez vía un único diálogo de texto (valores nuevos separados por coma, mismo orden que la consola; `0` = quitar flag/heredar). Aplica con la técnica de doble pasada (ver gotcha de arriba) para evitar drift. Funciona, pero la UI (una sola línea de texto) es incómoda con muchas filas.
- **`convert_simple_to_compound.lua`** — UI ReaImGui con tabla de checkboxes. Escanea candidatos (markers con denominador 4, numerador 2-7) dentro de la selección de tiempo activa, o todo el proyecto si no hay selección. Muestra preview de conversión (compás y BPM actual → nuevo) antes de aplicar. Click en cualquier celda de una fila mueve el cursor de edición a esa posición (útil para ubicar el marker en el proyecto). Aplica la fórmula de conversión simple→compuesto (ver gotcha de arriba) con doble pasada. Probado y funcionando end-to-end.

## Flujo recomendado según tipo de canción (para decidir rápido)

- **Tempo constante, sin cambios de métrica reales:** una sola detección continua sobre el track de referencia completo (glueado). Si ReaBeat marca compás redundante en cada marker, correr `strip_tempo_timesig_flag.lua` una vez al final.
- **Tempo variable (rubato), señal de referencia limpia en todo el tema:** una sola pasada continua, sin necesidad de splitear.
- **Tempo variable, con un tramo de señal débil/ambigua (ej. un instrumento se queda solo y bajo):** splitear + glue solo ese tramo, tratarlo aparte (ver gotcha de drift), empalmar.
- **Cambios de métrica frecuentes, pulso constante:** una sola pasada en modo variable-bars; corregir downbeats a mano dentro del editor de ReaBeat *antes* de aplicar, especialmente en compases irregulares cortos (2/4, 3/4, 5/4 intercalados en 4/4).
- **Intro con instrumento de referencia distinto al resto (ej. guitarra sola antes de que entre la batería):** splitear + glue esa intro aparte, detectar con ese instrumento como referencia (no con el track que está en silencio ahí), aplicar solo en ese rango.

## Pendiente (próxima sesión)

- Construir UI mejorada para `bulk_edit_timesig_markers.lua`: lista de markers con checkbox para habilitar edición por fila + input individual (default `0`), reemplazando el diálogo de una sola línea. Ya hay un patrón de referencia funcionando en `convert_simple_to_compound.lua` (tabla ImGui + checkboxes + selectable por celda para mover cursor) — reusar esa estructura en vez de partir de cero.
- Soportar multiselección (Shift+click, mismo patrón que `convert_simple_to_compound.lua`): al aplicar un valor de compás sobre varias filas seleccionadas, la primera fila de la selección recibe ese compás explícito y el resto de las filas seleccionadas quedan en `0` (heredan). Automatiza el patrón manual usado hoy para fusionar tramos de falso 2/4 en un 4/4 real.
- Validar la fórmula de conversión simple→compuesto (`num×3, denom=8, bpm×0.75`) para el caso 12/8 (4 pulsos ternarios) — solo se confirmó para 6/8 hasta ahora.
- Nota de API: `reaper.ImGui_DestroyContext` no existe en versiones recientes de ReaImGui (0.9+) — el contexto se limpia por garbage collection. No llamarla al cerrar la ventana del loop.
- Sin confirmar: si existe acción nativa ejecutable equivalente al toggle de ruler display, para viabilizar el workaround de SWS `Set project startup action` (ocultar markers por proyecto).
