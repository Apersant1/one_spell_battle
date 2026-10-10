modifier_osc_courier_drunk = class({})

local function GetConfiguredSlowPct()
    for _, ability in ipairs(OSC_COURIER_ABILITY_POOL) do
        if ability.modifier == "modifier_osc_courier_drunk" then
            return ability.slow_pct
        end
    end
    return 0
end

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
    if not IsServer() then return end
    self.slowPct = tonumber(kv.slow_pct) or GetConfiguredSlowPct()
    self.baseMoveSpeed = tonumber(kv.base_move_speed)
    self:SetHasCustomTransmitterData(true)
end

function modifier_osc_courier_drunk:OnRefresh(kv)
    if not IsServer() then return end
    self.slowPct = tonumber(kv.slow_pct) or self.slowPct or GetConfiguredSlowPct()
    self.baseMoveSpeed = tonumber(kv.base_move_speed) or self.baseMoveSpeed
    self:SendBuffRefreshToClients()
end

-- Сервер → клиент. nil в таблице не передаётся, поэтому -1 = «нет значения».
function modifier_osc_courier_drunk:AddCustomTransmitterData()
    return {
        slow_pct = self.slowPct or GetConfiguredSlowPct(),
        base_move_speed = self.baseMoveSpeed or -1,
    }
end

function modifier_osc_courier_drunk:HandleCustomTransmitterData(data)
    self.slowPct = data.slow_pct
    self.baseMoveSpeed = data.base_move_speed >= 0 and data.base_move_speed or nil
end

function modifier_osc_courier_drunk:DeclareFunctions()
    return {
        MODIFIER_PROPERTY_MOVESPEED_BASE_OVERRIDE,
        MODIFIER_PROPERTY_TOOLTIP,
    }
end

function modifier_osc_courier_drunk:GetModifierMoveSpeedOverride()
    if not self.baseMoveSpeed then return nil end
    return self.baseMoveSpeed * (1 - (self.slowPct or GetConfiguredSlowPct()) / 100)
end

function modifier_osc_courier_drunk:OnTooltip()
    return self.slowPct or GetConfiguredSlowPct()
end