return {
    move_view = true,
    seek_play = false,

    undo = {
        enabled = true,
    },

    measure = {
        tolerance_sec = 0.005,
        epsilon_sec = 0.0001,
    },

    notes = {
        channel_filter = "all",
        include_muted = true,
        chord_tol_ppq = 2,
    },

    select = {
        mode = "replace",
        move_cursor = "start",
        threshold_sec = 0.005,
        chord_pick_next = "lowest",
        chord_pick_prev = "lowest",
    },

    gap = {
        position = 0.5,
        min_gap_ppq = 1,
        no_gap_target = "next_start",
        no_gap_target_prev = "prev_end",
        selection_continue = true,
        tiebreak = "prev",
        tie_tol_ppq = 1,
        repeat_advances = true,
        same_pos_tol_sec = 0.002,
    },
}