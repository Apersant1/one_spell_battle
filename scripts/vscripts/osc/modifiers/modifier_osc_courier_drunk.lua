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
    self.baseMoveSpeed = kv and tonumber(kv.base_move_speed)
end

function modifier_osc_courier_drunk:OnRefresh(kv)
    self.slowPct = (kv and tonumber(kv.slow_pct)) or self.slowPct or 30
    self.baseMoveSpeed = (kv and tonumber(kv.base_move_speed)) or self.baseMoveSpeed
end

function modifier_osc_courier_drunk:DeclareFunctions()
    return { MODIFIER_PROPERTY_MOVESPEED_BASE_OVERRIDE }
end

function modifier_osc_courier_drunk:GetModifierMoveSpeedOverride()
    local baseMoveSpeed = self.baseMoveSpeed
    if not baseMoveSpeed then return nil end
    return baseMoveSpeed * (1 - (self.slowPct or 30) / 100)
end
