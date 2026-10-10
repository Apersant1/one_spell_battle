if OneSpellChaos == nil then
    OneSpellChaos = class({})
end

function OneSpellChaos:Init()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(15)

    OSC_Casino.Init()
    OSC_Commands.Init()
    OSC_HeroLifecycle.Init()
    OSC_Rotation.Init()
    OSC_ChaosRounds.Init()

    OSC_Logger.Log("One Spell Chaos loaded")
end
