require("osc/core/anchor")

item_osc_anchor = class({})
-- Уровни отличаются только rotations в KV
item_osc_anchor_2 = item_osc_anchor
item_osc_anchor_3 = item_osc_anchor

-- Тратит один заряд стака: при успехе заряд расходуется, при отказе (якорь
-- уже стоит, не основной герой, механика выключена) остаётся у игрока
function item_osc_anchor:OnSpellStart()
    local hero = self:GetCaster()
    local ok, reason = OSC_Anchor.Activate(hero, self:GetSpecialValueFor("rotations"))
    if ok then
        local charges = self:GetCurrentCharges()
        if charges > 1 then
            self:SetCurrentCharges(charges - 1)
        else
            hero:RemoveItem(self)
        end
        return
    end

    OSC_Logger.Log("Anchor refused: " .. tostring(reason))
    local player = hero and PlayerResource:GetPlayer(hero:GetPlayerOwnerID())
    if player then
        OSC_Notifications.PlayerEvent(player, "osc_hud_error", { message = reason })
    end
end
