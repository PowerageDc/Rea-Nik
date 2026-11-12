-- MusicStateCuesModel_common_logic.lua
-- Modelo en memoria de los cues del Helper, sin ImGui: lista ordenada de
-- {uid, qn, dur_qn, roles, text}. La posicion es QN absoluto, libre (sin
-- grilla), redondeado a 3 decimales. Consumido solo por el Helper.
--
-- Toda mutacion pasa por las funciones de este modulo y devuelve su
-- inversa: una funcion que, al llamarla, deshace el cambio y devuelve a su
-- vez la inversa de la inversa (rehacer). Devuelven nil si el uid no existe.

local M = {}

M.ALL_ROLE = 'todos'
M.DEFAULT_DUR_QN = 1.0
M.MIN_DUR_QN = 0.01

-- Tolerancia al decidir si un cue esta activo en un QN dado.
local EPS_QN = 1e-4

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end
M.round3 = round3

-- Roles --------------------------------------------------------------

-- Sin duplicados ni vacios; 'todos' es excluyente y una lista vacia cae en
-- 'todos'.
function M.normalizeRoles(roles)
  local out, seen = {}, {}
  for _, r in ipairs(roles or {}) do
    if r == M.ALL_ROLE then return { M.ALL_ROLE } end
    if r ~= '' and not seen[r] then
      seen[r] = true
      out[#out + 1] = r
    end
  end
  if #out == 0 then out[1] = M.ALL_ROLE end
  return out
end

-- Lista de roles resultante de marcar o desmarcar `role`. No modifica la
-- recibida.
function M.toggledRoles(roles, role)
  if role == M.ALL_ROLE then return { M.ALL_ROLE } end
  local out, found = {}, false
  for _, r in ipairs(roles or {}) do
    if r == role then
      found = true
    elseif r ~= M.ALL_ROLE then
      out[#out + 1] = r
    end
  end
  if not found then out[#out + 1] = role end
  return M.normalizeRoles(out)
end

function M.hasRole(cue, role)
  for _, r in ipairs(cue.roles) do
    if r == role then return true end
  end
  return false
end

-- Lo que veria el musico de ese rol: sus cues mas los dirigidos a todos.
-- role == nil: sin filtro.
function M.visibleFor(cue, role)
  return role == nil or M.hasRole(cue, role) or M.hasRole(cue, M.ALL_ROLE)
end

-- Roles del cue que no estan en la lista de roles del proyecto ('todos'
-- nunca cuenta como desconocido).
function M.unknownRoles(cue, known_roles)
  local known = {}
  for _, r in ipairs(known_roles or {}) do known[r] = true end
  local out = {}
  for _, r in ipairs(cue.roles) do
    if r ~= M.ALL_ROLE and not known[r] then out[#out + 1] = r end
  end
  return out
end

-- Lista ---------------------------------------------------------------

-- Orden total: por QN y, a igual QN, por uid (estable).
local function before(a, b)
  if a.qn ~= b.qn then return a.qn < b.qn end
  return a.uid < b.uid
end

local function insertSorted(list, cue)
  local i = #list + 1
  while i > 1 and before(cue, list[i - 1]) do i = i - 1 end
  table.insert(list, i, cue)
end

function M.find(list, uid)
  for i, c in ipairs(list) do
    if c.uid == uid then return c, i end
  end
  return nil, nil
end

local function removeByUid(list, uid)
  local cue, i = M.find(list, uid)
  if i then table.remove(list, i) end
  return cue
end

-- El uid lo asigna insert: el contador vive en la lista, asi no depende de
-- cuantas veces se cargo este modulo.
function M.newCue(qn, dur_qn, roles, text)
  return {
    qn = math.max(0, round3(qn)),
    dur_qn = math.max(M.MIN_DUR_QN, round3(dur_qn or M.DEFAULT_DUR_QN)),
    roles = M.normalizeRoles(roles),
    text = text or '',
  }
end

local function nextUid(list)
  if not list.next_uid then
    local max = 0
    for _, c in ipairs(list) do
      if c.uid and c.uid > max then max = c.uid end
    end
    list.next_uid = max
  end
  list.next_uid = list.next_uid + 1
  return list.next_uid
end

function M.insert(list, cue)
  cue.uid = cue.uid or nextUid(list)
  insertSorted(list, cue)
  return function() return M.delete(list, cue.uid) end
end

function M.delete(list, uid)
  local cue = removeByUid(list, uid)
  if not cue then return nil end
  return function() return M.insert(list, cue) end
end

local function setField(list, uid, field, value)
  local cue = M.find(list, uid)
  if not cue then return nil end
  local old = cue[field]
  cue[field] = value
  return function() return setField(list, uid, field, old) end
end

function M.setText(list, uid, text)
  return setField(list, uid, 'text', text or '')
end

function M.setRoles(list, uid, roles)
  return setField(list, uid, 'roles', M.normalizeRoles(roles))
end

function M.setDuration(list, uid, dur_qn)
  return setField(list, uid, 'dur_qn', math.max(M.MIN_DUR_QN, round3(dur_qn)))
end

function M.move(list, uid, qn)
  local cue = removeByUid(list, uid)
  if not cue then return nil end
  local old = cue.qn
  cue.qn = math.max(0, round3(qn))
  insertSorted(list, cue)
  return function() return M.move(list, uid, old) end
end

-- Consultas -----------------------------------------------------------

-- Mismos cue (no copias), en el orden de la lista. role == nil: todos.
function M.filtered(list, role)
  local out = {}
  for _, c in ipairs(list) do
    if M.visibleFor(c, role) then out[#out + 1] = c end
  end
  return out
end

-- Cues cuyo intervalo [qn, qn + dur_qn) contiene el QN dado. Puede haber
-- varios: los cues de roles distintos se solapan.
function M.activeAt(list, qn)
  local out = {}
  for _, c in ipairs(list) do
    if c.qn > qn + EPS_QN then break end
    if qn < c.qn + c.dur_qn - EPS_QN then out[#out + 1] = c end
  end
  return out
end

-- Conversion con el formato publicado ----------------------------------

-- QN absoluto -> compas (1-indexed) y qn_offset desde su downbeat. El QN se
-- redondea ANTES de partirlo: sin eso un evento justo en un downbeat puede
-- caer como 3.9999 del compas anterior.
function M.qnToMeasure(proj, qn)
  qn = math.max(0, round3(qn))
  local measure, qn_start = reaper.TimeMap_QNToMeasures(proj, qn)
  return measure, round3(qn - qn_start)
end

-- Inversa de qnToMeasure. measure es 1-indexed; TimeMap_GetMeasureInfo
-- espera 0-indexed.
function M.measureToQn(proj, measure, qn_offset)
  local _, qn_start = reaper.TimeMap_GetMeasureInfo(proj, measure - 1)
  return round3(qn_start + qn_offset)
end

return M