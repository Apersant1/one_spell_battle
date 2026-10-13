-- «Якорь» (флаг ANCHOR_ENABLED): общий сервис для предмета item_osc_anchor и
-- ротации. Пока якорь стоит, герой не получает выбор из трёх, а ближайшая
-- ротация его способность не меняет и снимает якорь — ровно одна ротация.
--
-- Net table osc_state/anchor_<playerID> = { active = 0 | 1 } — значок у
-- таймера ротации в HUD. Постановка якоря рассылается событием
-- hero_anchored (OSC_GameEvents): ротация по нему закрывает уже выданный выбор.

require("osc/core/heroes")
require("osc/core/hero_state")
require("osc/core/game_events")

OSC_Anchor = OSC_Anchor or {}

function OSC_Anchor.IsEnabled()
    return OSC_CONFIG.ANCHOR_ENABLED == true
end

function OSC_Anchor.IsActive(hero)
    local state = OSC_HeroState.Peek(hero)
    return state ~= nil and state.anchored == true
end

function OSC_Anchor.Publish(hero)
    CustomNetTables:SetTableValue("osc_state", "anchor_" .. hero:GetPlayerOwnerID(), {
        active = OSC_Anchor.IsActive(hero) and 1 or 0,
    })
end

-- Ставит якорь основному герою. Возвращает true или false и ключ
-- локализации причины отказа (заряд в этом случае не тратится).
function OSC_Anchor.Activate(hero)
    if not OSC_Anchor.IsEnabled() then
        return false, "osc_anchor_err_disabled"
    end
    if not OSC_Heroes.IsMainHero(hero) then
        return false, "osc_anchor_err_main_hero"
    end

    local state = OSC_HeroState.Get(hero)
    if state.anchored then
        return false, "osc_anchor_err_active"
    end

    state.anchored = true
    OSC_Anchor.Publish(hero)
    OSC_Logger.Log("Anchor set for " .. hero:GetUnitName())
    OSC_GameEvents.Emit("hero_anchored", hero)
    return true
end

-- Вызывает ротация: если якорь стоял — снимает его и возвращает true
-- (эту ротацию герой пропускает)
function OSC_Anchor.Consume(hero)
    if not OSC_Anchor.IsActive(hero) then
        return false
    end
    OSC_HeroState.Get(hero).anchored = false
    OSC_Anchor.Publish(hero)
    return true
end
