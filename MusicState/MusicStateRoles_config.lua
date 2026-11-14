-- MusicStateRoles_config.lua
-- Catalogo de roles de MusicState: los valores que se pueden tildar en la tab
-- Roles del Helper y que usan los cues y los selectores de las UIs. Se edita a
-- mano; el id es el texto que se guarda y se publica, asi que cambiarlo
-- desvincula los cues que ya lo usan.
--
-- id: texto del rol (sin acentos, igual en todos los proyectos).
-- default: si un proyecto sin roles guardados arranca con este rol tildado.
-- El orden de la lista es el orden en que se muestran y se publican.

return {
  catalog = {
    { id = 'bajo',       default = true },
    { id = 'bateria',    default = true },
    { id = 'guitarra',   default = true },
    { id = 'guitarra 2', default = false },
    { id = 'teclado',    default = true },
    { id = 'teclado 2',  default = false },
    { id = 'voz',        default = true },
  },
}