# Contexto General — Proyecto REAPER Practice Rig / Stems Player

## Setup técnico
- REAPER v7.79
- SWS/S&M Extensions
- Windows 10

## Entorno de desarrollo
Repo real (`.git`, historial completo) vive en `C:\dev\Rea-Nik\`, **fuera**
de `%APPDATA%\REAPER` — decisión tomada para resolver dos problemas a la
vez: categorías cortas en ReaPack (`reapack-index` deriva la categoría de
la ruta relativa a la raíz del repo — con el repo afuera, las carpetas de
dominio quedan directamente en la raíz, sin el prefijo `Scripts/Custom/`
de antes) y una raíz de repo real abierta en VS Code (el workspace viejo
abría subcarpetas sueltas vía `.gitignore` allow-list, lo cual rompía el
refresh automático de extensiones como GitGraph).

Estructura:

```
C:\dev\Rea-Nik
├── AutoColor, RemoteControl, ReaPitchBus, RenderWorkflow,
│ TempoTools, MvsepImporter, StemFragment, Tests-Debug, _Shared
├── web\ ← contenido servido como reaper_www_root
├── _docs
└── Rea-Nik.code-workspace
```

Los scripts Lua **no** requieren estar físicamente bajo `Scripts\` del
resource path de REAPER — el Command ID se asigna según dónde REAPER
encuentra el archivo al registrarlo ("Load ReaScript..."), sin importar
la ubicación. Se registran directo contra `C:\dev\Rea-Nik\<Dominio>\...`.

`web\` sí necesita vivir en una ruta fija (`reaper_www_root`, requerida
por el servidor web embebido de REAPER) — se resuelve con un **junction**:

```
%APPDATA%\REAPER\reaper_www_root → (junction) → C:\dev\Rea-Nik\web
```

Creado con `New-Item -ItemType Junction` (no symlink — no requiere admin
en Windows 10). Transparente para REAPER: lee/escribe como si fuera una
carpeta normal.

**Importante:** el Command ID de cada script es específico de esta PC de
dev — no tiene relación con el Command ID que un script recibe en una PC
de destino tras un deploy vía ReaPack (ver `05_REAPACK_DEPLOY.md`), ya
que ReaPack instala en `Scripts\Rea-Nik\<categoría>\...`, una ruta
distinta. Son independientes por diseño, no hay sincronización posible
entre ambos.

## Modo de trabajo (aplica a toda sesión de scripting/documentación)
- Resolver por pasos, esperando confirmación antes de avanzar al siguiente.
- Advertir antes de escribir más de 300 líneas de código.
- Al debuguear o modificar código existente: **no regenerar archivos completos**.
  Entregar diffs en formato listo para buscar/copiar/pegar. El bloque de código
  debe contener solo el código a buscar y reemplazar, sin comentarios extra
  dentro del bloque.
- Desarrollo iterativo y modular: construir y testear en etapas, no de una vez.
- Conversaciones en español.

## Propósito general del proyecto
Flujo de trabajo centrado en un proyecto plantilla ("Practice Rig - Stems
Player") para transformar canciones separadas en stems (Drums, Bass, Guitar,
Piano, Other, Vocals) en pistas de práctica: renders de secciones específicas
con combinaciones de stems adaptadas (un instrumento protagonista, o la mezcla
completa menos un instrumento), incluyendo un count-in de metrónomo grabado en
el archivo final.

## Mapa del ecosistema de funcionalidades

Cada funcionalidad tiene su propio doc en `features/`, pero todas comparten
las convenciones de `01_CONVENCIONES.md`. Relación entre ellas:

```
MVSEP Importer  →  llena el folder "Stem Bus" con los 6 stems
                         │
                         ▼
                Sistema de Snapshots (SN_*)
                (ya implementado, script custom)
                         │
                         ▼
                Render Workflow
        (regiones nombradas + count-in + preset)
                         │
                         ▼
        Batch Script (Paso 7 — EN DESARROLLO)
   vincula región ↔ snapshot ↔ render automático
```

Funcionalidades independientes (no articulan directamente con el flujo de
render, pero conviven en el mismo proyecto/entorno):
- **Auto-color system**: colorea tracks por familia de instrumento.
- **Tempo mapping / ReaBeat**: detección de tempo y corrección de mapa de
  tempo para intros atípicas.
- **Panel ReaPitch (Stem Bus)**: control nativo de semitonos ReaPitch vía
  ReaImGui, ver `03_PANEL_REAPITCH_KNOB.md`.
- **Control remoto web**: interfaz HTML para controlar REAPER desde el
  celular en ensayos (transporte, faders, markers, playrate, semitonos
  ReaPitch), ver `features/remote_control.md`.
- **Deploy vía ReaPack**: empaquetado y distribución de un subconjunto de
  scripts (hoy: Control remoto + Auto-color) a PCs de ensayo sin git ni
  editor de código, vía repo propio `Rea-Nik` en GitHub. Ver
  `05_REAPACK_DEPLOY.md`.

## Estado general (ver detalle en cada doc de feature)
| Funcionalidad           | Estado                                        |
|--------------------------|------------------------------------------------|
| Auto-color system        | Confirmado funcionando                         |
| MVSEP stem importer      | En progreso (caso borde "instrum" pendiente)   |
| Sistema de Snapshots      | Implementado (script custom, prefijo SN_)      |
| Render Workflow           | Pasos 1–6 cerrados, Paso 7 (batch) pendiente   |
| Tempo mapping / ReaBeat   | Diagnóstico en curso                           |
| Panel ReaPitch (Stem Bus) | Funcional, pulido visual pendiente             |
| Control remoto web        | Funcional, pendientes menores (ver doc feature)|
| Deploy vía ReaPack        | En progreso (AutoColor deployado, RemoteControl pendiente) |

## Pendientes generales (horizonte, no bloqueantes)
- Count-in con offset negativo de render: **evaluado y descartado** como forma
  de evitar el track de count-in — el track propio sigue siendo necesario por
  calidad de sonido y porque el patrón rítmico del conteo varía (4 negras, o
  2 blancas + 4 negras en tempos rápidos).
- Pitch-shift toggle script (per-stem, mapeable a footswitch MIDI).
- Parser de nomenclatura alternativa de secciones (V1, V2, PC, C1...) usada en
  otros proyectos — no bloqueante.
