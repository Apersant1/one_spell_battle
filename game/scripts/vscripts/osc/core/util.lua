-- Мелкие общие помощники, которые иначе повторялись по системам.

OSC_Util = OSC_Util or {}

function OSC_Util.Contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

-- Множество из списка: { a, b } -> { [a] = true, [b] = true }
function OSC_Util.ToSet(list)
    local set = {}
    for _, item in ipairs(list or {}) do
        set[item] = true
    end
    return set
end

-- callback(playerID) для каждого занятого слота игрока
function OSC_Util.ForEachPlayerID(callback)
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            callback(playerID)
        end
    end
end
