# Feature: Render Workflow

Ver `../01_CONVENCIONES.md` para nomenclatura de tracks/snapshots/regiones —
no duplicado acá.

## Objetivo
Automatizar el render de fragmentos de práctica (sección + combinación de
stems) minimizando trabajo manual repetitivo: nombrado de archivo, ajuste de
mezcla, y disparo de render.

## Contexto de mezcla
El volumen/mute de cada combinación de stems ya está resuelto por un sistema
de **Mix Snapshots (SWS)** propio, generado por un script custom existente:
- Snapshot protagonista: deja el resto de los tracks con **fader bajo, pero
  activos** (no mute).
- Snapshot "sin instrumento" (`_Muted` / `SN_Instrumental`): **mutea** el
  track correspondiente. En testing al momento de esta documentación.

Dado esto, la **Region Render Matrix de SWS fue evaluada y descartada** — no
aporta nada porque el estado de mute/volumen ya lo resuelve el sistema de
snapshots antes del render.

## Pasos definidos y su estado

### Paso 1 — Regiones de render ✅
- Cada combinación (sección × instrumento protagonista, o sección × "sin
  instrumento") es una región propia, nombrada según la convención de
  `01_CONVENCIONES.md`.
- La región abarca: **count-in + fragmento musical**, más **1 segundo de
  padding de silencio al inicio y al final** (para no cortar colas de
  reverb/delay ni el ataque del count-in).
- Las secciones "limpias" (para navegar el proyecto) se marcan con
  **markers** simples, separados de estas regiones de render.
- REAPER 7.76 permite **region lanes ocultables individualmente** — abre la
  posibilidad de tener también regiones limpias en un lane aparte, oculto,
  si en algún momento se prefiere sobre markers. No implementado, queda como
  alternativa disponible.

### Paso 2 — Region Render Matrix ❌ Descartado
Redundante dado el sistema de snapshots existente (ver "Contexto de mezcla").

### Paso 3 — Wildcard de nombre de archivo ✅
- Render dialog → **Source: Selected Regions**.
- **File name: `$region`** — toma el nombre de la región tal cual (que ya es
  igual al nombre de archivo final definido en las convenciones).
- Validado: el archivo renderizado sale nombrado correctamente.

### Paso 4 — Count-in ✅
- Vive en un **track dedicado** (ReaSamplomatik + sample de palillos, o
  variante hi-hat a futuro), independiente de los tracks de instrumentos.
- Track de count-in permanece **muteado por default**; se desmutea
  manualmente antes de renderizar la región que lo necesita, y se vuelve a
  mutear después. Esto no cambia respecto al proceso actual del usuario.
- Se ubica **un ítem de conteo por cada sección** que lo requiera,
  coexistiendo todos en el mismo track, en distintas posiciones del timeline.
- Patrón rítmico más frecuente: 4 negras. Variante 2 blancas + 4 negras
  posible en tempos rápidos.
- **Evaluado y descartado**: usar "Custom Time Range" con inicio negativo de
  render para evitar el track de count-in en canciones que arrancan en bar 1.
  Aunque es técnicamente posible (`RENDER_BOUNDSFLAG`, `RENDER_STARTPOS`
  acepta negativos), no elimina la necesidad del track/ítem real (se necesita
  igual para que suene algo ahí) y agregaría un segundo mecanismo de render
  distinto al resto de las regiones. Descartado por complejidad injustificada.
- **Mitigación adoptada**: el usuario se asegurará de que las canciones
  siempre arranquen en bar 2 o 3, eliminando el caso borde de raíz.

### Paso 5 — Preset de render ✅
- Preset nuevo `MP3 192 - Regions`, derivado de un preset previo del usuario
  (que usaba `Time selection` + `$project`, mantenido intacto para otros usos
  como el render del Master completo).
- Cambios aplicados: **Source → Selected Regions**, **File name → $region**.
- Formato/bitrate (mp3 192kbps) heredado del preset original.

### Paso 6 — Mix Snapshots ✅ (ya resuelto previamente)
Sistema ya implementado por el usuario, ver "Contexto de mezcla" arriba.

### Paso 7 — Batch script ⏳ PENDIENTE (próxima sesión)

**Objetivo:** automatizar la repetición manual actual (por cada región:
activar snapshot correspondiente → desmutear track de count-in → renderizar
→ mutear count-in → repetir).

**Specs acordadas para el script:**
1. **Generación de regiones desde markers existentes:**
   - Leer todos los markers del proyecto (`EnumProjectMarkers` o equivalente).
   - Por cada sección (marker), calcular el rango de cada región a crear:
     inicio = posición del marker − tiempo del count-in − 1s de padding;
     fin = posición del siguiente marker + 1s de padding.
   - Crear las regiones (`AddProjectMarker2` con `isrgn = true`) iterando
     sobre las combinaciones necesarias por sección: 6 protagonistas + hasta
     6 "sin instrumento", según la tabla de `01_CONVENCIONES.md`.
   - Nombrarlas exactamente según la convención definida.

2. **Asignación a region lanes — PENDIENTE DE VERIFICAR:**
   - No confirmado si la API de ReaScript expone actualmente un parámetro
     para asignar una región a un lane específico al crearla (feature de
     lanes es relativamente nueva en REAPER 7).
   - **Acción para la próxima sesión:** verificar en documentación de la API
     de REAPER (o testeo directo) si existe dicho parámetro antes de asumir
     que el script puede separar automáticamente las regiones en lanes.
   - Alternativa de fallback si no está soportado: crear todas las regiones
     en el lane por defecto, y reorganizar manualmente una sola vez, o
     navegar por nombre vía el filtro de texto del Region/Marker Manager.

3. **Matching región ↔ snapshot para el batch de render:**
   - El nombre de instrumento en español (de la región) debe mapearse al
     nombre de snapshot correspondiente (ver tabla de correspondencia en
     `01_CONVENCIONES.md`) para que el script sepa qué snapshot recuperar
     antes de renderizar cada región.

4. **Flujo del batch (por cada región a renderizar):**
   - Recuperar el snapshot correspondiente.
   - Desmutear el track de count-in (si la región lo requiere).
   - Disparar render de esa región puntual (usando el preset
     `MP3 192 - Regions`).
   - Mutear nuevamente el track de count-in.
   - Avanzar a la siguiente región.

**No bloqueante para el Paso 7, pero relacionado:** advertencia de 300 líneas
de código — probable que el script completo (generación de regiones + batch
de render) supere ese límite; evaluar si conviene dividirlo en dos scripts
(uno de generación de regiones, otro de batch render) o ir construyendo por
etapas con confirmación en cada una, según el modo de trabajo acordado.
