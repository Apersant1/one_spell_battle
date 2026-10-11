OSC_ConfigValidation = {}

local function ValidatePool(poolName, pool)
    local errors = {}
    if type(pool) ~= "table" then
        table.insert(errors, poolName .. " is not a table")
        return errors
    end

    local seen = {}
    for index, entry in ipairs(pool) do
        if type(entry) ~= "table" then
            table.insert(errors, poolName .. " entry at index " .. tostring(index) .. " is not a table")
        else
            if type(entry.name) ~= "string" or entry.name == "" then
                table.insert(errors, poolName .. " entry at index " .. tostring(index) .. " has no valid name")
            elseif seen[entry.name] then
                table.insert(errors, poolName .. " contains duplicate ability name: " .. tostring(entry.name))
            else
                seen[entry.name] = true
            end

            local weight = entry.weight == nil and 4 or entry.weight
            if type(weight) ~= "number" or weight <= 0 or weight ~= math.floor(weight) then
                table.insert(errors, poolName .. " entry " .. tostring(entry.name) .. " has invalid weight: " .. tostring(weight))
            end
        end
    end

    return errors
end

function OSC_ConfigValidation.Validate()
    local errors = {}
    if type(OSC_CONFIG) ~= "table" then
        OSC_Logger.Error("Config validation failed: OSC_CONFIG is missing")
        return false
    end

    local totalChance = 0
    local seenOutcomeSymbols = {}
    local outcomes = OSC_CONFIG.CASINO_OUTCOMES or {}
    for index, outcome in ipairs(outcomes) do
        if type(outcome) ~= "table" then
            table.insert(errors, "CASINO_OUTCOMES[" .. tostring(index) .. "] is not a table")
        else
            local symbol = outcome.symbol
            local chance = outcome.chance
            local multiplier = outcome.multiplier
            if type(symbol) ~= "string" or symbol == "" then
                table.insert(errors, "CASINO_OUTCOMES[" .. tostring(index) .. "] has no symbol")
            elseif seenOutcomeSymbols[symbol] then
                table.insert(errors, "CASINO_OUTCOMES contains duplicate symbol: " .. tostring(symbol))
            else
                seenOutcomeSymbols[symbol] = true
            end

            if type(chance) ~= "number" or chance <= 0 then
                table.insert(errors, "CASINO_OUTCOMES[" .. tostring(index) .. "] has invalid chance: " .. tostring(chance))
            else
                totalChance = totalChance + chance
            end

            if type(multiplier) ~= "number" or multiplier < 0 then
                table.insert(errors, "CASINO_OUTCOMES[" .. tostring(index) .. "] has invalid multiplier: " .. tostring(multiplier))
            end
        end
    end

    if totalChance > 100 then
        table.insert(errors, "CASINO_OUTCOMES total chance exceeds 100 (" .. tostring(totalChance) .. ")")
    end

    if type(OSC_CONFIG.CASINO_MIN_SPIN_COST) ~= "number" or type(OSC_CONFIG.CASINO_DEFAULT_STAKE) ~= "number" then
        table.insert(errors, "Casino stake configuration must be numeric")
    elseif OSC_CONFIG.CASINO_MIN_SPIN_COST > OSC_CONFIG.CASINO_DEFAULT_STAKE then
        table.insert(errors, "CASINO_MIN_SPIN_COST cannot exceed CASINO_DEFAULT_STAKE")
    end

    for _, poolName in ipairs({ "OSC_ABILITY_POOL", "OSC_ULTIMATE_POOL" }) do
        local pool = _G[poolName]
        for _, entry in ipairs(ValidatePool(poolName, pool)) do
            table.insert(errors, entry)
        end
    end

    local maxDuplicates = OSC_CONFIG.MAX_DUPLICATE_ULTIMATES_PER_TEAM
    if type(maxDuplicates) ~= "number" or maxDuplicates < 1 then
        table.insert(errors, "MAX_DUPLICATE_ULTIMATES_PER_TEAM must be at least 1")
    end

    local rotationInterval = OSC_CONFIG.ROTATION_INTERVAL
    if type(rotationInterval) == "number" and type(OSC_CONFIG.WARNING_TIME) == "number" and OSC_CONFIG.WARNING_TIME >= rotationInterval then
        table.insert(errors, "WARNING_TIME must be less than ROTATION_INTERVAL")
    end

    local chaos = OSC_CONFIG.CHAOS_ROUNDS or {}
    local chaosWarning = chaos.WARNING_TIME
    local chaosDuration = chaos.DURATION
    local chaosInterval = chaos.INTERVAL
    if type(chaosWarning) == "number" and type(chaosDuration) == "number" and type(chaosInterval) == "number" then
        if chaosWarning + chaosDuration >= chaosInterval then
            table.insert(errors, "CHAOS_ROUNDS.WARNING_TIME + DURATION must be less than INTERVAL")
        end
    end

    if #errors > 0 then
        for _, message in ipairs(errors) do
            OSC_Logger.Error("Config validation: " .. tostring(message))
        end
        return false
    end

    return true
end
