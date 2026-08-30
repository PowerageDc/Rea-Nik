# Guía de Deploy — Control Remoto Web (sala de ensayo)

Fecha de armado: 2026-08-29
Referencia: `nsaudio_remote_control.html`

---

## 0. Antes de salir de casa

- [ ] Confirmar en tu carpeta `Custom/` los nombres reales de los 4 scripts
      marcados como "verificar" en la tabla de la sección 2 (PlayRate Set,
      PlayRate TogglePreservePitch, TabPrev, TabNext).
- [ ] Armar una carpeta única de deploy con:
  - [ ] Todos los `.lua` ejecutables (`Nik_*`, `NikRemote_*`) involucrados
  - [ ] Los módulos de soporte `_common_logic.lua` que consumen (mínimo
        `StemBus_common_logic.lua`, `ReaPitchBus_common_logic.lua`, y
        cualquier otro que exista para PlayRate/ProjectTabs/TrackVis/RemoteState)
  - [ ] `nsaudio_remote_control.html`
- [ ] Proyecto REAPER template ("Practice Rig - Stems Player") con la
      estructura de tracks/Stem Bus idéntica a la que esperan los scripts.

---

## 1. Checklist de archivos en la PC destino

- [ ] Copiar carpeta de deploy completa a la ubicación de scripts custom de
      esa PC (mismo criterio de organización que en tu PC principal).
- [ ] Verificar que en `reaper_www_root` (o la carpeta que uses para el web
      control) estén presentes, junto al HTML:
  - `main.js`
  - `manifest.json`
  - `sw.js`
  - `apple-touch-icon.png`
  (normalmente ya están si es el `reaper_www_root` default de REAPER —
  el HTML los referencia pero no los reemplaza).
- [ ] REAPER v7.79 y SWS/S&M Extensions instalados en destino (mismas
      versiones que tu PC, para evitar diferencias de API).
- [ ] Preferences → Control/OSC/web → Web browser interface: habilitada,
      apuntando a la carpeta correcta, puerto anotado, password si aplica.

---

## 2. Los 10 Command IDs (`_RS...`) a re-registrar

Los IDs se hashean del path absoluto del script → cambian por PC. Hay que
registrar cada uno en el Action List de la PC destino y pegar el ID nuevo
en el HTML.

| # | Variable en el HTML | Botón / función | Script (Action List) |
|---|----------------------|------------------|------------------------|
| 1 | `REAPITCH_CMD_SET` | Modal Semitonos → drag/set | `NikRemote_ReaPitch_SetSemitones.lua` |
| 2 | `REAPITCH_CMD_TOGGLE` | Toggle "ReaPitch: —" | `NikRemote_ReaPitch_ToggleEnable.lua` |
| 3 | `PLAYRATE_CMD_SET` | Modal Playrate → drag/set | `NikRemote_PlayRate_Set.lua` ⚠️ verificar nombre |
| 4 | `PLAYRATE_CMD_TOGGLE_PP` | Checkbox Preserve Pitch | `NikRemote_PlayRate_TogglePreservePitch.lua` ⚠️ verificar nombre |
| 5 | `TRACKVIS_CMD_REFRESH` | Panel visibilidad TCP → "Aplicar" | `Nik_TrackVis_Refresh.lua` |
| 6 | `STATE_POLL_CMD` | Poll de fondo (proyecto/playrate/reapitch/markers) | `Nik_RemoteState_Poll.lua` |
| 7 | `PROJECTTABS_CMD_READ` | Modal Proyectos → al abrir | `Nik_ProjectTabs_Read.lua` |
| 8 | `PROJECTTABS_CMD_SELECT` | Modal Proyectos → seleccionar tab | `Nik_ProjectTabs_Select.lua` |
| 9 | inline, línea ~1585 | Botón "⏮ Tab" | `NikRemote_TabPrev.lua` ⚠️ verificar nombre |
| 10 | inline, línea ~1587 | Botón "Tab ⏭" | `NikRemote_TabNext.lua` ⚠️ verificar nombre |

**Orden recomendado:**
1. Registrar primero los módulos `_common_logic.lua` en la carpeta (NO se
   registran como acción, solo tienen que estar presentes en disco).
2. Registrar los 10 ejecutables en el Action List, anotando cada Command ID
   apenas se genera (columna extra en esta tabla, a mano, sirve).
3. Recién al final, editar el HTML en un solo pase con los 10 IDs nuevos.

---

## 3. Edición del HTML (un solo pase)

Reemplazar cada valor `_RS...` en las líneas correspondientes:

```
Línea ~204: REAPITCH_CMD_SET    = "_RS..."
Línea ~205: REAPITCH_CMD_TOGGLE = "_RS..."
Línea ~209: PLAYRATE_CMD_SET       = "_RS..."
Línea ~210: PLAYRATE_CMD_TOGGLE_PP = "_RS..."
Línea ~214: TRACKVIS_CMD_REFRESH = "_RS..."
Línea ~218: STATE_POLL_CMD = "_RS..."
Línea ~234: PROJECTTABS_CMD_READ   = "_RS..."
Línea ~235: PROJECTTABS_CMD_SELECT = "_RS..."
Línea ~1585: wwr_req('40667;_RS...;'+NIK_ONDEMAND_READS)   -- botón ⏮ Tab
Línea ~1587: wwr_req('40667;_RS...;'+NIK_ONDEMAND_READS)   -- botón Tab ⏭
```

---

## 4. Test rápido post-deploy

- [ ] Abrir el HTML en el celular (misma red que la PC).
- [ ] Verificar que `nikActiveProjectName` (arriba, tab bar) muestre el
      nombre del proyecto → confirma que `STATE_POLL_CMD` quedó bien.
- [ ] Probar un botón de cada grupo (no los 10 uno por uno, alcanza con
      uno representativo por bloque):
  - [ ] Semitonos (set + toggle)
  - [ ] Playrate (set + toggle preserve pitch)
  - [ ] Visibilidad de tracks (aplicar)
  - [ ] Modal Proyectos (leer + seleccionar tab)
  - [ ] Botones ⏮ Tab / Tab ⏭

---

## 5. Notas / riesgos conocidos

- **Fuente Open Sans vía Google Fonts (`fonts.googleapis.com`)**: si la sala
  no tiene internet, cae a fallback sans-serif. No rompe funcionalidad,
  solo estético.
- **Fully Kiosk Browser** como launcher en el celular (en vez de PWA vía
  Chrome) — necesario porque el WebAPK de Chrome requiere URL pública; IPs
  LAN degradan a shortcut simple.
- Si algún Command ID no matchea (botón no responde), lo más probable es
  que el script no se haya registrado bien en el Action List de esa PC, o
  que falte un módulo `_common_logic.lua` en la misma carpeta relativa.
