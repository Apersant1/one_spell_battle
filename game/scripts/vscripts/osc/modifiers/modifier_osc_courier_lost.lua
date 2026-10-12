-- «Заблудший курьер»: пока висит модификатор, курьер отдаёт предметы
-- не тому союзнику. Сама подмена получателя — в osc/systems/couriers.lua.
modifier_osc_courier_lost = class({})

function modifier_osc_courier_lost:IsHidden()    return false end
function modifier_osc_courier_lost:IsDebuff()    return true end
function modifier_osc_courier_lost:IsPurgable()  return false end
function modifier_osc_courier_lost:GetTexture()  return "item_tpscroll" end