local ON_OFF = {
  { label = "On", value = 127 },
  { label = "Off", value = 0 },
}

return {
  name = "MODO Bass 2",
  channel = 1,
  middle_c = 3,
  defaults = {
    ks_length = 60,
    ks_velocity = 100,
    ks_offset = 0,
    ramp_shape = "linear",
  },
  groups = {
    {
      title = "Articulaciones",
      controls = {
        { kind = "ks", label = "Pizzicato / Finger", pitch = "C#0" },
        { kind = "ks", label = "Pick", pitch = "D#0" },
        { kind = "ks", label = "Slap", pitch = "F#0" },
        { kind = "ks", label = "DB Slap Noise", pitch = "C#1" },
        { kind = "ks", label = "DB Stop Strings", pitch = "D#1" },
      },
    },
    {
      title = "Técnicas",
      controls = {
        { kind = "ks", label = "Ham. On / Pull Off", pitch = "C0" },
        { kind = "ks", label = "Ghost Mode", pitch = "A#-1" },
        { kind = "ks", label = "Harmonics", pitch = "F0" },
        { kind = "ks", label = "Index Stroke", pitch = "C#-1" },
        { kind = "ks", label = "Middle Stroke", pitch = "D#-1" },
        { kind = "ks", label = "Stop on Detach", pitch = "G#0" },
      },
    },
    {
      title = "Forzar cuerda",
      controls = {
        { kind = "ks", label = "B", pitch = "B-1" },
        { kind = "ks", label = "E", pitch = "E0" },
        { kind = "ks", label = "A", pitch = "A-1" },
        { kind = "ks", label = "D", pitch = "D0" },
        { kind = "ks", label = "G", pitch = "G0" },
        { kind = "ks", label = "C", pitch = "C-1" },
      },
    },
    {
      title = "Curvas",
      controls = {
        { kind = "cc", label = "Bend", cc = 5, min = 0, max = 127,
          scale = { center = 64, unit = "st", neg = 4, pos = 4 } },
        { kind = "cc", label = "Vibrato", cc = 1 },
        { kind = "cc", label = "Muting", cc = 9 },
        { kind = "cc", label = "Pluck Position", cc = 3 },
        { kind = "cc", label = "Slide (pitch wheel)", cc = "pw", min = -8192, max = 8191,
          scale = { center = 0, unit = "st", neg = 12, pos = 12 },
          presets = { { label = "Centro", value = 0 } } },
      },
    },
    {
      title = "Mano izquierda",
      controls = {
        { kind = "position", label = "Posicion", count = 17, first = 1, via = "cc", cc = 4,
          step = 5.3 },
      },
    },
    {
      title = "Switches",
      controls = {
        { kind = "cc", label = "Legato Slide", cc = 65, presets = ON_OFF },
        { kind = "cc", label = "Let Ring", cc = 64, presets = ON_OFF },
        { kind = "cc", label = "Chord Mode", cc = 2, presets = ON_OFF },
      },
    },
  },
}