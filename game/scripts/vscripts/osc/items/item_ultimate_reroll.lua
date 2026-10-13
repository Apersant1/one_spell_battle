item_osc_ultimate_reroll = class({})

function item_osc_ultimate_reroll:OnSpellStart()
    local hero = self:GetCaster()
    -- Ультимейт меняется только у основного героя: копии его копируют
    if not OSC_Heroes.IsMainHero(hero) or hero:GetLevel() < 6 then
        OSC_Logger.Error("Ultimate reroll requires a main hero at level 6 or higher")
        return
    end

    local entry = OSC_Abilities.GiveRandomUltimate(hero, true)
    if entry then
        hero:RemoveItem(self)
    end
end
