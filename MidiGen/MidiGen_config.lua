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

    gliss = {
        preset = "Pulgar",
        channel = "active",
        verbose = true,

        -- mode: "merge" conserva las notas existentes; "replace" borra las
        -- notas no seleccionadas del canal que arrancan entre la primera nota
        -- generada y el final (el destino queda)
        mode = "merge",

        -- pitch classes de cada conjunto (0 = Do)
        sets = {
            white = { 0, 2, 4, 5, 7, 9, 11 },
            black = { 1, 3, 6, 8, 10 },
        },

        -- una sola nota seleccionada: es el destino; el glissando llega a ella
        -- desde count notas del conjunto, subiendo (up) o bajando (down). Con
        -- from_pitch (opcional, pitch MIDI) el origen es ese pitch y count no se usa
        single = { count = 12, direction = "up" },

        -- con time selection y sin notas seleccionadas: de from_pitch a to_pitch
        -- (ambos incluidos si pertenecen al conjunto), con esa velocity
        range = { from_pitch = 48, to_pitch = 84, velocity = 100 },

        -- contact: teclas apretadas a la vez (1 = cada nota dura hasta la
        -- siguiente; mas = solape de palma). timing.mode: "total" (total_ms) o
        -- "per_note" (note_ms); curve < 1 acelera, > 1 frena. velocity: factor
        -- sobre la velocity del destino, de la primera nota a la ultima.
        presets = {
            ["Pulgar"] = {
                set = "white", contact = 1,
                timing = { mode = "total", total_ms = 300, note_ms = 25, curve = 0.9, jitter_ms = 0 },
                velocity = { from = 0.85, to = 1.0, curve = 1.0, jitter = 3 },
            },
            ["Palma"] = {
                set = "white", contact = 3,
                timing = { mode = "total", total_ms = 140, note_ms = 12, curve = 1.0, jitter_ms = 0 },
                velocity = { from = 0.9, to = 1.0, curve = 1.0, jitter = 2 },
            },
            ["Negras"] = {
                set = "black", contact = 1,
                timing = { mode = "total", total_ms = 350, note_ms = 40, curve = 0.9, jitter_ms = 0 },
                velocity = { from = 0.85, to = 1.0, curve = 1.0, jitter = 3 },
            },
        },
    },
}