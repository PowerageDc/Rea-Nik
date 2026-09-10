-- ============================================================
-- TEST MINIMO -- ReaImGui (REAPER 7.79)
-- Valida dos comportamientos antes de llevarlos a la UI real:
--
--  A) Input de texto + boton "Agregar", donde:
--       - ENTER hace commit
--       - Click en "Agregar" hace commit
--       - Click en OTRO lugar de la ventana (despues de tipear)
--         NO debe hacer commit
--
--     Hipotesis validada con los flags de debug en pantalla:
--       IsItemFocused NO sirve para distinguir: clickear en una
--       zona no-focusable (Text/Dummy) dentro de la misma ventana
--       no le roba el foco al input, asi que queda en true igual
--       que con ENTER (solo cambia si se clickea OTRO widget
--       focusable, como el boton).
--
--     Señal que si funciona: ENTER y la deactivation ocurren en
--     el MISMO frame (es la propia tecla la que deactiva el item).
--     Un click afuera deactiva sin que se haya presionado Enter
--     ese frame. Entonces:
--       IsItemDeactivatedAfterEdit == true
--       Y (IsKeyPressed(Key_Enter) O IsKeyPressed(Key_KeypadEnter))
--     -> commit real por ENTER.
--
--  B) Captura de teclas dentro de la ventana ImGui para mover
--     el cursor de edicion de REAPER (compas / marker) sin
--     necesidad de enfocar la ventana principal de REAPER.
--     Sirve para confirmar si ReaImGui "roba" el foco de teclado
--     de forma exclusiva, o si el atajo nativo de REAPER se
--     dispara en paralelo (double movimiento = filtracion).
--
-- Como usar: Action List > New action > Load ReaScript... y
-- correrlo. Dejar la ventana con foco (click adentro) para
-- probar la seccion B con las flechas del teclado.
-- ============================================================

-- Se crea el context con config_flags=0 para desactivar la
-- navegacion por teclado nativa de ImGui (NavEnableKeyboard),
-- que es la responsable del recuadro celeste que salta entre
-- widgets al usar las flechas. IsKeyPressed no depende de ese
-- flag, asi que la lectura de teclas para compas/marker sigue
-- funcionando igual sin ese efecto visual.
local ctx = reaper.ImGui_CreateContext('Test input+teclado', 0)

-- ---------- CONFIG: completar despues de validar en REAPER ----------
-- Action List (main section) > buscar "measure" / "marker" >
-- click derecho > "Copy selected action command ID" (o mirar el
-- ID en la barra de estado de la ventana de acciones).
-- Dejar en nil lo que todavia no se confirmo: el boton lo avisa
-- solo en el log en vez de romper.
local CMD_MEASURE_PREV = 41041
local CMD_MEASURE_NEXT = 41040
local CMD_MARKER_PREV  = 40172
local CMD_MARKER_NEXT  = 40173

-- Teclas asignadas dentro de la ventana (cambiar aca si se
-- prefieren otras). Por defecto: flechas izq/der = compas,
-- flechas arriba/abajo = marker.
local KEY_MEASURE_PREV = reaper.ImGui_Key_LeftArrow()
local KEY_MEASURE_NEXT = reaper.ImGui_Key_RightArrow()
local KEY_MARKER_PREV  = reaper.ImGui_Key_DownArrow()
local KEY_MARKER_NEXT  = reaper.ImGui_Key_UpArrow()

-- Play/Stop y Play/Pause son comandos distintos en REAPER.
-- Space = play/stop (vuelve al punto de partida al detener).
-- Enter = play/pause (retiene la posicion al pausar).
-- Disparan solo si NINGUN item (input, dropdown, etc.) esta
-- activo, via IsAnyItemActive.
local CMD_PLAYSTOP  = 40044
local CMD_PLAYPAUSE = 40073

-- ---------- ESTADO: seccion A (input + lista) ----------
local buf = ''
local items = {}
local last_event = '(ninguno todavia)'
local dbg_active, dbg_focused, dbg_deact_edit, dbg_changed = false, false, false, false
local consumed_enter = false -- se resetea cada frame en loop()

-- ---------- ESTADO: seccion B (teclado / transporte) ----------
local key_log = {}

local function log_key(txt)
  table.insert(key_log, 1, string.format('%.2fs  %s', reaper.time_precise(), txt))
  if #key_log > 6 then table.remove(key_log) end
end

local function run_action(cmd_id, label)
  if not cmd_id then
    log_key(label .. ' -> SIN CONFIGURAR (ver CONFIG arriba)')
    return
  end
  local before = reaper.GetCursorPositionEx(0)
  reaper.Main_OnCommand(cmd_id, 0)
  local after = reaper.GetCursorPositionEx(0)
  log_key(string.format('%s: %.3f -> %.3f', label, before, after))
end

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 480, 600, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Test minimo', true, reaper.ImGui_WindowFlags_NoNav())

  if visible then
    consumed_enter = false -- reset por frame, antes de la seccion A

    -- ======================================================
    -- SECCION A -- Input + boton, SIN flag EnterReturnsTrue.
    -- El buffer se sincroniza en cada tecla, asi "Agregar"
    -- siempre tiene el texto real tipeado.
    -- ======================================================
    reaper.ImGui_SeparatorText(ctx, 'A) Input + boton (agregar a lista)')

    local changed, new_buf = reaper.ImGui_InputText(ctx, '##item', buf)
    if changed then buf = new_buf end

    dbg_changed    = changed
    dbg_active     = reaper.ImGui_IsItemActive(ctx)
    dbg_focused    = reaper.ImGui_IsItemFocused(ctx)
    dbg_deact_edit = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)

    local enter_key_this_frame =
      reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false) or
      reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
    local enter_commit = dbg_deact_edit and enter_key_this_frame

    -- El input se desactiva en el mismo frame en que se presiona
    -- Enter, asi que para cuando llega la seccion B, IsAnyItemActive
    -- ya da false y el Enter "libre" volveria a dispararse ahi como
    -- play/pause. Este flag marca el Enter como ya consumido por el
    -- commit del input, para ese mismo frame.
    consumed_enter = enter_commit

    reaper.ImGui_SameLine(ctx)
    local clicked = reaper.ImGui_Button(ctx, 'Agregar')

    if (enter_commit or clicked) and buf ~= '' then
      table.insert(items, buf)
      last_event = (enter_commit and 'commit por ENTER: ' or 'commit por BOTON: ') .. buf
      buf = ''
    end

    reaper.ImGui_Text(ctx, 'Ultimo evento: ' .. last_event)
    reaper.ImGui_Spacing(ctx)

    reaper.ImGui_TextWrapped(ctx,
      'Prueba: (1) tipear + ENTER, (2) tipear + click en "Agregar", ' ..
      '(3) tipear + click en la zona vacia de abajo (sin tocar el ' ..
      'boton). Los casos 1 y 2 deben agregar a la lista; el caso 3 NO.')

    if reaper.ImGui_TreeNode(ctx, 'debug (flags crudos del InputText)') then
      reaper.ImGui_Text(ctx, ('changed=%s  active=%s  focused=%s  deactivated_after_edit=%s')
        :format(tostring(dbg_changed), tostring(dbg_active), tostring(dbg_focused), tostring(dbg_deact_edit)))
      reaper.ImGui_Text(ctx, 'enter_key_this_frame=' .. tostring(enter_key_this_frame))
      reaper.ImGui_TreePop(ctx)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, 'Lista:')
    for i, v in ipairs(items) do
      reaper.ImGui_BulletText(ctx, i .. '. ' .. v)
    end

    reaper.ImGui_Dummy(ctx, -1, 40)
    reaper.ImGui_Text(ctx, '(zona vacia para probar el caso 3 -- click aca)')

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- ======================================================
    -- SECCION B -- teclado como transport / navegacion
    -- ======================================================
    reaper.ImGui_SeparatorText(ctx, 'B) Navegacion por teclado / botones')

    reaper.ImGui_TextWrapped(ctx,
      'Con esta ventana enfocada (click adentro), probar flechas ' ..
      'izq/der (compas) y arriba/abajo (marker). Si el cursor de ' ..
      'edicion en REAPER se mueve el doble de lo esperado (o ves el ' ..
      'atajo nativo dispararse aparte), ReaImGui NO esta capturando ' ..
      'la tecla de forma exclusiva.')

    if reaper.ImGui_IsWindowFocused(ctx) then
      if reaper.ImGui_IsKeyPressed(ctx, KEY_MEASURE_PREV, false) then
        run_action(CMD_MEASURE_PREV, 'compas <- (tecla)')
      end
      if reaper.ImGui_IsKeyPressed(ctx, KEY_MEASURE_NEXT, false) then
        run_action(CMD_MEASURE_NEXT, 'compas -> (tecla)')
      end
      if reaper.ImGui_IsKeyPressed(ctx, KEY_MARKER_PREV, false) then
        run_action(CMD_MARKER_PREV, 'marker <- (tecla)')
      end
      if reaper.ImGui_IsKeyPressed(ctx, KEY_MARKER_NEXT, false) then
        run_action(CMD_MARKER_NEXT, 'marker -> (tecla)')
      end

      -- Play/Stop y Play/Pause: solo si no hay NINGUN item activo
      -- (input, dropdown abierto, etc). Este guard es global al ctx,
      -- no por widget, asi que escala aunque la UI real tenga muchos
      -- inputs/listas -- no hace falta trackear cada uno a mano.
      if not reaper.ImGui_IsAnyItemActive(ctx) then
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space(), false) then
          run_action(CMD_PLAYSTOP, 'play/stop (tecla)')
        end
        -- consumed_enter: el Enter que ya comiteo el input en la
        -- seccion A no debe ademas pausar el transporte aca.
        if not consumed_enter and (
          reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false) or
          reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
        ) then
          run_action(CMD_PLAYPAUSE, 'play/pause (tecla)')
        end
      end
    end

    if reaper.ImGui_Button(ctx, '<< Compas') then run_action(CMD_MEASURE_PREV, 'compas << (boton)') end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Compas >>') then run_action(CMD_MEASURE_NEXT, 'compas >> (boton)') end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, '<< Marker') then run_action(CMD_MARKER_PREV, 'marker << (boton)') end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'Marker >>') then run_action(CMD_MARKER_NEXT, 'marker >> (boton)') end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, ('Cursor actual: %.3f s'):format(reaper.GetCursorPositionEx(0)))
    reaper.ImGui_Text(ctx, 'Log (mas reciente primero):')
    for _, line in ipairs(key_log) do
      reaper.ImGui_BulletText(ctx, line)
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
