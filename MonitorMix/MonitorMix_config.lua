return {
  buses = {
    { name = "Monitor Bus - Batería" },
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