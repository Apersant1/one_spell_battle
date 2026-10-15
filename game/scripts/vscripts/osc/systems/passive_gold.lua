-- Пассивное золото. Начисление движка (GameRules:SetGoldPerTick /
-- SetGoldTickTime) в этом режиме не работает — золото не капает, — поэтому
-- начисляем сами: после горна раз в PASSIVE_GOLD_TICK_TIME секунд каждому
-- игроку с героем PASSIVE_GOLD_PER_TICK обычного золота. На POST_GAME
-- начисление останавливается.

require("osc/core/runtime_config")
require("osc/core/game_events")
require("osc/core/util")

OSC_PassiveGold = OSC_PassiveGold or {}

-- Шаг таймера; возвращает задержку до следующего или nil (конец игры)
function OSC_PassiveGold.Tick()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
        return nil
    end
    local amount = OSC_Config.Get("PASSIVE_GOLD_PER_TICK")
    if amount > 0 then
        OSC_Util.ForEachPlayerID(function(playerID)
            if PlayerResource:GetSelectedHeroEntity(playerID) then
                PlayerResource:ModifyGold(playerID, amount, false, DOTA_ModifyGold_GameTick)
            end
        end)
    end
    return OSC_Config.Get("PASSIVE_GOLD_TICK_TIME")
end

function OSC_PassiveGold.Init()
    -- Начисление движка выключено явно: если оно когда-нибудь заработает,
    -- золото не придёт дважды
    GameRules:SetGoldPerTick(0)
    OSC_GameEvents.Subscribe("game_started", "passive_gold", function()
        GameRules:GetGameModeEntity():SetContextThink(
            "osc_passive_gold", OSC_PassiveGold.Tick, OSC_Config.Get("PASSIVE_GOLD_TICK_TIME"))
    end)
end
