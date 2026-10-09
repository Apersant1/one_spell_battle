OSC_Commands = {}

local function OnPlayerChat(event)
    local text = string.lower(string.match(event.text or "", "^%s*(.-)%s*$"))
    local playerID = event.playerid
    local abilityName = string.match(text, "^%-courier_ability%s*(%S*)$")
    if abilityName ~= nil then
        if not OSC_CONFIG.ENABLE_COURIER_DEBUG_CHAT_COMMAND then
            OSC_Logger.Log("Ignored disabled -courier_ability chat command")
            return
        end

        if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
            OSC_Logger.Error("-courier_ability ignored: invalid player")
            return
        end

        local hero = PlayerResource:GetSelectedHeroEntity(playerID)
        if not hero or hero:IsNull() then
            OSC_Logger.Error("-courier_ability ignored: player has no hero")
            return
        end

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

    if text ~= "-reroll" then return end
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        OSC_Logger.Error("-reroll ignored: invalid player")
        return
    end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    if not hero or not hero.osc_initialized then
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
