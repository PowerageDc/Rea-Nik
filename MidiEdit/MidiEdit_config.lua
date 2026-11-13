return {
    undo = {
        enabled = true,
    },

    align_chord = {
        starts = "earliest",
        ends = "latest",
    },

    strum = {
        default_style = "Folk abajo",
        chord_window_ms = 30,
        anchor = "first",
        ends = "keep",

        -- total_ms: duracion del despliegue; curve < 1 acelera, > 1 frena
        timings = {
            tight  = { total_ms = 20,  curve = 1.0,  jitter_ms = 1 },
            fast   = { total_ms = 35,  curve = 0.9,  jitter_ms = 2 },
            medium = { total_ms = 60,  curve = 0.85, jitter_ms = 3 },
            slow   = { total_ms = 100, curve = 0.85, jitter_ms = 4 },
            roll   = { total_ms = 160, curve = 1.0,  jitter_ms = 3 },
            arp    = { total_ms = 280, curve = 1.0,  jitter_ms = 0 },
        },

        -- factor sobre la velocity original, segun el orden de ataque
        dynamics = {
            decay = { from = 1.08, to = 0.86, curve = 1.0, jitter = 3, up_scale = 0.9 },
            flat  = { from = 1.0,  to = 1.0,  curve = 1.0, jitter = 2, up_scale = 1.0 },
            swell = { from = 0.85, to = 1.05, curve = 1.0, jitter = 2, up_scale = 1.0 },
        },

        styles = {
            ["Folk abajo"]   = { timing = "medium", dynamics = "decay", direction = "down" },
            ["Folk alterna"] = { timing = "medium", dynamics = "decay", direction = "alternate" },
            ["Rock seco"]    = { timing = "tight",  dynamics = "decay", direction = "down" },
            ["Piano roll"]   = { timing = "roll",   dynamics = "swell", direction = "down" },
            ["Arpegio"]      = { timing = "arp",    dynamics = "flat",  direction = "down" },
        },
    },
}