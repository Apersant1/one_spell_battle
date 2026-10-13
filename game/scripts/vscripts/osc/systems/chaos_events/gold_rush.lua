require("osc/core/runtime_config")
OSC_ChaosEvents:Register({
    id = "gold_rush",
    weight = 6,
    tick_interval = function() return OSC_Config.Get("CHAOS_ROUNDS.GOLD_RUSH_TICK") end,
    description_params = function()
        return {
            amount = OSC_Config.Get("CHAOS_ROUNDS.GOLD_RUSH_AMOUNT"),
            tick = OSC_Config.Get("CHAOS_ROUNDS.GOLD_RUSH_TICK"),
        }
    end,

    OnInterval = function(_, ctx)
        if ctx.remaining <= 0 then
            return
        end

        local amount = OSC_Config.Get("CHAOS_ROUNDS.GOLD_RUSH_AMOUNT")
        for playerID = 0, DOTA_MAX_PLAYERS - 1 do
            if PlayerResource:IsValidPlayerID(playerID)
                and PlayerResource:GetPlayer(playerID) then
                PlayerResource:ModifyGold(
                    playerID,
                    amount,
                    false,
                    DOTA_ModifyGold_Unspecified
                )
            end
        end
    end,
})