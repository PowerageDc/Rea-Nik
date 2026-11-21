local M = {}

local function to_db(x, floor_db, gain_db)
    if x <= 0 then return floor_db end
    local db = 20 * math.log(x, 10) + gain_db
    return db < floor_db and floor_db or db
end

-- Mide RMS y pico por ventana dentro de [part.t0, part.t1] (tiempo de proyecto).
-- El accessor de take recibe el tiempo relativo al inicio del item.
function M.part_levels(part, opts)
    local take = reaper.GetActiveTake(part.item)
    if not take or reaper.TakeIsMIDI(take) then return nil, "take sin audio" end

    local src = reaper.GetMediaItemTake_Source(take)
    local nch = math.min(2, reaper.GetMediaSourceNumChannels(src))
    local acc = reaper.CreateTakeAudioAccessor(take)
    local sr = opts.sample_rate
    local n = math.floor(opts.window_s * sr + 0.5)
    local buf = reaper.new_array(n * nch)

    local info = {
        acc_start = reaper.GetAudioAccessorStartTime(acc),
        acc_end = reaper.GetAudioAccessorEndTime(acc),
        channels = nch,
        item_vol_db = to_db(math.abs(reaper.GetMediaItemInfo_Value(part.item, "D_VOL")), opts.floor_db, 0),
        take_vol_db = to_db(math.abs(reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")), opts.floor_db, 0),
    }
    info.gain_db = info.item_vol_db + info.take_vol_db

    local rows = {}
    local t = part.t0
    while t + opts.window_s <= part.t1 + 1e-9 do
        buf.clear()
        local got = reaper.GetAudioAccessorSamples(acc, sr, nch, t - part.pos, n, buf)
        local sum, peak, count = 0, 0, 0
        if got == 1 then
            local s = buf.table()
            count = #s
            for i = 1, count do
                local v = s[i]
                sum = sum + v * v
                if v < 0 then v = -v end
                if v > peak then peak = v end
            end
        end
        local rms = count > 0 and math.sqrt(sum / count) or 0
        rows[#rows + 1] = {
            t = t,
            rms_db = to_db(rms, opts.floor_db, info.gain_db),
            peak_db = to_db(peak, opts.floor_db, info.gain_db),
            got = got,
        }
        t = t + opts.window_s
    end

    reaper.DestroyAudioAccessor(acc)
    return rows, info
end

return M