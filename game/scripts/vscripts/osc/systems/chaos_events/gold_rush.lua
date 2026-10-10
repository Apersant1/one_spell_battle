OSC_ChaosEvents:Register({
    id = "gold_rush",
    weight = 6,
    tick_interval = OSC_CONFIG.CHAOS_ROUNDS.GOLD_RUSH_TICK,
    description_params = {
        amount = OSC_CONFIG.CHAOS_ROUNDS.GOLD_RUSH_AMOUNT,
        tick = OSC_CONFIG.CHAOS_ROUNDS.GOLD_RUSH_TICK,
    },

    OnInterval = function(_, ctx)
        if ctx.remaining <= 0 then
            return
        end

        local amount = OSC_CONFIG.CHAOS_ROUNDS.GOLD_RUSH_AMOUNT
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