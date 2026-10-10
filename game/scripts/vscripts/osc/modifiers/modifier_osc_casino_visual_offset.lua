modifier_osc_casino_visual_offset = class({})

function modifier_osc_casino_visual_offset:IsHidden()    return true end
function modifier_osc_casino_visual_offset:IsPurgable()  return false end

function modifier_osc_casino_visual_offset:DeclareFunctions()
    return { MODIFIER_PROPERTY_VISUAL_Z_DELTA }
end

function modifier_osc_casino_visual_offset:GetVisualZDelta()
    return 110
end