OSC_Notifications = {}

function OSC_Notifications.TeamMessage(team, message)
    GameRules:SendCustomMessage(message, team or 0, 0)
end

function OSC_Notifications.PlayerEvent(player, eventName, data)
    if not player then
        OSC_Logger.Error("Cannot send event '" .. eventName .. "': player is unavailable")
        return false
    end

    CustomGameEventManager:Send_ServerToPlayer(player, eventName, data)
    return true
end

function OSC_Notifications.AbilityChanged(hero, entry)
    local particle = ParticleManager:CreateParticle(
        "particles/generic_hero_status/hero_levelup.vpcf",
        PATTACH_ABSORIGIN_FOLLOW,
        hero
    )
    ParticleManager:ReleaseParticleIndex(particle)

    local player = PlayerResource:GetPlayer(hero:GetPlayerOwnerID())
    if not player then return end

    OSC_Notifications.PlayerEvent(player, "osc_ability_changed", {
        ability = entry.name,
        label = entry.label,
    })

    if OSC_CONFIG.CHAT_MESSAGES then
        Say(player, "Моя способность: " .. entry.label, true)
    end
end

function OSC_Notifications.RotationWarning(seconds)
    if not OSC_CONFIG.CHAT_MESSAGES then return end
    OSC_Notifications.TeamMessage(
        0,
        "<font color='#FF8C00'>Смена способностей через " .. seconds .. " сек!</font>"
    )
end

function OSC_Notifications.RotationStarted()
    if not OSC_CONFIG.CHAT_MESSAGES then return end
    OSC_Notifications.TeamMessage(
        0,
        "<font color='#FFD700'>ХАОС! Все получили новые способности!</font>"
    )
end

function OSC_Notifications.ChaosRoundWarning(seconds)
    OSC_Notifications.TeamMessage(
        0,
        "<font color='#FF8C00'>Хаос-раунд начнётся через "
            .. seconds .. " сек.!</font>"
    )
end

function OSC_Notifications.ChaosRoundStarted(eventName, duration)
    OSC_Notifications.TeamMessage(
        0,
        "<font color='#FF4D4D'>ХАОС-РАУНД: " .. eventName
            .. "! Длительность: " .. duration .. " сек.</font>"
    )
end

function OSC_Notifications.ChaosRoundEnded(eventName)
    OSC_Notifications.TeamMessage(
        0,
        "<font color='#B0B0B0'>Хаос-раунд «" .. eventName .. "» завершён.</font>"
    )
end
