-- Списание и возврат золота игрока (казино, Хаос-лавка).
-- SpendGold сам решает, сколько взять надёжного золота и сколько обычного,
-- и может списать не всё. Поэтому Spend сверяет фактически списанное:
-- неполное списание вызывающий возвращает через Refund и отказывает.

OSC_Gold = OSC_Gold or {}

-- Списывает amount; возвращает, сколько списано всего и сколько из этого
-- надёжного золота (нужно Refund, чтобы вернуть так же)
function OSC_Gold.Spend(playerID, amount, reason)
    local goldBefore = PlayerResource:GetGold(playerID)
    local reliableBefore = PlayerResource:GetReliableGold(playerID)
    PlayerResource:SpendGold(playerID, amount, reason or DOTA_ModifyGold_Unspecified)
    local spent = goldBefore - PlayerResource:GetGold(playerID)
    local reliableSpent = math.max(0, reliableBefore - PlayerResource:GetReliableGold(playerID))
    return spent, reliableSpent
end

-- Возвращает amount так же, как списали: сначала надёжное золото (не больше
-- reliableSpent), остальное — обычным
function OSC_Gold.Refund(playerID, amount, reliableSpent)
    local reliablePart = math.min(amount, reliableSpent or 0)
    if reliablePart > 0 then
        PlayerResource:ModifyGold(playerID, reliablePart, true, DOTA_ModifyGold_Unspecified)
    end
    if amount > reliablePart then
        PlayerResource:ModifyGold(playerID, amount - reliablePart, false, DOTA_ModifyGold_Unspecified)
    end
end
