require("osc/core/runtime_config")
require("osc/core/hero_state")

OSC_Commands = OSC_Commands or {}

local function OnPlayerChat(event)
    local text = string.lower(string.match(event.text or "", "^%s*(.-)%s*$"))
    local abilityName = string.match(text, "^%-courier_ability%s*(%S*)$")
    local isReroll = text == "-reroll"
    -- -hero_state: всё состояние героя режима, число способностей и модификаторов
    local isHeroState = text == "-hero_state"
    local isChaosStop = text == "-chaos_stop"
    local chaosId = text == "-chaos" and ""
        or string.match(text, "^%-chaos%s+(%S+)$")
    -- -casino <circle|diamond|star|seven>: следующие спины дают тройку символа; -casino off — обычный режим
    local casinoSymbol = string.match(text, "^%-casino%s+(%S+)$")
    if abilityName == nil and not isReroll and not isChaosStop and chaosId == nil
        and casinoSymbol == nil and not isHeroState then
        return
    end

    if not OSC_Config.Get("DEVELOPMENT_MODE") then
        OSC_Logger.Log("Ignored development chat command: " .. text)
        return
    end

    local playerID = event.playerid
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        OSC_Logger.Error(text .. " ignored: invalid player")
        return
    end

    if casinoSymbol ~= nil then
        local ok, err = OSC_Casino.DebugForceSymbol(casinoSymbol ~= "off" and casinoSymbol or nil)
        if ok then
            OSC_Logger.Log(text .. " executed by player " .. tostring(playerID))
        else
            OSC_Logger.Error(text .. " failed: " .. tostring(err))
        end
        return
    end

    if isChaosStop or chaosId ~= nil then
        local ok, err
        if isChaosStop then
            ok, err = OSC_ChaosRounds:DebugStop()
        else
            ok, err = OSC_ChaosRounds:DebugStart(
                chaosId ~= "" and chaosId or nil
            )
        end

        if not ok then
            OSC_Logger.Error(text .. " failed for player " .. tostring(playerID)
                .. ": " .. tostring(err))
        else
            OSC_Logger.Log(text .. " executed by player " .. tostring(playerID))
        end
        return
    end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    if not hero or hero:IsNull() then
        OSC_Logger.Error(text .. " ignored: player has no hero")
        return
    end

    if isHeroState then
        for _, line in ipairs(OSC_HeroState.Describe(hero)) do
            OSC_Logger.Log(line)
        end
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

    if not OSC_HeroState.Get(hero).initialized then
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
