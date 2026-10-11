-- Nik_Test_KeysFocusRequest.lua
-- One-shot del probe de foco: levanta la bandera que lee
-- Nik_Test_KeysFocusProbe.lua. Registrar en el Action List y asignarle una
-- tecla (seccion Main) para probar el paso REAPER -> ImGui sin mouse.
reaper.SetExtState('NikKeysProbe', 'focus_request', '1', false)
