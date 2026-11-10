# MusicVideo — videos de instrumento y de letra

Pipeline para grabar videos de práctica con un VSTi sin equivalente a KeySight
(MODO Bass, Ample Guitar Luthier) y videos de letra: REAPER reproduce, OBS
compone y graba, `ffmpeg` agrega los fades. Convenciones generales en
`01_CONVENCIONES.md`.

No es una feature de REAPER ni se publica por ReaPack: son herramientas de
escritorio de esta PC (`.bat`, archivos de OBS), como `ProjectPack/`. No hay
nada que registrar en el Action List.

## 1. Alcance

Tres tipos de video, que comparten todo el pipeline y solo varían las capas de
la escena de OBS:

| Video | Capas |
|---|---|
| Instrumento | fondo + captura del VSTi (con recorte y máscara) + tira de acordes |
| Solo letra | fondo + UI del cantante |
| Instrumento + letra | las dos de arriba combinadas |

La letra es una capa más (Browser Source), no un "instrumento". La armonía en
subtítulos para los videos de piano de KeySight es otra feature:
`features/subtitle_export.md`.

## 2. Pipeline

```
REAPER (ASIO) ──master──► ReaRoute 1/2 ──► OBS (obs-asio) ─┐
REAPER (web) ──UI acordes/letra──► Browser Source ─────────┼─► grabación .mkv
Ventana del VSTi ──Captura de pantalla + recorte/máscara───┤        │
Fondo (PNG) ───────────────────────────────────────────────┘        ▼
                                              MusicVideo_Fades.bat (ffmpeg) ─► *_final.mp4
```

## 3. Software y rol

| Software | Rol |
|---|---|
| REAPER | reproduce el MIDI y sirve la UI web (acordes, letra) |
| ReaRoute | lleva el master de REAPER a OBS como entrada ASIO |
| OBS 33.0.1 | compone la escena, graba el video con el audio |
| obs-asio (dll 3.2.1) | fuente *ASIO Input Capture*; solo captura entradas, no salidas de una DAW |
| ffmpeg / ffprobe | fades y mp4 final (deben estar en el PATH) |
| Photoshop | máscaras de imagen a medida |

Interfaz de audio: M-Audio Fast Track Ultra 8, sin loopback interno. REAPER y
OBS trabajan a 48 kHz.

## 4. Archivos del repo

```
MusicVideo\
├── MusicVideo_Fades.bat
├── MusicVideo_MakeMask.ps1      regenera las máscaras verticales de masks\
├── masks\                       máscaras PNG de los filtros de OBS
└── obs\
    ├── css\
    │   ├── chords_base.css      fondo transparente y margen del Browser Source
    │   ├── chords_ModoBass.css  ajustes de la escena MODO Bass
    │   └── lyrics.css           UI del cantante
    ├── profile\                 copia de basic.ini del perfil
    └── scenes\
        └── MusicVideo.json      colección completa exportada de OBS
```

- Colección y perfil de OBS se llaman `MusicVideo`. Escenas: `MODO Bass` y
  `Ample Guitar Luthier`.
- La colección vive en un solo JSON: OBS exporta la colección entera, no una
  escena. Contiene rutas absolutas de esta PC (los fondos) y el CSS de cada
  Browser Source.
- Los `.css` de `obs\css\` son la referencia legible; lo que OBS usa es lo
  pegado en el campo de CSS de cada fuente (base + archivo del instrumento).
- Los fondos son PNG en carpetas dentro de `Imágenes\`, fuera del repo.
- El perfil guarda lo que no viaja en la colección: canvas, fps, encoder,
  formato, audio y atajos de grabación.

## 5. Escena de OBS

- **Canvas:** 1920×1080 base y de salida, 60 fps. Con base y salida iguales, el
  filtro de reescalado global queda deshabilitado; el que cuenta es el *Scale
  Filtering* `Lanczos` de la fuente del mango.
- **Orden de capas:** fondo abajo, captura del VSTi encima, Browser Source de
  acordes arriba.
- **Captura del VSTi:** *Captura de pantalla* del monitor (1920×1080) con la
  ventana flotante del plugin visible y sin nada encima. Una fuente nueva por
  escena (`Captura MODO Bass`, `Captura Ample Guitar`): las fuentes son de la
  colección, y compartir una entre escenas comparte también el recorte.
- **Recorte:** todo en el filtro *Crop/Pad*, con el *Crop* de *Edit Transform*
  en 0. Los filtros se aplican antes que el recorte de *Edit Transform*; mezclar
  los dos lugares desalinea la máscara. Los valores son píxeles de pantalla:
  si la ventana del plugin se mueve `dx`/`dy`, izquierda y arriba suman, derecha
  y abajo restan.
- **Escalado:** *Edit Transform* con límites *Llenar ancho* (ancho 1920,
  alineación al centro, X 960). El alto de los límites se iguala al alto real
  del mango escalado (210 en MODO Bass) para que el recuadro lo abrace; Y es el
  centro del mango en el canvas y es lo único que se mueve entre composiciones.
- **Máscara:** filtro *Máscara de imagen/Mezcla* debajo del *Crop/Pad*, tipo
  *Máscara alfa (canal de color)*, con *expandir* activado para que se ajuste
  al recorte. Si se mueve el PNG, hay que reapuntar la ruta en el filtro.
- **Browser Source (acordes):** URL de la UI del instrumentista servida por el
  servidor web de REAPER (`nsaudio_prompter.html`, puerto de la interfaz web),
  60 fps personalizados, propiedades 1920×1080 y transformación a 2304×1296.
  Se dibuja dentro de OBS, no depende de ninguna ventana visible.

## 6. Audio

- REAPER permanece en ASIO: con Direct Sound el audio de OBS sonaba peor y con
  jitter al arrancar.
- El master de REAPER se envía además a **ReaRoute 1/2** (sin reemplazar la
  salida a la placa, para seguir oyendo).
- En OBS: fuente *ASIO Input Capture*, dispositivo ReaRoute ASIO, canales 1/2,
  estéreo, 48 kHz en REAPER y en OBS.
- La sincronización con la UI web quedó bien sin corregir. Si hiciera falta:
  *Propiedades de audio avanzadas* → *Desfase de sincronización*, en
  milisegundos; es un valor fijo del sistema.
- El audio del video es una copia digital del master de REAPER.

## 7. Encoder

Salida en modo *Avanzado*, grabación en `mkv`, NVENC H.264, *QP constante* 16,
intervalo de fotogramas clave 0 s, preajuste P5, ajuste de calidad alta, dos
pasos, perfil `main`, mirar hacia adelante y cuantización adaptativa activados,
2 B-frames sin referencia. Audio AAC 320 kbps. Peso medido: unos 10 MB por
minuto.

## 8. Cómo grabar un video

1. Abrir el proyecto, con el plugin flotante a su tamaño y posición de la
   escena.
2. Elegir la escena en OBS. Iniciar y detener la grabación con los atajos
   globales (con OBS minimizado, porque se captura la pantalla).
3. Iniciar la grabación, esperar 1,5 s o más y dar play en REAPER.
4. Al terminar el audio, esperar 1,5 s o más y detener la grabación. Los
   márgenes dejan el fade-in en silencio y el fade-out después del final.
5. Arrastrar el `.mkv` sobre `MusicVideo_Fades.bat`.

## 9. Fades

`MusicVideo_Fades.bat` calcula la duración con `ffprobe` y aplica fade-in y
fade-out de `FADE` segundos (variable al inicio del `.bat`, 1 por defecto) en
video y audio. Recodifica con `libx264` (CRF 14, preset slow) y AAC 320 kbps, y
deja `<nombre>_final.mp4` junto al original.

## 10. CSS del Browser Source

El CSS depende de nombres de la UI del prompter (`web/musicstate-ui/`); al
renombrar alguno, OBS falla en silencio:

- variables `--ms-bg` y `--ms-divider-color`
- clases `.ms-top-block` y `.ms-cue-divider` (ocultas con `visibility: hidden`
  para conservar el layout)

`chords_base.css` lleva el fondo transparente (`--ms-bg`, `body`); cada
instrumento suma su archivo con los ajustes de estilo.

## 11. Máscaras

- **Verticales** (MODO Bass): PNG de 16×130 px, blancas en todo el ancho y con
  degradado suave (smoothstep) de 2, 4 o 6 px arriba y abajo; con *expandir* se
  estiran al recorte. Se usa la de 2 px. `MusicVideo_MakeMask.ps1` las regenera
  (parámetros `-Width`, `-Height`, `-Feather`, `-OutDir`).
- **Por VSTi:** `mascara_<codigo>[_<variante>].png`, con el código corto del
  VSTi. El tamaño no va en el nombre; se anota en esta tabla. El PSD lleva el
  mismo nombre, está junto al PNG y lo ignora git (`.gitignore`): no se
  respalda con el repo.

  | Archivo | Escena | Recorte (ancho × alto) | PSD |
  |---|---|---|---|
  | `mascara_agl.png` | Ample Guitar Luthier | 1340 × 530 | `mascara_agl.psd` |

- **A medida** (Ample Guitar): exportar un frame a 1:1 del recorte, trazar la
  forma en Photoshop (Pluma con trazados, o *Seleccionar sujeto* y *Seleccionar
  y aplicar máscara*), suavizar 1–2 px y guardar PNG blanco/negro de las mismas
  dimensiones del recorte. La máscara queda atada al layout de la UI del plugin.

## 12. Decisiones y descartes

- *Captura de ventana* no lista las ventanas flotantes de REAPER (plugins, FX
  Chain, docker flotante) y *Captura de juego* no funcionó. Se usa *Captura de
  pantalla* con recorte.
- Con el plugin acoplado en un docker de la ventana principal sí se ve en OBS,
  pero la UI tiene tope de tamaño y no se puede desplazar: descartado.
- Subir la resolución con NVIDIA DSR o un monitor virtual: descartado por
  complejidad.
- Standalone del VSTi más un puerto MIDI virtual (loopMIDI): plan B, no todos
  los plugins tienen standalone.
- Medir el primer dot de beat en el video para alinear un WAV externo:
  descartado por frágil; el audio entra por ReaRoute y queda alineado.
- obs-asio solo captura entradas: por eso ReaRoute.
- Una sola colección con una escena por instrumento, no una colección por
  instrumento.
- Mango dibujado por script desde el MIDI (nítido a cualquier resolución, pero
  con la asignación de cuerda y traste a cargo del script): no se hizo.

## 13. Pendientes

- **Ample Guitar:** Browser Source de acordes y su `chords_AmpleGuitar.css`.
- **Videos de letra:** escena con fondo, UI del cantante transparente y
  `lyrics.css` (ver qué variable de fondo usa); fades iguales.
- **Fondo de KeySight:** ver si se puede exportar como video corto y repetirlo
  (loop o ping-pong con `ffmpeg`); hoy se usan PNG.
- **Zoom en el Browser Source (MODO Bass):** para que el texto se dibuje
  nítido en vez de escalarse 1,2× en OBS:
  1. Propiedades de la fuente: ancho 2304, alto 1296.
  2. En `chords_ModoBass.css`: `html { zoom: 1.2; }`.
  3. *Edit Transform*: tamaño 2304×1296 sin escalado, alineación al centro y la
     misma posición.
  4. Verificar que el layout no se rompa (unidades `vw`/`vh` de la UI) y mirar
     los fotogramas perdidos en *Ver → Estadísticas*.
- Revisar el color (NV12, Rec. 709, rango parcial) en los ajustes avanzados de OBS.
- Fondo transparente por parámetro de URL (`?transparent=1`) en la UI, en vez
  de CSS en OBS; evaluar un `?theme=` por instrumento.
- Comprobar si la posición de la ventana del plugin se conserva al reabrir el
  proyecto, para no recalcular el recorte.