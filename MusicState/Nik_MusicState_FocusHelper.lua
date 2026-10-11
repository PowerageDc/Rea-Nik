-- @description Nik MusicState - Enfocar el Helper desde REAPER
-- @version 1.0
-- @author Nik
-- @about
--   One-shot para asignar a una tecla (seccion Main). Lleva el foco del
--   teclado a la ventana del Helper. La vuelta a REAPER la resuelve el
--   propio Helper con la misma tecla (ver Nik_MusicState_Helper.lua).

local script_dir = debug.getinfo(1, "S").source:match("@(.*[/\\])")
local HostFocus = dofile(script_dir .. "../_Shared/ImGuiHostFocus_common_logic.lua")

-- Tiene que coincidir con el titulo que el Helper le pasa a ImGui_Begin.
local WINDOW_TITLE = 'MusicState Helper'
local EXT_SECTION = 'NikMusicStateHelper'
local EXT_KEY_BLOCK_REAPER = 'host_focus_block_reaper'
local EXT_KEY_BLOCK_HELPER = 'host_focus_block_helper'
local BLOCK_S = 0.8
local SLIDE_S = 0.15

-- Si el Helper acaba de devolver el foco a REAPER con esta misma tecla, el
-- auto-repeat de la tecla apretada llega aca y lo devolveria de golpe.
if HostFocus.blocked(EXT_SECTION, EXT_KEY_BLOCK_REAPER, SLIDE_S) then return end

-- La ventana contraria se arma solo si el foco realmente se movio (con el
-- Helper cerrado no hay nada que enfocar ni que proteger).
if HostFocus.toWindow(WINDOW_TITLE) then
  HostFocus.arm(EXT_SECTION, EXT_KEY_BLOCK_HELPER, BLOCK_S)
end
