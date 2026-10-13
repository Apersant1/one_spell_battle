require("osc/core/anchor")

item_osc_anchor = class({})

-- Один заряд: при успехе предмет расходуется, при отказе (якорь уже стоит,
-- не основной герой, механика выключена) остаётся у игрока
function item_osc_anchor:OnSpellStart()
    local hero = self:GetCaster()
    local ok, reason = OSC_Anchor.Activate(hero)
    if ok then
        hero:RemoveItem(self)
        return
    end

    OSC_Logger.Log("Anchor refused: " .. tostring(reason))
    local player = hero and PlayerResource:GetPlayer(hero:GetPlayerOwnerID())
    if player then
        OSC_Notifications.PlayerEvent(player, "osc_hud_error", { message = reason })
    end
end
