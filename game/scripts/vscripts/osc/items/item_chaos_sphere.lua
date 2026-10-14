require("osc/systems/chaos_sphere")

item_osc_chaos_sphere = class({})

-- Сама ничего не выдаёт: открывает выбор (OSC_ChaosSphere.Offer). Предмет
-- расходуется, когда игрок выбрал режим; отказ и отмена его не тратят
function item_osc_chaos_sphere:OnSpellStart()
    OSC_ChaosSphere.Offer(self:GetCaster(), self)
end
