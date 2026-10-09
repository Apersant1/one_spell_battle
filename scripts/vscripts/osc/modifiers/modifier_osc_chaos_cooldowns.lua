modifier_osc_chaos_cooldowns = class({})

function modifier_osc_chaos_cooldowns:IsHidden()
    return false
end

function modifier_osc_chaos_cooldowns:IsDebuff()
    return false
end

function modifier_osc_chaos_cooldowns:IsPurgable()
    return false
end

function modifier_osc_chaos_cooldowns:RemoveOnDeath()
    return false
end

function modifier_osc_chaos_cooldowns:GetTexture()
    return "item_octarine_core"
end

function modifier_osc_chaos_cooldowns:OnCreated()
    self.cooldownReductionPct = OSC_CONFIG.CHAOS_ROUNDS.COOLDOWN_REDUCTION_PCT
end

function modifier_osc_chaos_cooldowns:DeclareFunctions()
    return { MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE }
end

function modifier_osc_chaos_cooldowns:GetModifierPercentageCooldown()
    return self.cooldownReductionPct or OSC_CONFIG.CHAOS_ROUNDS.COOLDOWN_REDUCTION_PCT
end
