# Contexto General — Proyecto REAPER Practice Rig / Stems Player

## Setup técnico
- REAPER v7.79
- SWS/S&M Extensions
- Windows 10

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
  editor de código, vía repo propio `reaper-nik` en GitHub. Ver
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
- Categoría de ReaPack anidada (`Scripts/Custom/AutoColor` en vez de
  `AutoColor`) — causa raíz: el repo git vive en la raíz de
  `%APPDATA%\REAPER` (necesario hoy para no romper Command IDs), y
  `reapack-index` deriva la categoría de la ruta completa desde la raíz
  del repo. Solución de fondo pendiente: reestructurar carpetas para que
  un único repo permita categorías cortas sin sacrificar rutas estables
  de Command ID (descartada la alternativa de un segundo repo/junctions
  por complejidad injustificada). No bloqueante — no afecta
  funcionalidad, solo estética del navegador de paquetes en ReaPack.
