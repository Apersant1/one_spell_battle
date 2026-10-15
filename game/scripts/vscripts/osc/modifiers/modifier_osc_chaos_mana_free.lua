modifier_osc_chaos_mana_free = class({})

function modifier_osc_chaos_mana_free:IsHidden()       return false end
function modifier_osc_chaos_mana_free:IsPurgable()     return false end
function modifier_osc_chaos_mana_free:RemoveOnDeath()  return false end
function modifier_osc_chaos_mana_free:GetTexture()     return "item_arcane_boots" end

function modifier_osc_chaos_mana_free:OnCreated()
    if IsServer() then
        self:SetStackCount(OSC_Config.Get("CHAOS_ROUNDS.MANA_COST_REDUCTION_PCT"))
    end
end

function modifier_osc_chaos_mana_free:DeclareFunctions()
    return { MODIFIER_PROPERTY_MANACOST_PERCENTAGE_STACKING }
end

function modifier_osc_chaos_mana_free:GetModifierPercentageManacostStacking()
    return self:GetStackCount()
end
