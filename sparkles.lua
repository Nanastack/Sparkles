addon = addon or {}
addon.name = 'sparkles'
addon.author = ' Windower Author - Rubenator (Ashita port by Zarianna)'
addon.version = '1.0.0'
addon.desc = 'Displays the names/nameplates of otherwise hidden entities.'

local ffi = require('ffi')
local bit = require('bit')
local show_names = true
local cache = {}
local debug_index = nil -- Set an entity index here to log its 0x00E updates.

-- Incoming packet 0x00E has a four-byte packet header. These offsets are
-- packet-relative and match Windower's NPC Update layout.
local function read_u8(data, offset)
    return data:byte(offset + 1) or 0
end

local function read_u16(data, offset)
    local a, b = data:byte(offset + 1, offset + 2)
    if not b then return 0 end
    return a + b * 0x100
end

local function read_u32(data, offset)
    local a, b, c, d = data:byte(offset + 1, offset + 4)
    if not d then return 0 end
    return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

local function show_nameplate(packet, untargetable, is_mob)
    local ptr = ffi.cast('uint8_t*', packet.data_modified_raw)
    local words = ffi.cast('uint32_t*', ptr)

    -- _unknown4 at 0x28; clear the nameplate-hidden bits (same mask used by
    -- the original Windower addon).
    words[0x28 / 4] = bit.band(words[0x28 / 4], 0xD7FFFFFF)

    if is_mob and untargetable then
        -- _unknown3 at 0x24: mark as blue.
        words[0x24 / 4] = bit.bor(words[0x24 / 4], 0x08000000)
    end
end

ashita.events.register('packet_in', 'sparkles_packet_in', function (e)
    if e.id == 0x00A then
        -- Zone transition: discard entity state from the previous zone.
        cache = {}
        return
    end

    if e.id ~= 0x00E or e.size < 0x36 then
        return
    end

    local data = e.data
    local index = read_u16(data, 0x08)
    local mask = read_u8(data, 0x0A)
    local rotation = read_u8(data, 0x0B)
    local walk_count = read_u32(data, 0x18)
    local unknown2 = read_u32(data, 0x20)
    local unknown4 = read_u32(data, 0x28)
    local model = read_u16(data, 0x32)

    local mask_position_update = bit.band(mask, 1) ~= 0
    local mask_status_update = bit.band(mask, 4) ~= 0
    local mask_name_update = bit.band(mask, 8) ~= 0
    local mask_depop = bit.band(mask, 32) ~= 0
    local mask_only_name = mask == 8
    local mask_model_update = mask_position_update or mask_status_update or mask_name_update
    local is_mob = bit.band(unknown2, 1) ~= 0
    local hide_nameplate = bit.band(unknown4, 0x08000000) ~= 0
    local hide_model = bit.band(unknown2, 2) ~= 0
    local untargetable = bit.band(unknown2, 0x00080000) ~= 0

    if mask_depop then
        cache[index] = nil
        return
    elseif not mask_only_name then
        cache[index] = { hide_model = hide_model, untargetable = untargetable }
    else
        local previous = cache[index]
        hide_model = hide_model or (previous and previous.hide_model) or false
        untargetable = untargetable or (previous and previous.untargetable) or false
    end

    if debug_index and index == debug_index then
        print(string.format('[Sparkles] 0x00E index=%d model=%d mask=%d', index, model, mask))
    end

    if model == 52 then
        if mask_model_update and not hide_model and not untargetable
            and (not mask_status_update or walk_count > 0 or rotation > 0) then
            -- Replace the sparkle model with the visible model used by the original.
            local ptr = ffi.cast('uint8_t*', e.data_modified_raw)
            ffi.cast('uint16_t*', ptr + 0x32)[0] = 1382
            if show_names then
                show_nameplate(e, untargetable, is_mob)
            end
        end
    elseif is_mob and hide_nameplate then
        if mask_model_update and not hide_model
            and (not mask_status_update or walk_count > 0 or rotation > 0) then
            show_nameplate(e, untargetable, is_mob)
        end
    end
end)
