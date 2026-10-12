local ctx = reaper.ImGui_CreateContext('KeyProbe')
local keys = {}
for name, fn in pairs(reaper) do
  local k = name:match('^ImGui_Key_(.+)$')
  if k and type(fn) == 'function' then keys[#keys + 1] = { k, fn() } end
end
local function loop()
  local visible, open = reaper.ImGui_Begin(ctx, 'KeyProbe', true)
  if visible then
    local down = {}
    for _, e in ipairs(keys) do
      if reaper.ImGui_IsKeyDown(ctx, e[2]) then down[#down + 1] = e[1] end
    end
    reaper.ImGui_Text(ctx, 'Abajo: ' .. table.concat(down, ', '))
    reaper.ImGui_End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)