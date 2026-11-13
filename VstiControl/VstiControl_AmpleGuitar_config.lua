local ON_OFF = {
  { label = "On", value = 127 },
  { label = "Off", value = 0 },
}

local POS_VARIANTS = {
  { label = "Mantiene pos.", velocity = 40 },
  { label = "Cambia pos.", velocity = 100 },
}

local function fx(label, pitch)
  return { kind = "ks", label = label, pitch = pitch, mode = "cursor" }
end

return {
  name = "Ample Guitar",
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
        { kind = "ks", label = "Sustain & Pop", pitch = "C0" },
        { kind = "ks", label = "Natural Harmonic", pitch = "C#0" },
        { kind = "ks", label = "Palm Mute", pitch = "D0" },
        { kind = "ks", label = "Slide In & Out", pitch = "D#0" },
        { kind = "ks", label = "Legato Slide", pitch = "E0", variants = POS_VARIANTS },
        { kind = "ks", label = "Hammer-On / Pull-Off", pitch = "F0", variants = POS_VARIANTS },
      },
    },
    {
      title = "Cuerda",
      controls = {
        { kind = "ks", label = "Cuerda 6", pitch = "G0", variants = POS_VARIANTS },
        { kind = "ks", label = "Cuerda 5", pitch = "G#0", variants = POS_VARIANTS },
        { kind = "ks", label = "Cuerda 4", pitch = "A0", variants = POS_VARIANTS },
        { kind = "ks", label = "Cuerda 3", pitch = "A#0", variants = POS_VARIANTS },
        { kind = "ks", label = "Cuerda 2", pitch = "B0", variants = POS_VARIANTS },
        { kind = "ks", label = "Cuerda 1", pitch = "C1", variants = POS_VARIANTS },
      },
    },
    {
      title = "Mano izquierda",
      controls = {
        { kind = "position", label = "Posicion", count = 17, first = 0,
          via = "ks_pair", enable = "C#1", base = "E1", stagger = 1 },
        { kind = "ks", label = "Open String First", pitch = "G#6",
          variants = {
            { label = "On", velocity = 100 },
            { label = "Off", velocity = 30 },
          } },
      },
    },
    {
      title = "FX",
      controls = {
        fx("Scratch", "F5"),
        fx("Slap", "F#5"),
        fx("Muting", "G5"),
        fx("Strum Mute", "G#5"),
        fx("Downstroke Noise 1", "A5"),
        fx("Upstroke Noise 1", "A#5"),
        fx("Downstroke Noise 2", "B5"),
        fx("Upstroke Noise 2", "C6"),
        fx("Hit Top (Open)", "F6"),
        fx("Hit Top (Mute)", "F#6"),
        fx("Hit Rim", "G6"),
      },
    },
    {
      title = "Curvas",
      controls = {
        { kind = "cc", label = "Vibrato Wheel", cc = 1,
          presets = { { label = "Off", value = 0 } } },
        { kind = "cc", label = "Bend", cc = "pw", min = -8192, max = 8191,
          scale = { center = 0, unit = "st", neg = 4, pos = 4 },
          presets = { { label = "Centro", value = 0 } } },
      },
    },
    {
      title = "Switches",
      controls = {
        { kind = "cc", label = "Stroke Noise", cc = 15, presets = ON_OFF },
      },
    },
  },
}