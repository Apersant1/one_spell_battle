OSC_Rotation = {
    timer_started = false,
    warned = false,
}

local function PublishTimer()
    CustomNetTables:SetTableValue("osc_state", "timer", {
        next_rotation = OSC_Rotation.next_time or -1,
    })
end

local function RotateAll()
    OSC_Notifications.RotationStarted()

    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            local hero = PlayerResource:GetSelectedHeroEntity(playerID)
            if hero and not hero:IsNull() and hero.osc_initialized then
                OSC_Abilities.GiveRandom(hero, true)
            end
        end
    end
end

function OSC_Rotation.Think()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
        return nil
    end

    local timeLeft = OSC_Rotation.next_time - GameRules:GetGameTime()
    if not OSC_Rotation.warned and timeLeft <= OSC_CONFIG.WARNING_TIME then
        OSC_Rotation.warned = true
        OSC_Notifications.RotationWarning(OSC_CONFIG.WARNING_TIME)
    end

    if timeLeft <= 0 then
        RotateAll()
        OSC_Rotation.next_time = OSC_Rotation.next_time + OSC_CONFIG.ROTATION_INTERVAL
        OSC_Rotation.warned = false
        PublishTimer()
    end

    return 0.5
end

local function StartTimer()
    if OSC_Rotation.timer_started then return end
    OSC_Rotation.timer_started = true
    OSC_Rotation.next_time = GameRules:GetGameTime() + OSC_CONFIG.ROTATION_INTERVAL
    OSC_Rotation.warned = false
    PublishTimer()
    OSC_Logger.Log("Rotation timer started")
    GameRules:GetGameModeEntity():SetThink("Think", OSC_Rotation, "osc_rotation", 0.5)
end

local function OnStateChange()
    if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        StartTimer()
    end
end

function OSC_Rotation.Init()
    PublishTimer()
    ListenToGameEvent("game_rules_state_change", OnStateChange, nil)
end
