# FxWindow — ventana flotante de VSTi para grabar en OBS

Acomoda la ventana flotante de un VSTi (posición y tamaño) según un config por
nombre de FX, para que el recorte de la captura de pantalla de OBS caiga
siempre en el mismo lugar en cualquier proyecto. Hay una escena de OBS por
VSTi (Modo Bass 2, Ample Guitar L, etc.).

## 1. Archivos (`FxWindow/`)

| Archivo | Rol |
|---|---|
| `FxWindow_config.lua` | Tabla editada a mano, una entrada por VSTi |
| `FxWindow_common_logic.lua` | Módulo: medición, aplicación y verificación |
| `Nik_FxWindow_Apply.lua` | Aplica el config a los tracks seleccionados |
| `Nik_FxWindow_Capture.lua` | Imprime la línea de config de los FX con la ventana abierta |

Requiere JS_ReaScriptAPI (instalar desde ReaPack). Sondas de diagnóstico en
`Tests-Debug/`: `Nik_FxWindow_ProbeRect.lua` (rect de ventana y cliente),
`Nik_FxWindow_ProbeChildren.lua` (ventana y ventanas hijas) y
`Nik_FxWindow_ProbeNudge.lua` (efecto de distintos cambios de tamaño sobre la
vista del plugin).

## 2. Config

```lua
{ match = "MODO BASS", x = 196, y = 45, w = 1599, h = 991, view_w = 1570, view_h = 964 },
```

- `x, y, w, h`: área cliente de la ventana flotante, en píxeles de pantalla
  (sin bordes ni barra de título). Es lo que ve una captura de pantalla.
- `view_w, view_h` (opcionales): tamaño esperado de la vista del plugin (hija
  `reaperPluginHostWrapProc`). Si están, Apply verifica también eso.
- `match`: subcadena del nombre del FX, sin distinguir mayúsculas. Gana la
  primera coincidencia: las entradas específicas van antes que las genéricas
  (por ejemplo, una variante de Ample Guitar antes de `AMPLE GUITAR`).

## 3. Flujo para un VSTi nuevo

1. Abrir la ventana flotante y llevar la UI del plugin a su escala máxima (si
   tiene handle de escala con tope).
2. Ajustar la ventana para que calce con la UI, sin margen blanco.
3. Seleccionar el track y correr `Nik_FxWindow_Capture.lua`; pegar la línea en
   `FxWindow_config.lua`.
4. Armar la escena de OBS contra esa ventana.

A partir de ahí, `Nik_FxWindow_Apply.lua` deja la ventana igual en cualquier
proyecto.

## 4. Cómo aplica Apply

- Trabaja sobre los tracks seleccionados y recorre toda la cadena de cada uno:
  busca por nombre de FX, no por índice.
- Abre la ventana flotante y espera `INIT_DELAY` antes del primer ajuste, para
  que el plugin termine de armar su UI.
- Ubica el área cliente en el rect del config. El grosor de bordes y barra de
  título se mide en cada ejecución.
- A los `VERIFY_DELAY` compara cliente y vista. Si no coinciden, encoge la
  ventana `SHRINK` px y vuelve al tamaño exacto, hasta `MAX_RETRIES` veces.
- Reporta en consola: OK, DIFIERE (con las diferencias), sin ventana flotante,
  o instrumento del track sin entrada en el config.

Las constantes están al comienzo del bloque principal de `Nik_FxWindow_Apply.lua`.

## 5. Hallazgos

- La captura de ventana de OBS no ve las ventanas GDI de REAPER (FX, browser,
  undo history), por eso se usa captura de pantalla. Dockear el VSTi en el
  arrange no sirve con Modo Bass 2: no deja agrandar la UI y el handle queda
  fuera de vista.
- El `FLOATPOS` del `.rpp` solo existe si el plugin se guardó flotante, y
  reescribir el chunk recarga los FX: no sirve como fuente de coordenadas.
- El área cliente incluye la barra de controles de REAPER (preset, `+`,
  `Param`, `UI`); la UI del plugin es la hija `reaperPluginHostWrapProc`. La
  clase `JUCE_*` cambia en cada ejecución.
- Modo Bass 2 solo reajusta su UI ante un cambio real de tamaño de la ventana
  y después de armarse: un +1 px y volver no alcanza, y redimensionar
  inmediatamente después de abrir deja la vista chica.
- Modo Bass 2 tiene un handle de escala con tope. Con la ventana más grande que
  la UI, el excedente se pinta de blanco y Apply no logra acomodar. La escena se
  arma contra la UI al tope.
- Las coordenadas son de pantalla: la escena depende del mismo monitor y del
  mismo escalado de Windows con los que se armó.

## 6. Pendientes

- Recapturar Ample Guitar L para completar `view_w` y `view_h`, y probar Apply
  con ese VSTi.
- Sumar entradas (y una genérica para las variantes de Ample Guitar) a medida
  que se armen las escenas de los demás VSTi (Ample Bass, otros de bajo y de
  guitarra).