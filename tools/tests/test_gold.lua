-- Списание и возврат золота (osc/core/gold.lua): сверка фактически
-- списанного и возврат сначала надёжного золота

-- Игрок 0 с золотом: reliable — надёжное, unreliable — обычное.
-- SpendGold, как в Dota, сначала тратит обычное
local function setup(reliable, unreliable)
    require("osc/core/gold")
    local wallet = { reliable = reliable, unreliable = unreliable, calls = {} }
    PlayerResource.GetGold = function() return wallet.reliable + wallet.unreliable end
    PlayerResource.GetReliableGold = function() return wallet.reliable end
    PlayerResource.SpendGold = function(_, _, amount)
        local fromUnreliable = math.min(amount, wallet.unreliable)
        wallet.unreliable = wallet.unreliable - fromUnreliable
        wallet.reliable = math.max(0, wallet.reliable - (amount - fromUnreliable))
    end
    PlayerResource.ModifyGold = function(_, _, amount, reliable)
        table.insert(wallet.calls, { amount = amount, reliable = reliable })
        if reliable then
            wallet.reliable = wallet.reliable + amount
        else
            wallet.unreliable = wallet.unreliable + amount
        end
    end
    return wallet
end

return {
    spend_reports_reliable_part = function()
        setup(300, 100)
        local spent, reliableSpent = OSC_Gold.Spend(0, 250)
        H.eq(spent, 250, "spent all")
        H.eq(reliableSpent, 150, "reliable part after unreliable ran out")
    end,

    spend_reports_partial_charge = function()
        setup(0, 100)
        local spent = OSC_Gold.Spend(0, 250)
        H.eq(spent, 100, "only what the player had")
    end,

    refund_returns_reliable_first = function()
        local wallet = setup(300, 100)
        local spent, reliableSpent = OSC_Gold.Spend(0, 250)
        OSC_Gold.Refund(0, spent, reliableSpent)
        H.eq(wallet.reliable, 300, "reliable restored")
        H.eq(wallet.unreliable, 100, "unreliable restored")
        H.eq(#wallet.calls, 2, "reliable and unreliable parts")
        H.eq(wallet.calls[1].reliable, true, "reliable goes first")
    end,

    refund_above_reliable_is_unreliable = function()
        local wallet = setup(0, 0)
        OSC_Gold.Refund(0, 500, 100)
        H.eq(wallet.reliable, 100, "up to what was reliable")
        H.eq(wallet.unreliable, 400, "the rest (winnings) is unreliable")
    end,
}
