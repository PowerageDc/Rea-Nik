-- MusicStateKeys_common_logic.lua
-- Despacho central de atajos de teclado del Helper (Paso 3: capa global con
-- press y autorepeat). Los bindings vienen de MusicStateKeys_config.lua.
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
-- habia un item activo al inicio ni lo hay ahora, no hay popup abierto y la
-- tecla no fue consumida este frame (Keys.consume). Dos campos del binding
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
  actions = {},
  item_active_start = false,
  tab_cur = nil,
  tab_prev = nil,
  consumed = {},
}

local function err(msg)
  reaper.ShowConsoleMsg('[MusicStateKeys] ' .. msg .. '\n')
end

local function buildBinding(def, defaults, actions)
  local id = def.id
  if type(id) ~= 'string' or id == '' then
    err('binding sin id (entrada ignorada)'); return nil
  end
  local key_fn = reaper['ImGui_Key_' .. tostring(def.key)]
  if not key_fn then
    err(id .. ': tecla desconocida "' .. tostring(def.key) .. '"'); return nil
  end
  if (def.cmd == nil) == (def.action == nil) then
    err(id .. ': tiene que llevar cmd o action (uno solo)'); return nil
  end
  if def.action and not actions[def.action] then
    err(id .. ': la accion "' .. tostring(def.action) .. '" no esta registrada'); return nil
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
    cmd = def.cmd, action = def.action, rep_cfg = rep,
    ignore_item_active = def.ignore_item_active or false,
    ignore_popup = def.ignore_popup or false,
    rep = nil,  -- estado de repeticion: nil o { next = tiempo }
  }
end

-- cfg: la tabla de MusicStateKeys_config.lua. actions: { nombre = funcion }
-- para los bindings con `action`. Devuelve la cantidad de bindings cargados.
function M.init(cfg, actions)
  S.actions = actions or {}
  S.bindings = {}
  local defaults = cfg.autorepeat or { delay = 0.5, rate = 0.15 }
  local ids, sigs = {}, {}
  for _, def in ipairs(cfg.global or {}) do
    local b = buildBinding(def, defaults, S.actions)
    if b then
      local sig = b.key_name .. '|' .. b.mods
      if ids[b.id] then
        err('id repetido "' .. b.id .. '" (se ignora la segunda entrada)')
      elseif sigs[sig] then
        err(string.format('colision: "%s" y "%s" usan la misma tecla en la capa global (se ignora la segunda)',
          sigs[sig], b.id))
      else
        ids[b.id], sigs[sig] = true, b.id
        S.bindings[#S.bindings + 1] = b
      end
    end
  end
  return #S.bindings
end

function M.begin_frame(ctx)
  S.item_active_start = reaper.ImGui_IsAnyItemActive(ctx)
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

local function fire(b)
  if b.cmd then
    reaper.Main_OnCommand(b.cmd, 0)
  else
    S.actions[b.action](b)
  end
end

function M.dispatch(ctx)
  local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_ChildWindows())
  local popup = reaper.ImGui_IsPopupOpen(ctx, '', reaper.ImGui_PopupFlags_AnyPopupId())
  local item_active = S.item_active_start or reaper.ImGui_IsAnyItemActive(ctx)
  local mods = reaper.ImGui_GetKeyMods(ctx) & MODS_ALL
  local now = reaper.time_precise()
  local tab_changed = S.tab_cur ~= S.tab_prev

  for _, b in ipairs(S.bindings) do
    local open = focused and not tab_changed
      and not S.consumed[b.key_name]
      and (b.ignore_popup or not popup)
      and (b.ignore_item_active or not item_active)

    if not open or mods ~= b.mods or not reaper.ImGui_IsKeyDown(ctx, b.key) then
      -- Guard cerrado, otra combinacion de modificadores o tecla suelta: la
      -- repeticion se apaga y solo un press nuevo con todo abierto la prende.
      b.rep = nil
    elseif reaper.ImGui_IsKeyPressed(ctx, b.key, false) then
      fire(b)
      b.rep = b.rep_cfg and { next = now + b.rep_cfg.delay } or nil
    elseif b.rep and now >= b.rep.next then
      fire(b)
      local nxt = b.rep.next + b.rep_cfg.rate
      b.rep.next = (nxt > now) and nxt or (now + b.rep_cfg.rate)
    end
  end
end

return M
