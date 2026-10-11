if OneSpellChaos == nil then
    OneSpellChaos = class({})
end

local function SafeInit(name, module)
    if module == nil then
        OSC_Logger.Log("[OSC] " .. name .. " init skipped: module not loaded (check require)")
        return
    end
    local ok, err = pcall(function() module:Init() end)
    if not ok then OSC_Logger.Log("[OSC] " .. name .. " init failed: " .. tostring(err)) end
end

function OneSpellChaos:Init()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(15)
    GameRules:SetCustomGameSetupTimeout(60) -- длительность фазы (0 = пропустить, -1 = без лимита)
    GameRules:LockCustomGameSetupTeamAssignment(false)

    CustomNetTables:SetTableValue("osc_state", "version", {
        version = OSC_CONFIG.VERSION,
    })

    SafeInit("TeamShuffle", OSC_TeamShuffle)
    SafeInit("Casino", OSC_Casino)
    SafeInit("Commands", OSC_Commands)
    SafeInit("HeroLifecycle", OSC_HeroLifecycle)
    SafeInit("Rotation", OSC_Rotation)
    SafeInit("ChaosRounds", OSC_ChaosRounds)

    OSC_Logger.Log("One Spell Chaos loaded")
end