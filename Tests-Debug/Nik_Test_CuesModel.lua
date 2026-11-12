-- Nik_Test_CuesModel.lua
-- Test de consola de MusicStateCuesModel_common_logic.lua. No modifica el
-- proyecto: las operaciones sobre la lista son en memoria y la conversion
-- solo lee el mapa de tempo del proyecto activo.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Model = dofile(script_dir .. "../MusicState/MusicStateCuesModel_common_logic.lua")

local pass, fail = 0, 0

local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    reaper.ShowConsoleMsg('FAIL: ' .. name .. '\n')
  end
end

local function uids(list)
  local t = {}
  for _, c in ipairs(list) do t[#t + 1] = c.uid end
  return table.concat(t, ',')
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

reaper.ClearConsole()

-- Roles ---------------------------------------------------------------
check('normalize vacio -> todos', same(Model.normalizeRoles({}), { 'todos' }))
check('normalize nil -> todos', same(Model.normalizeRoles(nil), { 'todos' }))
check('normalize todos excluyente', same(Model.normalizeRoles({ 'bajistas', 'todos' }), { 'todos' }))
check('normalize duplicados', same(Model.normalizeRoles({ 'a', 'a', 'b' }), { 'a', 'b' }))
check('toggle agrega', same(Model.toggledRoles({ 'a' }, 'b'), { 'a', 'b' }))
check('toggle quita', same(Model.toggledRoles({ 'a', 'b' }, 'a'), { 'b' }))
check('toggle ultimo cae en todos', same(Model.toggledRoles({ 'a' }, 'a'), { 'todos' }))
check('toggle todos limpia', same(Model.toggledRoles({ 'a', 'b' }, 'todos'), { 'todos' }))
check('toggle rol sobre todos', same(Model.toggledRoles({ 'todos' }, 'a'), { 'a' }))

-- Lista ---------------------------------------------------------------
local list = {}
local c1 = Model.newCue(4, 2, { 'a' }, 'uno')
local c2 = Model.newCue(1, 1, { 'b' }, 'dos')
local c3 = Model.newCue(4, 1, { 'todos' }, 'tres')
Model.insert(list, c1)
Model.insert(list, c2)
local undo_insert = Model.insert(list, c3)
check('orden por qn y uid', uids(list) == c2.uid .. ',' .. c1.uid .. ',' .. c3.uid)

local redo_insert = undo_insert()
check('undo insert', uids(list) == c2.uid .. ',' .. c1.uid)
redo_insert()
check('redo insert', uids(list) == c2.uid .. ',' .. c1.uid .. ',' .. c3.uid)

local undo_move = Model.move(list, c2.uid, 10)
check('move reordena', uids(list) == c1.uid .. ',' .. c3.uid .. ',' .. c2.uid)
undo_move()
check('undo move', uids(list) == c2.uid .. ',' .. c1.uid .. ',' .. c3.uid)
check('move uid inexistente', Model.move(list, 9999, 1) == nil)

local undo_text = Model.setText(list, c1.uid, 'cambio')
check('setText', c1.text == 'cambio')
undo_text()
check('undo setText', c1.text == 'uno')

local undo_roles = Model.setRoles(list, c1.uid, { 'a', 'b' })
check('setRoles', same(c1.roles, { 'a', 'b' }))
undo_roles()
check('undo setRoles', same(c1.roles, { 'a' }))

local undo_dur = Model.setDuration(list, c1.uid, 0)
check('setDuration minimo', c1.dur_qn == Model.MIN_DUR_QN)
undo_dur()
check('undo setDuration', c1.dur_qn == 2)

local undo_del = Model.delete(list, c1.uid)
check('delete', uids(list) == c2.uid .. ',' .. c3.uid)
undo_del()
check('undo delete', uids(list) == c2.uid .. ',' .. c1.uid .. ',' .. c3.uid)
check('delete inexistente', Model.delete(list, 9999) == nil)

-- Consultas -----------------------------------------------------------
-- c2: [1,2) b  | c1: [4,6) a  | c3: [4,5) todos
check('visibleFor sin filtro', Model.visibleFor(c1, nil))
check('visibleFor propio', Model.visibleFor(c1, 'a'))
check('visibleFor ajeno', not Model.visibleFor(c1, 'b'))
check('visibleFor todos', Model.visibleFor(c3, 'b'))
check('filtered rol b', uids(Model.filtered(list, 'b')) == c2.uid .. ',' .. c3.uid)
check('activeAt 0.5', #Model.activeAt(list, 0.5) == 0)
check('activeAt inicio inclusive', #Model.activeAt(list, 1) == 1)
check('activeAt fin exclusivo', #Model.activeAt(list, 2) == 0)
check('activeAt solape', #Model.activeAt(list, 4.5) == 2)
check('activeAt ruido flotante', #Model.activeAt(list, 3.99999) == 2)
check('unknownRoles', same(Model.unknownRoles(c1, { 'b' }), { 'a' }))
check('unknownRoles todos', #Model.unknownRoles(c3, {}) == 0)

-- Cues creados por instancias distintas del modulo en la misma lista ----
local ModelB = dofile(script_dir .. "../MusicState/MusicStateCuesModel_common_logic.lua")
local shared = {}
local x = Model.newCue(1, 1, nil, 'x')
local y = ModelB.newCue(2, 1, nil, 'y')
Model.insert(shared, x)
ModelB.insert(shared, y)
check('uid unico entre instancias', x.uid ~= y.uid)

-- Conversion con el mapa de tempo real --------------------------------
local proj = 0
local probes = { 0, 1.25, 3.9999999, 4, 4.376, 16.0005, 37.5 }
for _, qn in ipairs(probes) do
  local measure, offset = Model.qnToMeasure(proj, qn)
  local back = Model.measureToQn(proj, measure, offset)
  check('round-trip qn ' .. qn, math.abs(back - Model.round3(qn)) < 1e-9)
  check('offset >= 0 en qn ' .. qn, offset >= 0)
  local _, _, _, num, den = reaper.TimeMap_GetMeasureInfo(proj, measure - 1)
  check('offset < largo del compas en qn ' .. qn, offset < num * 4 / den - 1e-9)
end

reaper.ShowConsoleMsg(string.format('CuesModel: %d ok, %d fallas\n', pass, fail))