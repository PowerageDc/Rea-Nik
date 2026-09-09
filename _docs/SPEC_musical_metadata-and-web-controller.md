# REAPER Musical Metadata & Web Controller

## 1. Objetivo

Extender el uso del Web Control de REAPER mediante un sistema de **metadata musical sincronizada con el timeline**, accesible desde un dispositivo remoto conectado al servidor Web de REAPER.

El objetivo principal es que un dispositivo —por ejemplo un celular— pueda consultar durante la reproducción información musical asociada a la posición actual del proyecto.

La primera aplicación será mostrar:

- Acorde actual.
- Próximo acorde.
- Compás actual.
- Beat actual.
- Tempo.
- Time signature.
- Sección actual.
- Eventualmente otras indicaciones musicales.

El sistema debe ser extensible para incorporar posteriormente:

- Tonalidad.
- Escala.
- Función armónica.
- Número de compás.
- Indicaciones de interpretación.
- Cues.
- Lyrics.
- Texto sincronizado.
- Información de arreglo.
- Otros datos específicos del proyecto.

---

# 2. Estado actual

El proyecto ya utiliza:

## Markers

Los **Project Markers** se utilizan actualmente para identificar secciones formales de la canción.

Ejemplos:

```text
INTRO
VERSO 1
PRE-CORO
CORO
VERSO 2
PUENTE
SOLO
OUTRO
```

Por lo tanto:

> Los Markers existentes deben conservar su función de **estructura formal del proyecto**.

No se propone reutilizarlos para almacenar los acordes.

---

# 3. Fuentes de metadata de REAPER

El sistema utilizará distintas fuentes según el tipo de información.

| Información | Fuente propuesta |
|---|---|
| Secciones | Project Markers |
| Posición temporal | Timeline / API de REAPER |
| Compás actual | Posición musical de REAPER |
| Beat actual | Posición musical de REAPER |
| Tempo | Tempo map / API de REAPER |
| Time signature | Tempo/Time Signature markers / API |
| Armonía | Project ExtState |
| Información global del proyecto | Project ExtState / Project Notes |
| Texto sincronizado | Lyrics u otros mecanismos temporales |
| Rangos estructurales opcionales | Regions |

REAPER 7.79 expone mediante ReaScript APIs para markers, regions, tempo/time signature, project notes y Project ExtState.

---

# 4. Project ExtState como almacenamiento de metadata musical

## 4.1. Concepto

La información armónica no se almacenará inicialmente en Markers ni Regions.

Se utilizará **Project ExtState** como almacenamiento persistente asociado al proyecto.

REAPER proporciona:

```lua
reaper.SetProjExtState()
reaper.GetProjExtState()
reaper.EnumProjExtState()
```

Los datos quedan asociados al proyecto y se restauran al volver a cargarlo.

Esto permite crear un namespace propio para la aplicación.

Ejemplo:

```text
NS_AUDIO_MUSIC
```

---

# 5. Modelo de datos armónicos

La metadata armónica debe estar asociada a una **posición musical**, preferentemente a un compás.

Ejemplo conceptual:

```text
bar 1  → Cmaj7
bar 2  → Am7
bar 3  → Dm7
bar 4  → G7
```

La información almacenada no necesita modificar ningún elemento visual del proyecto.

El timeline de REAPER continúa siendo la fuente de verdad para:

- posición;
- compás;
- beat;
- tempo;
- métrica.

El ExtState contiene únicamente la metadata musical adicional.

---

# 6. Namespace propuesto

Namespace inicial:

```text
NS_AUDIO_MUSIC
```

Dentro de ese namespace pueden existir diferentes claves.

Ejemplo conceptual:

```text
NS_AUDIO_MUSIC
    harmony.bar.1 = Cmaj7
    harmony.bar.2 = Am7
    harmony.bar.3 = Dm7
    harmony.bar.4 = G7
```

Una implementación posterior podría utilizar una estructura más rica:

```text
harmony.bar.1.chord = Cmaj7
harmony.bar.1.symbol = Cmaj7
harmony.bar.1.function = I
harmony.bar.1.scale = C major
```

Sin embargo, para la primera versión se recomienda mantener el modelo simple.

---

# 7. Unidad temporal de la armonía

## 7.1. Primera versión

La unidad primaria será:

> **Compás**

Ejemplo:

```text
Compás 1 → Cmaj7
Compás 2 → Am7
Compás 3 → Dm7
Compás 4 → G7
```

Esto permite que el controlador determine el acorde actual a partir del compás actual.

---

## 7.2. Futuro: múltiples acordes por compás

El modelo deberá poder evolucionar a subdivisiones menores.

Ejemplo:

```text
Compás 12
    Beat 1 → Cmaj7
    Beat 3 → Dm7

Compás 13
    Beat 1 → G7
    Beat 3 → Cmaj7
```

Por lo tanto, la arquitectura no debería asumir que siempre existe exactamente un acorde por compás.

Una posible representación futura:

```text
bar.12.beat.1 = Cmaj7
bar.12.beat.3 = Dm7

bar.13.beat.1 = G7
bar.13.beat.3 = Cmaj7
```

---

# 8. Separación entre estructura y armonía

La arquitectura debe mantener separadas estas dos capas.

## Estructura

Proviene de los Project Markers:

```text
VERSE
CHORUS
BRIDGE
SOLO
```

## Armonía

Proviene de Project ExtState:

```text
Cmaj7
Am7
Dm7
G7
```

Esto permite que una misma sección contenga cualquier cantidad de eventos armónicos.

Ejemplo:

```text
Marker:
CHORUS

Harmony:
bar 25 → Cmaj7
bar 26 → Am7
bar 27 → Dm7
bar 28 → G7
```

---

# 9. Regions

Las Regions **no son necesarias para la metadata armónica inicial**.

Una Region representa naturalmente un rango temporal:

```text
inicio ───────────── fin
```

Por lo tanto, puede resultar útil posteriormente para información que tenga duración.

Posibles usos futuros:

- Bloques de arreglo.
- Secciones completas con inicio y fin.
- Rangos de ensayo.
- Loops.
- Bloques de exportación.
- Estructuras alternativas.
- Rangos que deban ser tratados como una unidad.

Ejemplo:

```text
Region:
VERSE 1
00:32 ───────── 01:04
```

Pero como actualmente los Markers ya se utilizan para identificar:

```text
VERSE 1
CHORUS
BRIDGE
```

no se introduce Regions en la primera versión.

---

# 10. Estado musical en tiempo real

El sistema debe construir un estado musical derivado de la posición actual del proyecto.

Conceptualmente:

```text
MUSIC STATE

position:
    time
    bar
    beat

transport:
    playing
    stopped
    paused

tempo:
    bpm

meter:
    numerator
    denominator

structure:
    section

harmony:
    chord
    next_chord
```

Ejemplo:

```json
{
    "playing": true,
    "bar": 37,
    "beat": 3,
    "tempo": 128,
    "time_signature": "4/4",
    "section": "CHORUS",
    "chord": "Dm7",
    "next_chord": "G7"
}
```

El JSON es solamente un modelo conceptual; el formato real dependerá de la interfaz que finalmente utilice el Web Control.

---

# 11. Flujo de funcionamiento

```text
                REAPER
                   │
                   │
          ┌────────┴─────────┐
          │                  │
       Timeline          Project ExtState
          │                  │
          │                  │
     ┌────┴────┐        ┌────┴─────┐
     │         │        │          │
    Bar      Beat     Chord      Metadata
     │         │        │          │
     └────┬────┘        └────┬─────┘
          │                  │
          └────────┬─────────┘
                   │
             MUSIC STATE
                   │
                   ▼
             Web Controller
                   │
                   ▼
                Celular
```

---

# 12. Polling

El controlador Web ya realiza polling frecuente para obtener información de REAPER.

Actualmente se utiliza una frecuencia aproximada de:

```text
10 ms
```

Esto equivale a:

```text
100 consultas por segundo
```

La arquitectura propuesta debe aprovechar ese mecanismo existente.

No es necesario que el celular implemente por sí mismo la lógica completa de interpretación del proyecto.

La lógica puede estar centralizada en REAPER/ReaScript.

---

# 13. ReaScript como capa de integración

Se propone implementar una capa ReaScript —preferentemente Lua— que actúe como adaptador entre:

```text
REAPER Project
        ↓
Musical Metadata
        ↓
Web Controller
```

El script debe poder:

1. Obtener la posición actual.
2. Determinar compás y beat.
3. Obtener tempo y métrica.
4. Determinar la sección actual a partir de los Markers.
5. Obtener la metadata armónica correspondiente.
6. Determinar el próximo acorde.
7. Exponer un estado unificado para el controlador.

REAPER 7.79 soporta Lua de forma integrada mediante ReaScript.

---

# 14. API relevante de REAPER

Funciones/API a investigar durante la implementación:

## Markers / Regions

```lua
reaper.GetLastMarkerAndCurRegion()
reaper.GetNumRegionsOrMarkers()
reaper.GetRegionOrMarker()
reaper.GetSetRegionOrMarkerInfo_String()
```

`GetLastMarkerAndCurRegion()` permite obtener el último marker anterior a una posición y la región que contiene esa posición.

## Project ExtState

```lua
reaper.SetProjExtState()
reaper.GetProjExtState()
reaper.EnumProjExtState()
```

## Project Notes

```lua
reaper.GetSetProjectNotes()
```

## Tempo / Time Signature

Investigar:

```lua
reaper.GetProjectTimeSignature2()
```

y las APIs de Tempo/Time Signature markers.

REAPER 7.79 expone APIs específicas para esta información.

---

# 15. Project Notes

Project Notes se reservará para información global del proyecto que no dependa de la posición temporal.

Ejemplos:

```text
Key: C major
Tuning: Standard
Arrangement: Live
Conductor notes:
General notes:
```

No se utilizará Project Notes para almacenar los acordes.

REAPER expone `GetSetProjectNotes()` para esta finalidad.

---

# 16. Lyrics

El sistema de Lyrics de REAPER debe investigarse como una posible fuente adicional de texto sincronizado.

Posibles aplicaciones:

```text
Lyrics
Cues
Indicaciones
Texto para intérpretes
Anotaciones sincronizadas
```

La utilización de Lyrics queda fuera de la primera implementación de armonía, pero se considera una extensión futura.

---

# 17. Arquitectura conceptual final

La primera versión debería quedar conceptualmente así:

```text
┌─────────────────────────────────────────────┐
│                 REAPER                      │
│                                             │
│  Timeline                                   │
│    ├── bar                                  │
│    ├── beat                                 │
│    ├── tempo                                │
│    └── time signature                       │
│                                             │
│  Project Markers                            │
│    └── sections                             │
│                                             │
│  Project ExtState                            │
│    └── NS_AUDIO_MUSIC                       │
│          └── harmony                         │
│                                             │
│  Project Notes                              │
│    └── global project information           │
│                                             │
└───────────────────┬─────────────────────────┘
                    │
                    ▼
             ReaScript / Lua
                    │
                    ▼
             MUSIC STATE
                    │
                    ▼
             Web Controller
                    │
                    ▼
                Celular
```

---

# 18. Primera versión — alcance

La primera implementación debe limitarse a:

### Entrada

- Posición actual de REAPER.
- Markers existentes.
- Tempo.
- Time signature.
- Metadata armónica almacenada en Project ExtState.

### Metadata armónica

Por compás:

```text
bar → chord
```

Ejemplo:

```text
1 → Cmaj7
2 → Am7
3 → Dm7
4 → G7
```

### Salida

El controlador debe poder conocer:

```text
current_bar
current_beat
current_section
current_chord
next_chord
tempo
time_signature
```

### Fuera del alcance inicial

- Regions como sistema de metadata.
- Escalas.
- Roman numerals.
- Análisis armónico.
- Lyrics.
- Cues avanzados.
- Múltiples acordes por beat.
- Edición de armonía desde el celular.

Estos elementos quedan contemplados como extensiones futuras.

---

# 19. Principio de diseño

La arquitectura debe seguir este principio:

> **REAPER mantiene el estado temporal y estructural; Project ExtState almacena la metadata musical adicional; ReaScript unifica ambos mundos; el Web Controller consume un estado musical simplificado.**

Esto evita sobrecargar Markers con información que no corresponde a su función actual y permite ampliar posteriormente el sistema sin cambiar la estructura básica del proyecto.