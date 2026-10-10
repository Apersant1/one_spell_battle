if OneSpellChaos == nil then
    OneSpellChaos = class({})
end

function OneSpellChaos:Init()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(15)

    CustomNetTables:SetTableValue("osc_state", "version", {
        version = OSC_CONFIG.VERSION,
    })

    OSC_Casino.Init()
    OSC_Commands.Init()
    OSC_HeroLifecycle.Init()
    OSC_Rotation.Init()
    OSC_ChaosRounds.Init()

    OSC_Logger.Log("One Spell Chaos loaded")
end
