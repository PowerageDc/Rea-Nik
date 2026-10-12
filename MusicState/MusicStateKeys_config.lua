-- MusicStateKeys_config.lua
-- Atajos globales del Helper, en datos puros (sin logica). Se carga con
-- dofile desde Nik_MusicState_Helper.lua y lo interpreta
-- MusicStateKeys_common_logic.lua. Ver 01_CONVENCIONES.md (config en codigo).
--
-- Campos de cada binding:
--   id                    nombre unico (se usa en los avisos de consola)
--   key                   nombre de tecla de ReaImGui sin prefijo: 'W', 'End',
--                         'Escape', 'F4', 'LeftArrow', 'Space', 'Enter'...
--   mods                  opcional: { 'ctrl', 'shift', 'alt', 'super' }.
--                         Sin mods, solo actua con la tecla sola.
--   cmd                   ID numerico de accion de REAPER (Main_OnCommand), o
--                         nombre de una accion con ID estable entre PCs
--                         ('_SWS_...', '_S&M_...'; copiar con "Copy selected
--                         action command ID"). Los '_RS...' de scripts
--                         cambian entre PCs: avisa por consola...
--   action                ...o nombre de una funcion Lua registrada por el
--                         Helper en Keys.init (uno de los dos, no ambos)
--   autorepeat            true (valores de abajo) o { delay=, rate= } propio
--   ignore_item_active    true: actua aunque haya un campo en edicion
--                         (para teclas que no se tipean, como F4)
--   ignore_popup          true: actua aunque haya un popup o modal abierto

return {
  -- Repeticion por hold: tras delay segundos apretada empieza a repetir
  -- cada rate segundos. El piso real es el frame del defer (~30 ms).
  autorepeat = { delay = 0.5, rate = 0.15 },

  -- Teclas de los modales (Keys.modal): cancelar y confirmar.
  modal = { cancel = { 'Escape' }, confirm = { 'Enter', 'KeypadEnter' } },

  global = {
    { id = 'transport.playstop',   key = 'Space',      cmd = 40044 },
    { id = 'transport.playpause',  key = 'Enter',      cmd = 40073 },
    { id = 'nav.measure_prev',     key = 'LeftArrow',  cmd = 41041, autorepeat = true },
    { id = 'nav.measure_next',     key = 'RightArrow', cmd = 41040, autorepeat = true },
    -- Marker anterior / siguiente: ´ y ç (Apostrophe y Slash en este teclado).
    { id = 'nav.marker_prev',      key = 'Apostrophe', cmd = 40172 },
    { id = 'nav.marker_next',      key = 'Slash',      cmd = 40173 },

    { id = 'time.go_start',        key = 'W',          cmd = 40042 },  -- inicio del proyecto
    { id = 'time.go_end',          key = 'End',        cmd = 40043 },  -- fin del proyecto
    { id = 'time.clear_selection', key = 'Escape',     cmd = 40020 },  -- quita seleccion de tiempo y loop

    -- Foco Helper -> REAPER. La vuelta (REAPER -> Helper) es el one-shot
    -- Nik_MusicState_FocusHelper.lua asignado a esta misma tecla.
    { id = 'host.focus',           key = 'F4',         action = 'host_focus',
      ignore_item_active = true, ignore_popup = true },

    -- Cierra el Helper (la apertura es el propio script en el Action List,
    -- asignado a esta misma tecla). Con guards normales: no actua con un
    -- campo en edicion ni con un modal abierto.
    { id = 'host.close',           key = 'F5',         action = 'close_helper' },
  },

  -- Bindings por tab: solo actuan con esa tab dibujada. Mismos campos que
  -- los globales, mas override = true para pisar una global. Undo de REAPER
  -- solo en Lyrics: sus ediciones son puntos de undo del proyecto; las de
  -- Armonia/Cues viven en el Helper y no pasan por el undo de REAPER.
  tab = {
    Lyrics = {
      { id = 'lyrics.undo', key = 'Z', mods = { 'ctrl' }, cmd = 40029 },
      { id = 'lyrics.redo', key = 'Z', mods = { 'ctrl', 'shift' }, cmd = 40030 },
    },
  },
}
