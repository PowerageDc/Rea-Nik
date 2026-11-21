return {
    probe_mode = "selected",
    merge_tolerance_ms = 1,
    window_ms = 20,
    print_every_ms = 1000,
    sample_rate = 44100,
    floor_db = -120,
    preview_prefix = "GR_",
    seg = {
        open_db = -45,
        close_db = -50,
        min_gap_ms = 150,
        min_len_ms = 60,
        smooth_ms = 60,
        level_split = true,
        level_step_db = 4,
        level_hold_ms = 60,
    },
}