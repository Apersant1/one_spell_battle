item_osc_ultimate_reroll = class({})

function item_osc_ultimate_reroll:OnSpellStart()
    local hero = self:GetCaster()
    if not hero or not hero:IsRealHero() or hero:GetLevel() < 6 then
        print("[OSC] Ultimate reroll requires a real hero at level 6 or higher")
        return
    end

    local entry = OSC_Abilities.GiveRandomUltimate(hero, true)
    if entry then
        hero:RemoveItem(self)
    end
end
