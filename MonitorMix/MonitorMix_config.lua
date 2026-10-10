return {
  buses = {
    { name = "Monitor Bus - Batería", pair_override = nil },
  },
  defaults = {
    send_db = -12,
    send_mode = 3,
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