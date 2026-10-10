OSC_Commands = {}

local function OnPlayerChat(event)
    local text = string.lower(string.match(event.text or "", "^%s*(.-)%s*$"))
    local abilityName = string.match(text, "^%-courier_ability%s*(%S*)$")
    local isReroll = text == "-reroll"
    if abilityName == nil and not isReroll then return end

    if not OSC_CONFIG.DEVELOPMENT_MODE then
        OSC_Logger.Log("Ignored development chat command: " .. text)
        return
    end

    local playerID = event.playerid
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        OSC_Logger.Error(text .. " ignored: invalid player")
        return
    end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    if not hero or hero:IsNull() then
        OSC_Logger.Error(text .. " ignored: player has no hero")
        return
    end

    if abilityName ~= nil then
        abilityName = abilityName ~= "" and abilityName or "drunk"
        local ok, result = OSC_Couriers.DebugAbility(hero:GetTeamNumber(), abilityName)
        if not ok then
            OSC_Logger.Error(result)
            return
        end

        OSC_Logger.Log("Applied courier ability '" .. abilityName
            .. "' to " .. result .. " team courier(s)")
        return
    end

    if not hero.osc_initialized then
        OSC_Logger.Error("-reroll ignored: player has no initialized hero")
        return
    end

    OSC_Abilities.GiveRandom(hero, true)
end

local function OnStripCommand()
    local player = Convars:GetCommandClient()
    local hero = player and player:GetAssignedHero()
    if not hero then
        OSC_Logger.Error("osc_strip: no hero found")
        return
    end

    OSC_Abilities.StripHero(hero)
    OSC_Abilities.GiveRandom(hero, true)
    OSC_Logger.Log("Manual strip done")
end

function OSC_Commands.Init()
    ListenToGameEvent("player_chat", OnPlayerChat, nil)
    Convars:RegisterCommand(
        "osc_strip",
        OnStripCommand,
        "Strip abilities",
        FCVAR_CHEAT
    )
end
