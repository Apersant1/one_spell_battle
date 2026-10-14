require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/game_events")
require("osc/core/hero_state")
require("osc/core/anchor")
require("osc/systems/rotation_choice")

OSC_Rotation = OSC_Rotation or {
    timer_started = false,
    warned = false,
    round = 0, -- номер ближайшей ротации; растёт в момент предупреждения
}

local function PublishTimer()
    CustomNetTables:SetTableValue("osc_state", "timer", {
        next_rotation = OSC_Rotation.next_time or -1,
        interval = OSC_Config.Get("ROTATION_INTERVAL"),
    })
end

-- Новая способность героя на ротации: выбранная из трёх (или случайная из
-- предложенных), а без предложения — случайная. Предложение закрывается в
-- любом случае, даже если выдача сорвалась.
local function RotateHero(hero, round)
    -- «Якорь»: эту ротацию герой пропускает, с якоря снимается одна ротация
    if OSC_Anchor.Consume(hero) then
        OSC_RotationChoice.Close(hero, OSC_HeroState.Get(hero).ability)
        OSC_Logger.Log("Rotation skipped by anchor for " .. hero:GetUnitName())
        return
    end

    local entry = OSC_RotationChoice.TakeEntry(hero, round)
    local ok, result = pcall(function()
        if entry then
            return OSC_Abilities.Give(hero, "ability", entry, true)
        end
        return OSC_Abilities.GiveRandom(hero, true)
    end)
    local chosen = ok and result and result.name or OSC_HeroState.Get(hero).ability
    OSC_RotationChoice.Close(hero, chosen)
    if not ok then
        error(result, 0)
    end
end

local function RotateAll()
    local ok, err = pcall(OSC_Notifications.RotationStarted)
    if not ok then OSC_Logger.Error("RotationStarted: " .. tostring(err)) end

    local round = OSC_Rotation.round or 0
    OSC_Heroes.ForEachPlayerHero(function(hero, playerID)
        if OSC_HeroState.Get(hero).initialized then
            local heroOk, heroErr = pcall(RotateHero, hero, round)
            if not heroOk then
                OSC_Logger.Error("Rotation for player " .. playerID .. ": " .. tostring(heroErr))
            end
        end
    end)
end

function OSC_Rotation.Think()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
        return nil
    end

    local timeLeft = OSC_Rotation.next_time - GameRules:GetGameTime()
    if not OSC_Rotation.warned and timeLeft <= OSC_Config.Get("WARNING_TIME") then
        OSC_Rotation.warned = true
        OSC_Rotation.round = (OSC_Rotation.round or 0) + 1
        OSC_Notifications.RotationWarning(OSC_Config.Get("WARNING_TIME"))
        OSC_RotationChoice.OfferAll(OSC_Rotation.round, OSC_Rotation.next_time)
    end

    if timeLeft <= 0 then
        RotateAll()
        OSC_Rotation.next_time = OSC_Rotation.next_time + OSC_Config.Get("ROTATION_INTERVAL")
        OSC_Rotation.warned = false
        PublishTimer()
    end

    return 0.5
end

local function StartTimer()
    if OSC_Rotation.timer_started then return end
    OSC_Rotation.timer_started = true
    OSC_Rotation.next_time = GameRules:GetGameTime() + OSC_Config.Get("ROTATION_INTERVAL")
    OSC_Rotation.warned = false
    PublishTimer()
    OSC_Logger.Log("Rotation timer started")
    GameRules:GetGameModeEntity():SetThink("Think", OSC_Rotation, "osc_rotation", 0.5)
end

function OSC_Rotation.Init()
    PublishTimer()
    OSC_RotationChoice.Init()
    OSC_GameEvents.Subscribe("game_started", "rotation", function()
        StartTimer()
    end)
end
