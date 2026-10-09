OSC_ChaosRounds = {
    started = false,
    warned = false,
    active = nil,
    previousEvent = nil,
}

local EVENTS = {
    {
        id = "cooldowns",
        name = "Перезарядки ускорены на 40%",
        modifier = "modifier_osc_chaos_cooldowns",
        target = "heroes",
    },
}

local function IsValidEntity(entity)
    return entity and not entity:IsNull()
end

local function ApplyModifier(unit, modifier, duration)
    if not IsValidEntity(unit) then return false end
    local result = unit:AddNewModifier(unit, nil, modifier, { duration = duration })
    if not result or result:IsNull() then
        OSC_Logger.Error("Failed to apply chaos round modifier " .. modifier
            .. " to " .. unit:GetUnitName())
        return false
    end
    return true
end

local function ApplyToHeroes(event, duration)
    local appliedCount = 0
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            local hero = PlayerResource:GetSelectedHeroEntity(playerID)
            if IsValidEntity(hero) and hero:IsHero() then
                if ApplyModifier(hero, event.modifier, duration) then
                    appliedCount = appliedCount + 1
                end
            end
        end
    end

    if appliedCount == 0 then
        OSC_Logger.Error("Cooldown chaos round found no heroes to apply its modifier to")
    else
        OSC_Logger.Log("Cooldown chaos modifier applied to " .. appliedCount
            .. " hero(es); icon=item_octarine_core")
    end
end

local function ApplyEvent(event, duration)
    if event.target == "heroes" then
        ApplyToHeroes(event, duration)
    end
end

local function PickEvent()
    local candidates = {}
    for _, event in ipairs(EVENTS) do
        if event.id ~= OSC_ChaosRounds.previousEvent then
            table.insert(candidates, event)
        end
    end
    if #candidates == 0 then
        candidates = EVENTS
    end
    return candidates[RandomInt(1, #candidates)]
end

local function StartEvent()
    local event = PickEvent()
    local duration = OSC_CONFIG.CHAOS_ROUNDS.DURATION
    OSC_ChaosRounds.active = {
        event = event,
        endsAt = GameRules:GetGameTime() + duration,
    }
    OSC_ChaosRounds.previousEvent = event.id

    ApplyEvent(event, duration)
    OSC_Notifications.ChaosRoundStarted(event.name, duration)
    OSC_Logger.Log("Chaos round started: " .. event.id)
end

local function EndEvent()
    local event = OSC_ChaosRounds.active.event
    OSC_ChaosRounds.active = nil
    OSC_Notifications.ChaosRoundEnded(event.name)
    OSC_Logger.Log("Chaos round ended: " .. event.id)
end

function OSC_ChaosRounds.Think()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
        return nil
    end

    local now = GameRules:GetGameTime()
    if OSC_ChaosRounds.active then
        if now >= OSC_ChaosRounds.active.endsAt then
            EndEvent()
        end
        return 0.5
    end

    local timeLeft = OSC_ChaosRounds.nextRoundAt - now
    if not OSC_ChaosRounds.warned and timeLeft <= OSC_CONFIG.CHAOS_ROUNDS.WARNING_TIME then
        OSC_ChaosRounds.warned = true
        OSC_Notifications.ChaosRoundWarning(OSC_CONFIG.CHAOS_ROUNDS.WARNING_TIME)
    end

    if timeLeft <= 0 then
        StartEvent()
        OSC_ChaosRounds.nextRoundAt = OSC_ChaosRounds.nextRoundAt
            + OSC_CONFIG.CHAOS_ROUNDS.INTERVAL
        OSC_ChaosRounds.warned = false
    end

    return 0.5
end

local function StartTimer()
    if OSC_ChaosRounds.started then return end
    OSC_ChaosRounds.started = true
    OSC_ChaosRounds.nextRoundAt = GameRules:GetGameTime() + OSC_CONFIG.CHAOS_ROUNDS.INTERVAL
    OSC_ChaosRounds.warned = false
    GameRules:GetGameModeEntity():SetThink(
        "Think",
        OSC_ChaosRounds,
        "osc_chaos_rounds",
        0.5
    )
    OSC_Logger.Log("Chaos round schedule started")
end

local function OnStateChange()
    if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        StartTimer()
    end
end

function OSC_ChaosRounds.Init()
    ListenToGameEvent("game_rules_state_change", OnStateChange, nil)
end
