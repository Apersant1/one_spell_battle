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

-- Величину берёт сервер из OSC_Config, клиенту она приходит числом стаков
function modifier_osc_chaos_cooldowns:OnCreated()
    if IsServer() then
        self:SetStackCount(OSC_Config.Get("CHAOS_ROUNDS.COOLDOWN_REDUCTION_PCT") or 0)
    end
end

function modifier_osc_chaos_cooldowns:DeclareFunctions()
    return { MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE }
end

function modifier_osc_chaos_cooldowns:GetModifierPercentageCooldown()
    return self:GetStackCount()
end
