-- MusicStateCuesData_common_logic.lua
-- Lista de cues del Helper <-> texto de cues_data (ProjExtState y puente).
-- Formato: {"<compas>":[{"qn_offset":N,"roles":[...],"text":"...",
-- "duration_qn":N}, ...], ...}. Consumido solo por el Helper.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local Json = dofile(script_dir .. "MusicStateJson_common_logic.lua")
local Model = dofile(script_dir .. "MusicStateCuesModel_common_logic.lua")

local M = {}

-- La lista llega ordenada por QN, asi que los compases salen en orden
-- creciente y los eventos de cada compas por posicion.
function M.encode(list, proj)
  local order, by_measure = {}, {}
  for _, c in ipairs(list) do
    local measure, offset = Model.qnToMeasure(proj, c.qn)
    local roles = {}
    for _, r in ipairs(c.roles) do roles[#roles + 1] = Json.jsonString(r) end
    local event = '{"qn_offset":' .. Json.fmtNumber(offset)
      .. ',"roles":[' .. table.concat(roles, ',') .. ']'
      .. ',"text":' .. Json.jsonString(c.text)
      .. ',"duration_qn":' .. Json.fmtNumber(c.dur_qn) .. '}'
    if not by_measure[measure] then
      by_measure[measure] = {}
      order[#order + 1] = measure
    end
    table.insert(by_measure[measure], event)
  end
  local parts = {}
  for _, measure in ipairs(order) do
    parts[#parts + 1] = string.format('"%d":[%s]', measure,
      table.concat(by_measure[measure], ','))
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- Devuelve la lista de cues y, si el texto no se pudo leer, un mensaje de
-- error (con la lista vacia). Texto vacio = sin cues, sin error.
function M.decode(json, proj)
  local list = {}
  if not json or json == '' then return list end
  local data, err = Json.decode(json)
  if type(data) ~= 'table' then return list, err or 'formato invalido' end

  local measures = {}
  for key in pairs(data) do
    local measure = tonumber(key)
    if measure and measure >= 1 and measure == math.floor(measure) then
      measures[#measures + 1] = { n = math.floor(measure), key = key }
    end
  end
  table.sort(measures, function(a, b) return a.n < b.n end)

  for _, m in ipairs(measures) do
    local measure = m.n
    local events = data[m.key]
    if type(events) == 'table' then
      for _, e in ipairs(events) do
        if type(e) == 'table' then
          local roles = {}
          if type(e.roles) == 'table' then
            for _, r in ipairs(e.roles) do
              if type(r) == 'string' then roles[#roles + 1] = r end
            end
          end
          local qn = Model.measureToQn(proj, measure, tonumber(e.qn_offset) or 0)
          local dur = tonumber(e.duration_qn) or Model.DEFAULT_DUR_QN
          local text = type(e.text) == 'string' and e.text or ''
          Model.insert(list, Model.newCue(qn, dur, roles, text))
        end
      end
    end
  end
  return list
end

return M