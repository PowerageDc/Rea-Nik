return {
    undo = {
        enabled = true,
    },

    cc_curve = {
        preset = "Campana",
        lane = "active",
        channel = "active",
        mode = "replace",
        resolution = "native",
        dense_step_ms = 10,
        -- bend range del VSTi, en semitonos hacia cada lado
        bend_range_st = 2,
        verbose = true,

        -- engine: swell (lo, hi, base, peak), ramp (from, to, base) u osc (center,
        -- depth, base, wave, hz o cycles, phase, fade_in como fraccion del rango).
        -- close devuelve la lane a base al final. shape: 0 cuadrada, 1 lineal,
        -- 2 suave, 3 inicio rapido, 4 final rapido, 5 bezier con tension.
        -- resolution por preset pisa a la general. Valores de CC de 0 a 127; en
        -- pitch bend, en cents (se convierten con bend_range_st).
        presets = {
            ["Campana"] = {
                engine = "swell", peak = 0.5, close = true, shape = 2, tension = 0,
                cc = { lo = 0, hi = 100, base = 0 },
                pitchbend = { lo = 0, hi = 100, base = 0 },
            },
            ["Crescendo"] = {
                engine = "swell", peak = 0.85, close = true, shape = 2, tension = 0,
                cc = { lo = 10, hi = 110, base = 0 },
                pitchbend = { lo = 0, hi = 50, base = 0 },
            },
            ["Subida suave"] = {
                engine = "ramp", close = false, shape = 2, tension = 0,
                cc = { from = 0, to = 100, base = 0 },
                pitchbend = { from = 0, to = 50, base = 0 },
            },
            ["Bajada lineal"] = {
                engine = "ramp", close = false, shape = 1, tension = 0,
                cc = { from = 100, to = 0, base = 0 },
                pitchbend = { from = 50, to = 0, base = 0 },
            },
            ["Vibrato"] = {
                engine = "osc", wave = "sine", hz = 5.5, phase = 0, fade_in = 0.3, close = true,
                cc = { center = 40, depth = 30, base = 0 },
                pitchbend = { center = 0, depth = 15, base = 0 },
            },
            ["Tremolo"] = {
                engine = "osc", wave = "triangle", hz = 6, phase = 0, fade_in = 0, close = true,
                cc = { center = 70, depth = 40, base = 0 },
                pitchbend = { center = 0, depth = 10, base = 0 },
            },
            ["Pulsos"] = {
                engine = "osc", wave = "square", hz = 2, phase = 0, fade_in = 0, close = true,
                cc = { center = 60, depth = 40, base = 0 },
                pitchbend = { center = 0, depth = 25, base = 0 },
            },
            ["Sierra"] = {
                engine = "osc", wave = "saw_up", cycles = 3, phase = 0, fade_in = 0, close = true,
                cc = { center = 60, depth = 40, base = 0 },
                pitchbend = { center = 0, depth = 25, base = 0 },
            },
            -- bend: rise (subida), hold (sosten: flat, osc, swell o ramp) y fall
            -- (bajada a base al final del rango). unit "ms" o "pct" (% del rango);
            -- from_previous sube desde el valor anterior de la lane en vez de base.
            ["Bend"] = {
                engine = "bend",
                rise = { unit = "ms", amount = 120, shape = 2 },
                fall = { unit = "ms", amount = 60, shape = 2 },
                hold = { engine = "flat" },
                cc = { base = 0, center = 80 },
                pitchbend = { base = 0, center = 100 },
            },
            ["Bend + vibrato"] = {
                engine = "bend",
                rise = { unit = "ms", amount = 120, shape = 2 },
                fall = { unit = "ms", amount = 60, shape = 2 },
                hold = { engine = "osc", wave = "sine", hz = 5.5, phase = 0, fade_in = 0.4 },
                cc = { base = 0, center = 80, depth = 20 },
                pitchbend = { base = 0, center = 100, depth = 12 },
            },
            ["Bend lento"] = {
                engine = "bend",
                rise = { unit = "pct", amount = 40, shape = 2 },
                fall = { unit = "ms", amount = 60, shape = 2 },
                hold = { engine = "flat" },
                cc = { base = 0, center = 100 },
                pitchbend = { base = 0, center = 150 },
            },
        },
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