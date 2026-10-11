-- MusicStateKeys_common_logic.lua
-- Despacho central de atajos de teclado del Helper. Los bindings globales
-- vienen de MusicStateKeys_config.lua; cada tab suma los suyos con
-- Keys.add_tab (press con fn, o hold consultado con Keys.held).
--
-- Ciclo del frame (todo dentro del `if visible` del Helper):
--   Keys.begin_frame(ctx)   al inicio: foto de IsAnyItemActive
--   Keys.set_tab(nombre)    dentro de cada BeginTabItem
--   Keys.dispatch(ctx)      justo antes de ImGui_End
-- El despacho al FINAL del frame ve tambien lo que paso durante el: tab
-- dibujada, popups abiertos, teclas consumidas. La foto del inicio evita
-- que el Enter que commitea un input dispare tambien Play/Pause.
--
-- Un binding actua solo si: la ventana tiene el foco (con ChildWindows), no
-- habia un item activo ni un popup abierto al inicio del frame ni los hay
-- ahora, y la tecla no fue consumida este frame (Keys.consume). La foto del
-- popup evita que el Enter o el Esc que cierra un modal dispare tambien el
-- atajo global: CloseCurrentPopup lo cierra en ese mismo frame. Dos campos del binding
-- relajan los guards (ignore_item_active, ignore_popup).

local M = {}

local function modBit(name)
  local f = reaper[name]
  return f and f() or 0
end

local MODS = {
  ctrl  = modBit('ImGui_Mod_Ctrl'),
  shift = modBit('ImGui_Mod_Shift'),
  alt   = modBit('ImGui_Mod_Alt'),
  super = modBit('ImGui_Mod_Super'),
}
local MODS_ALL = MODS.ctrl | MODS.shift | MODS.alt | MODS.super

local S = {
  bindings = {},
  by_id = {},
  sigs = {},      -- sigs[scope][tecla|mods] = binding; scope '' = capa global
  defaults = { delay = 0.5, rate = 0.15 },
  focused = false,
  popup_start = false,
  popup_prev = false,  -- popup abierto al FINAL del frame anterior
  modal = { cancel = {}, confirm = {} },  -- codigos de tecla, ver resolveModalKeys
  actions = {},
  item_active_start = false,
  tab_cur = nil,
  tab_prev = nil,
  consumed = {},
}

local function err(msg)
  reaper.ShowConsoleMsg('[MusicStateKeys] ' .. msg .. '\n')
end

local function buildBinding(def, defaults, actions, tab)
  local id = def.id
  if type(id) ~= 'string' or id == '' then
    err('binding sin id (entrada ignorada)'); return nil
  end
  local key_fn = reaper['ImGui_Key_' .. tostring(def.key)]
  if not key_fn then
    err(id .. ': tecla desconocida "' .. tostring(def.key) .. '"'); return nil
  end
  local kind = def.kind or 'press'
  if kind ~= 'press' and kind ~= 'hold' then
    err(id .. ': kind desconocido "' .. tostring(kind) .. '" (press o hold)'); return nil
  end
  local n_run = (def.cmd ~= nil and 1 or 0) + (def.action ~= nil and 1 or 0) + (def.fn ~= nil and 1 or 0)
  if kind == 'press' and n_run ~= 1 then
    err(id .. ': un press lleva cmd, action o fn (uno solo)'); return nil
  elseif kind == 'hold' and (n_run ~= 0 or def.autorepeat) then
    err(id .. ': un hold no lleva cmd, action, fn ni autorepeat (se consulta con Keys.held)'); return nil
  end
  if def.fn and not tab then
    err(id .. ': fn solo en bindings de tab (en la capa global usar action)'); return nil
  end
  if def.action and not actions[def.action] then
    err(id .. ': la accion "' .. tostring(def.action) .. '" no esta registrada'); return nil
  end

  -- cmd puede ser el numero de una accion nativa o el nombre de una accion
  -- con ID estable ('_SWS_...', '_S&M_...'), que se resuelve en esta PC.
  local cmd = def.cmd
  if type(cmd) == 'string' then
    local named = reaper.NamedCommandLookup(cmd)
    if named == 0 then
      err(id .. ': el comando "' .. cmd .. '" no existe en esta PC (se ignora)'); return nil
    end
    if cmd:sub(1, 3) == '_RS' then
      err(id .. ': "' .. cmd .. '" es el ID de un script y cambia entre PCs; en un config que se despliega conviene una accion nativa o de SWS')
    end
    cmd = named
  elseif cmd ~= nil and type(cmd) ~= 'number' then
    err(id .. ': cmd tiene que ser un numero o un nombre de comando'); return nil
  end

  local mods = 0
  for _, m in ipairs(def.mods or {}) do
    if not MODS[m] then err(id .. ': modificador desconocido "' .. tostring(m) .. '"'); return nil end
    mods = mods | MODS[m]
  end

  local rep = nil
  if def.autorepeat then
    local own = type(def.autorepeat) == 'table' and def.autorepeat or {}
    rep = { delay = own.delay or defaults.delay, rate = own.rate or defaults.rate }
  end

  return {
    id = id, key_name = def.key, key = key_fn(), mods = mods,
    kind = kind, tab = tab, override = def.override or false,
    cmd = cmd, action = def.action, fn = def.fn, rep_cfg = rep,
    ignore_item_active = def.ignore_item_active or false,
    ignore_popup = def.ignore_popup or false,
    rep = nil,  -- estado de repeticion: nil o { next = tiempo }
  }
end

-- Alta de un binding ya validado: unicidad de id y colisiones por capa.
-- Capa global o misma tab: tecla repetida = error. Una tecla de tab que pisa
-- una global tambien es error, salvo override = true (la global queda
-- suprimida mientras esa tab este activa).
local function register(b)
  if S.by_id[b.id] then
    err('id repetido "' .. b.id .. '" (se ignora la segunda entrada)'); return false
  end
  local sig = b.key_name .. '|' .. b.mods
  local scope = b.tab or ''
  S.sigs[scope] = S.sigs[scope] or {}
  local same = S.sigs[scope][sig]
  if same then
    err(string.format('colision: "%s" y "%s" usan la misma tecla en %s (se ignora la segunda)',
      same.id, b.id, b.tab and ('la tab ' .. b.tab) or 'la capa global'))
    return false
  end
  if b.tab then
    local g = S.sigs[''] and S.sigs[''][sig]
    if g then
      if not b.override then
        err(string.format('colision: "%s" (tab %s) pisa a la global "%s"; usar override = true si es a proposito (se ignora la de tab)',
          b.id, b.tab, g.id))
        return false
      end
      g.overridden_by = g.overridden_by or {}
      g.overridden_by[b.tab] = true
      b.overrides = g
    end
  end
  S.sigs[scope][sig] = b
  S.by_id[b.id] = b
  S.bindings[#S.bindings + 1] = b
  return true
end

local MODAL_DEFAULTS = { cancel = { 'Escape' }, confirm = { 'Enter', 'KeypadEnter' } }

-- Teclas de los modales: nombres de la config -> codigos de ReaImGui.
local function resolveModalKeys(cfg_modal)
  local out = { cancel = {}, confirm = {} }
  for role, defaults in pairs(MODAL_DEFAULTS) do
    local names = (cfg_modal and cfg_modal[role]) or defaults
    for _, name in ipairs(names) do
      local fn = reaper['ImGui_Key_' .. tostring(name)]
      if fn then
        out[role][#out[role] + 1] = fn()
      else
        err('modal.' .. role .. ': tecla desconocida "' .. tostring(name) .. '"')
      end
    end
  end
  return out
end

-- cfg: la tabla de MusicStateKeys_config.lua. actions: { nombre = funcion }
-- para los bindings con `action`. Devuelve la cantidad de bindings cargados.
function M.init(cfg, actions)
  S.actions = actions or {}
  S.bindings, S.by_id, S.sigs = {}, {}, {}
  S.defaults = cfg.autorepeat or S.defaults
  S.modal = resolveModalKeys(cfg.modal)
  for _, def in ipairs(cfg.global or {}) do
    local b = buildBinding(def, S.defaults, S.actions, nil)
    if b then register(b) end
  end
  for tab, defs in pairs(cfg.tab or {}) do
    M.add_tab(tab, defs)
  end
  return #S.bindings
end

-- Bindings propios de una tab (llamar despues de init). defs: los mismos
-- campos que la config, mas fn (funcion) en los press, kind = 'hold' para los
-- que se consultan con Keys.held y override = true para pisar una global.
-- Con override, si fn devuelve false (no la use) corre la global pisada.
-- Devuelve la cantidad dada de alta.
function M.add_tab(tab, defs)
  local n = 0
  for _, def in ipairs(defs) do
    local b = buildBinding(def, S.defaults, S.actions, tab)
    if b and register(b) then n = n + 1 end
  end
  return n
end

function M.begin_frame(ctx)
  S.focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
  S.item_active_start = reaper.ImGui_IsAnyItemActive(ctx)
  -- Un combo nativo se cierra con Esc/Enter dentro de NewFrame, antes de este
  -- punto: IsPopupOpen ya da false. El estado del final del frame anterior
  -- (S.popup_prev, lo guarda dispatch) cubre ese caso.
  S.popup_start = S.popup_prev
    or reaper.ImGui_IsPopupOpen(ctx, '', reaper.ImGui_PopupFlags_AnyPopupId())
  S.tab_prev = S.tab_cur
  S.tab_cur = nil
  S.consumed = {}
end

function M.set_tab(name)
  S.tab_cur = name
end

-- Tab dibujada en este frame (o la del anterior si todavia no se dibujo).
function M.current_tab()
  return S.tab_cur or S.tab_prev
end

-- Marca una tecla como usada por un widget este frame: ningun binding de esa
-- tecla actua en el despacho de este frame. name: nombre de la config.
function M.consume(name)
  S.consumed[name] = true
end

-- Teclas de un modal (lector para ImGuiConfirmModal.begin): devuelve
-- cancelar, confirmar. Press nuevo, sin repeticion. Los modales no pasan por
-- dispatch: con un popup abierto los bindings globales estan cerrados.
function M.modal(ctx)
  local function any(list)
    for _, k in ipairs(list) do
      if reaper.ImGui_IsKeyPressed(ctx, k, false) then return true end
    end
    return false
  end
  return any(S.modal.cancel), any(S.modal.confirm)
end

-- Devuelve lo que devuelve fn. Un binding de tab con override cuya fn da
-- false dice "no la use": el despacho cae a la global que suprimia.
local function fire(b)
  if b.fn then
    return b.fn(b)
  elseif b.cmd then
    reaper.Main_OnCommand(b.cmd, 0)
  else
    S.actions[b.action](b)
  end
end

local function fireWithFallback(b)
  if fire(b) == false and b.overrides then
    fire(b.overrides)
  end
end

-- Estado actual de un binding kind = 'hold': true mientras la tecla esta
-- abajo y todos los guards estan abiertos. Se evalua en el momento de la
-- llamada (durante el draw de la tab), sin esperar al dispatch del final del
-- frame: el tap de Lyrics no puede perder un frame de latencia. El que lo
-- consulta detecta los flancos (press/release) con su propio estado previo.
function M.held(ctx, id)
  local b = S.by_id[id]
  if not b or b.kind ~= 'hold' then return false end
  if b.tab and b.tab ~= S.tab_cur then return false end
  if not S.focused or S.consumed[b.key_name] then return false end
  if not b.ignore_popup
    and (S.popup_start
      or reaper.ImGui_IsPopupOpen(ctx, '', reaper.ImGui_PopupFlags_AnyPopupId())) then
    return false
  end
  if not b.ignore_item_active
    and (S.item_active_start or reaper.ImGui_IsAnyItemActive(ctx)) then
    return false
  end
  if (reaper.ImGui_GetKeyMods(ctx) & MODS_ALL) ~= b.mods then return false end
  return reaper.ImGui_IsKeyDown(ctx, b.key)
end

function M.dispatch(ctx)
  -- Estado VIVO (no `popup`, que incluye la foto del inicio y se
  -- retroalimentaria): es lo que el proximo begin_frame necesita.
  local popup_live = reaper.ImGui_IsPopupOpen(ctx, '', reaper.ImGui_PopupFlags_AnyPopupId())
  S.popup_prev = popup_live
  local popup = S.popup_start or popup_live
  local item_active = S.item_active_start or reaper.ImGui_IsAnyItemActive(ctx)
  local mods = reaper.ImGui_GetKeyMods(ctx) & MODS_ALL
  local now = reaper.time_precise()
  local tab_changed = S.tab_cur ~= S.tab_prev

  for _, b in ipairs(S.bindings) do
    -- Los hold no se despachan (se consultan con Keys.held). Los de tab
    -- solo actuan con su tab dibujada; una global suprimida por override,
    -- nunca en esa tab.
    local open = b.kind ~= 'hold'
      and S.focused and not tab_changed
      and (not b.tab or b.tab == S.tab_cur)
      and not (b.overridden_by and b.overridden_by[S.tab_cur])
      and not S.consumed[b.key_name]
      and (b.ignore_popup or not popup)
      and (b.ignore_item_active or not item_active)

    if b.kind == 'hold' then
      -- nada que despachar
    elseif not open or mods ~= b.mods or not reaper.ImGui_IsKeyDown(ctx, b.key) then
      -- Guard cerrado, otra combinacion de modificadores o tecla suelta: la
      -- repeticion se apaga y solo un press nuevo con todo abierto la prende.
      b.rep = nil
    elseif reaper.ImGui_IsKeyPressed(ctx, b.key, false) then
      fireWithFallback(b)
      b.rep = b.rep_cfg and { next = now + b.rep_cfg.delay } or nil
    elseif b.rep and now >= b.rep.next then
      fireWithFallback(b)
      local nxt = b.rep.next + b.rep_cfg.rate
      b.rep.next = (nxt > now) and nxt or (now + b.rep_cfg.rate)
    end
  end
end

return M
