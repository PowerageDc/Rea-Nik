return {
  -- false = Publish.lua no escribe en la consola de REAPER.
  debug = false,
  buses = {
    { name = "Monitor Bus - Batería", pair_override = nil },
  },
  defaults = {
    send_db = -12,
    send_mode = 3,
    -- true = los sends nacen muteados, solo al crear el bus (si ya existe, no actúan).
    -- Click = role "click"; música = todo lo demás.
    mute_click_on_create = false,
    mute_music_on_create = true,
  },
  folders = {
    { role = "stems", aliases = nil, recursive = true },
    { role = "click", aliases = { "click", "metronomo" }, recursive = true },
  },
  include = {},
  exclude = { "lyrics" },
  guid_include = {},
  guid_exclude = {},
  overrides = {
    -- { match = "nombre del proyecto", include = {}, exclude = {},
    --   guid_include = {}, guid_exclude = {}, folders = nil },
  },
}