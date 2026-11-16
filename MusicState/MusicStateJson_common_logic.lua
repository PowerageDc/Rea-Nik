-- MusicStateJson_common_logic.lua
-- JSON minimo para los datos de MusicState: escape de strings, formato
-- numerico y un decodificador que respeta los strings (llaves, corchetes y
-- comillas escapadas dentro de un texto no lo rompen). Consumido por el
-- Helper y por la publicacion de letras.

local M = {}

-- Valor que devuelve decode para un null, para que quepa en arrays y tablas.
M.NULL = setmetatable({}, { __tostring = function() return 'null' end })

-- Numero con 3 decimales y punto decimal siempre, sin importar el locale.
function M.fmtNumber(x)
  return (string.format('%.3f', x):gsub(',', '.'))
end

function M.jsonString(s)
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    return string.format('\\u%04x', c:byte())
  end)
  return '"' .. s .. '"'
end

local ESC = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
  b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function skipWs(s, i)
  return s:find('[^ \t\r\n]', i) or (#s + 1)
end

-- s:sub(i, i) es la comilla de apertura. Devuelve el texto decodificado y
-- la posicion siguiente a la comilla de cierre.
local function decodeString(s, i)
  local out = {}
  i = i + 1
  while true do
    local c = s:sub(i, i)
    if c == '' then error('string sin cerrar') end
    if c == '"' then return table.concat(out), i + 1 end
    if c == '\\' then
      local e = s:sub(i + 1, i + 1)
      if e == 'u' then
        local hex = s:match('^%x%x%x%x', i + 2)
        if not hex then error('escape \\u invalido') end
        local cp = tonumber(hex, 16)
        local used = 6
        if cp >= 0xD800 and cp <= 0xDBFF then
          local lo = s:match('^\\u(%x%x%x%x)', i + 6)
          local lo_cp = lo and tonumber(lo, 16)
          if lo_cp and lo_cp >= 0xDC00 and lo_cp <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo_cp - 0xDC00)
            used = 12
          end
        end
        out[#out + 1] = utf8.char(cp)
        i = i + used
      else
        local ch = ESC[e]
        if not ch then error('escape invalido') end
        out[#out + 1] = ch
        i = i + 2
      end
    else
      local j = s:find('["\\]', i) or (#s + 1)
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
end

local decodeValue

local function decodeObject(s, i)
  local obj = {}
  i = skipWs(s, i + 1)
  if s:sub(i, i) == '}' then return obj, i + 1 end
  while true do
    i = skipWs(s, i)
    if s:sub(i, i) ~= '"' then error('clave esperada') end
    local key
    key, i = decodeString(s, i)
    i = skipWs(s, i)
    if s:sub(i, i) ~= ':' then error("se esperaba ':'") end
    local v
    v, i = decodeValue(s, i + 1)
    obj[key] = v
    i = skipWs(s, i)
    local d = s:sub(i, i)
    if d == ',' then
      i = i + 1
    elseif d == '}' then
      return obj, i + 1
    else
      error("se esperaba ',' o '}'")
    end
  end
end

local function decodeArray(s, i)
  local arr = {}
  i = skipWs(s, i + 1)
  if s:sub(i, i) == ']' then return arr, i + 1 end
  while true do
    local v
    v, i = decodeValue(s, i)
    arr[#arr + 1] = v
    i = skipWs(s, i)
    local d = s:sub(i, i)
    if d == ',' then
      i = i + 1
    elseif d == ']' then
      return arr, i + 1
    else
      error("se esperaba ',' o ']'")
    end
  end
end

function decodeValue(s, i)
  i = skipWs(s, i)
  local c = s:sub(i, i)
  if c == '{' then return decodeObject(s, i) end
  if c == '[' then return decodeArray(s, i) end
  if c == '"' then return decodeString(s, i) end
  if s:sub(i, i + 3) == 'true' then return true, i + 4 end
  if s:sub(i, i + 4) == 'false' then return false, i + 5 end
  if s:sub(i, i + 3) == 'null' then return M.NULL, i + 4 end
  local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', i)
  local n = num and tonumber(num)
  if not n then error('valor invalido') end
  return n, i + #num
end

-- Devuelve el valor decodificado, o nil + mensaje si el texto no es JSON
-- valido o tiene algo despues del valor.
function M.decode(s)
  local ok, v, i = pcall(decodeValue, s, 1)
  if not ok then return nil, v end
  if skipWs(s, i) <= #s then return nil, 'texto sobrante' end
  return v
end

return M