modifier_osc_courier_drunk = class({})

function modifier_osc_courier_drunk:IsHidden()
    return false
end

function modifier_osc_courier_drunk:IsDebuff()
    return true
end

function modifier_osc_courier_drunk:IsPurgable()
    return false
end

function modifier_osc_courier_drunk:GetTexture()
    return "ogre_magi_bloodlust"
end

function modifier_osc_courier_drunk:OnCreated(kv)
    self.slowPct = kv and tonumber(kv.slow_pct) or 30
    self.baseMoveSpeed = self:GetParent():GetBaseMoveSpeed()
end

function modifier_osc_courier_drunk:OnRefresh(kv)
    self.slowPct = (kv and tonumber(kv.slow_pct)) or self.slowPct or 30
    if not self.baseMoveSpeed then
        self.baseMoveSpeed = self:GetParent():GetBaseMoveSpeed()
    end
end

function modifier_osc_courier_drunk:DeclareFunctions()
    return { MODIFIER_PROPERTY_MOVESPEED_BASE_OVERRIDE }
end

function modifier_osc_courier_drunk:GetModifierMoveSpeedOverride()
    return self.baseMoveSpeed * (1 - (self.slowPct or 30) / 100)
end
