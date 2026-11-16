-- Nik_Test_CuesData.lua
-- Test de consola de MusicStateJson_common_logic.lua y
-- MusicStateCuesData_common_logic.lua. No modifica el proyecto.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Json = dofile(script_dir .. "../MusicState/MusicStateJson_common_logic.lua")
local Model = dofile(script_dir .. "../MusicState/MusicStateCuesModel_common_logic.lua")
local Data = dofile(script_dir .. "../MusicState/MusicStateCuesData_common_logic.lua")

local pass, fail = 0, 0

local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    reaper.ShowConsoleMsg('FAIL: ' .. name .. '\n')
  end
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

reaper.ClearConsole()
local proj = 0

-- Decodificador ---------------------------------------------------------
local v = Json.decode([[{"a":[1,2.5,"x"],"b":null,"c":true,"d":false}]])
check('decode basico', v and v.a[1] == 1 and v.a[2] == 2.5 and v.a[3] == 'x')
check('decode null', v and v.b == Json.NULL)
check('decode bool', v and v.c == true and v.d == false)

v = Json.decode([[{"t":"a\"b"}]])
check('comilla escapada', v and v.t == 'a"b')
v = Json.decode([[{"t":"{[}]"}]])
check('llaves y corchetes en texto', v and v.t == '{[}]')
v = Json.decode([[{"t":"a\\b"}]])
check('barra invertida', v and v.t == 'a\\b')
v = Json.decode([[{"t":"\u00e9\u0001\n"}]])
check('unicode y control', v and v.t == utf8.char(0xE9) .. '\1\n')
v = Json.decode([[{"t":"\ud83c\udfb5"}]])
check('par sustituto', v and v.t == utf8.char(0x1F3B5))
v = Json.decode('  { "k" : [ ] , "o" : { } }  ')
check('espacios y vacios', v and #v.k == 0 and next(v.o) == nil)

check('error sin cerrar', Json.decode('{"a":') == nil)
check('error sobrante', Json.decode('{} x') == nil)
check('error string sin cerrar', Json.decode('{"a":"x') == nil)

-- Escape: lo que escribe jsonString lo lee decode ------------------------
local nasty = 'He said "hola" {x} [y] \\ back\ttab\1'
v = Json.decode('{"t":' .. Json.jsonString(nasty) .. '}')
check('round-trip jsonString', v and v.t == nasty)
check('fmtNumber', Json.fmtNumber(1.5) == '1.500' and Json.fmtNumber(0) == '0.000')

-- Codec de cues ----------------------------------------------------------
check('encode vacio', Data.encode({}, proj) == '{}')
local empty, err = Data.decode('', proj)
check('decode vacio', #empty == 0 and err == nil)
local bad, bad_err = Data.decode('{"1":[{"text":"x"', proj)
check('decode roto', #bad == 0 and bad_err ~= nil)

local list = {}
Model.insert(list, Model.newCue(1.25, 2, { 'bateria', 'bajo' }, nasty))
Model.insert(list, Model.newCue(1.25, 0.5, { 'todos' }, ''))
Model.insert(list, Model.newCue(16.376, 3, { 'a"b' }, 'Coro {1}'))
Model.insert(list, Model.newCue(4, 1, { 'voz' }, 'Verso'))

local json = Data.encode(list, proj)
local back, back_err = Data.decode(json, proj)
check('round-trip sin error', back_err == nil)
check('round-trip cantidad', #back == #list)
for i = 1, math.min(#list, #back) do
  local a, b = list[i], back[i]
  check('rt qn ' .. i, math.abs(a.qn - b.qn) < 1e-9)
  check('rt dur ' .. i, math.abs(a.dur_qn - b.dur_qn) < 1e-9)
  check('rt text ' .. i, a.text == b.text)
  check('rt roles ' .. i, same(a.roles, b.roles))
end
check('segundo encode igual', Data.encode(back, proj) == json)

-- Formato anterior (posiciones en grilla, numeros sin decimales fijos) ----
local legacy = '{"1":[{"qn_offset":0,"roles":["todos"],"text":"Entra","duration_qn":2}],'
  .. '"3":[{"qn_offset":1.5,"roles":["bateria","bajo"],"text":"","duration_qn":0.5}]}'
local old, old_err = Data.decode(legacy, proj)
check('legacy sin error', old_err == nil)
check('legacy cantidad', #old == 2)
if #old == 2 then
  check('legacy qn 1', math.abs(old[1].qn - Model.measureToQn(proj, 1, 0)) < 1e-9)
  check('legacy qn 2', math.abs(old[2].qn - Model.measureToQn(proj, 3, 1.5)) < 1e-9)
  check('legacy roles', same(old[2].roles, { 'bateria', 'bajo' }))
  check('legacy dur', old[2].dur_qn == 0.5)
  check('legacy texto', old[1].text == 'Entra')
end

reaper.ShowConsoleMsg(string.format('CuesData: %d ok, %d fallas\n', pass, fail))