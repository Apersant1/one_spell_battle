require("osc/core/heroes")
require("osc/core/game_events")
require("osc/core/hero_state")

OSC_Rotation = OSC_Rotation or {
    timer_started = false,
    warned = false,
}

local function PublishTimer()
    CustomNetTables:SetTableValue("osc_state", "timer", {
        next_rotation = OSC_Rotation.next_time or -1,
        interval = OSC_CONFIG.ROTATION_INTERVAL,
    })
end



local function RotateAll()
    local ok, err = pcall(OSC_Notifications.RotationStarted)
    if not ok then OSC_Logger.Error("RotationStarted: " .. tostring(err)) end

    OSC_Heroes.ForEachPlayerHero(function(hero, playerID)
        if OSC_HeroState.Get(hero).initialized then
            local ok, err = pcall(OSC_Abilities.GiveRandom, hero, true)
            if not ok then
                OSC_Logger.Error("GiveRandom for player " .. playerID .. ": " .. tostring(err))
            end
        end
    end)
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

function OSC_Rotation.Init()
    PublishTimer()
    OSC_GameEvents.Subscribe("game_started", "rotation", function()
        StartTimer()
    end)
end
