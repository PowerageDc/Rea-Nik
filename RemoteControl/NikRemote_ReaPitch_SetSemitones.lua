-- NikRemote_ReaPitch_SetSemitones.lua
-- Lee el semitono objetivo desde ExtState (seteado por la web antes de
-- invocar este script) y lo aplica a todas las instancias de ReaPitch
-- encontradas en los hijos del Stem Bus.

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local ReaPitchBus = dofile(script_dir .. "../_Shared/ReaPitchBus_common_logic.lua")

local target_str = reaper.GetExtState("NikRemote", "reapitch_semitone_target")
if target_str == "" then return end

local target = tonumber(target_str)
if not target then return end

local instances = ReaPitchBus.find_all_instances()
if #instances == 0 then return end

local normalized = ReaPitchBus.semitones_to_normalized(target)

reaper.Undo_BeginBlock()

for _, inst in ipairs(instances) do
  reaper.TrackFX_SetParamNormalized(inst.track, inst.fx, ReaPitchBus.SEMITONE_PARAM, normalized)
end

reaper.Undo_EndBlock("NikRemote: aplicar " .. target .. " semitonos a ReaPitch (Stem Bus)", -1)

-- Refrescar el agregado inmediatamente para que la web lea el valor nuevo
reaper.SetExtState("NikRemote", "reapitch_semitone", target_str, false)
