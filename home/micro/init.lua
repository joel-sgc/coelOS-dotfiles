local micro = import("micro")
local config = import("micro/config")

function toggleWordWrap(bp)
    local curVal = config.GetGlobalOption("wordwrap")
    if curVal == nil then
        curVal = false
    end
    config.SetGlobalOptionNative("wordwrap", not curVal)
    config.SetGlobalOptionNative("softwrap", not curVal)
    return true
end

function selectAllOccurrences(bp)
    local count = 0
    while bp:SpawnMultiCursor() and count < 1000 do
        count = count + 1
    end
    return true
end
