-- «Якорь» (флаг ANCHOR_ENABLED): общий сервис для предметов item_osc_anchor*
-- и ротации. Пока якорь стоит, герой не получает выбор из трёх, а ротации
-- его способность не меняют; каждая пропущенная ротация снимает одну из
-- anchor_rotations, на последней якорь снимается.
--
-- Уровни как у Healing Lotus: ANCHOR_MERGE_COUNT зарядов одного уровня в
-- инвентаре и рюкзаке сливаются в заряд следующего (LEVELS).
--
-- Net table osc_state/anchor_<playerID> = { active = 0 | 1, rotations } —
-- значок у таймера ротации в HUD. Постановка якоря рассылается событием
-- hero_anchored (OSC_GameEvents): ротация по нему закрывает уже выданный выбор.

require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/hero_state")
require("osc/core/game_events")

OSC_Anchor = OSC_Anchor or {}

-- Уровень N пропускает N ротаций (AbilityValues rotations в KV)
local LEVELS = { "item_osc_anchor", "item_osc_anchor_2", "item_osc_anchor_3" }
OSC_Anchor.LEVELS = LEVELS
local BACKPACK_LAST_SLOT = 8 -- 0-5 инвентарь, 6-8 рюкзак; тайник не сливаем

function OSC_Anchor.IsEnabled()
    return OSC_Config.Get("ANCHOR_ENABLED") == true
end

function OSC_Anchor.IsActive(hero)
    local state = OSC_HeroState.Peek(hero)
    return state ~= nil and (state.anchor_rotations or 0) > 0
end

function OSC_Anchor.Publish(hero)
    local state = OSC_HeroState.Peek(hero)
    local rotations = state and state.anchor_rotations or 0
    CustomNetTables:SetTableValue("osc_state", "anchor_" .. hero:GetPlayerOwnerID(), {
        active = rotations > 0 and 1 or 0,
        rotations = rotations,
    })
end

-- Ставит якорь основному герою на rotations ротаций. Возвращает true или
-- false и ключ локализации причины отказа (заряд в этом случае не тратится).
function OSC_Anchor.Activate(hero, rotations)
    if not OSC_Anchor.IsEnabled() then
        return false, "osc_anchor_err_disabled"
    end
    if not OSC_Heroes.IsMainHero(hero) then
        return false, "osc_anchor_err_main_hero"
    end

    local state = OSC_HeroState.Get(hero)
    if state.anchor_rotations > 0 then
        return false, "osc_anchor_err_active"
    end

    state.anchor_rotations = math.max(1, rotations or 1)
    OSC_Anchor.Publish(hero)
    OSC_Logger.Log("Anchor set for " .. hero:GetUnitName() .. ": " .. state.anchor_rotations .. " rotation(s)")
    OSC_GameEvents.Emit("hero_anchored", hero)
    return true
end

-- Вызывает ротация: если якорь стоял — снимает с него одну ротацию и
-- возвращает true (эту ротацию герой пропускает)
function OSC_Anchor.Consume(hero)
    if not OSC_Anchor.IsActive(hero) then
        return false
    end
    local state = OSC_HeroState.Get(hero)
    state.anchor_rotations = state.anchor_rotations - 1
    OSC_Anchor.Publish(hero)
    return true
end

-- ================= Слияние уровней =================

local function FindSlot(unit, item)
    for slot = 0, BACKPACK_LAST_SLOT do
        if unit:GetItemInSlot(slot) == item then
            return slot
        end
    end
end

local function FindItems(unit, name)
    local items, charges = {}, 0
    for slot = 0, BACKPACK_LAST_SLOT do
        local item = unit:GetItemInSlot(slot)
        if item and item:GetAbilityName() == name then
            table.insert(items, item)
            charges = charges + item:GetCurrentCharges()
        end
    end
    return items, charges
end

function OSC_Anchor.Merge(unit)
    local need = OSC_Config.Get("ANCHOR_MERGE_COUNT") or 2
    for level = 1, #LEVELS - 1 do
        local items, charges = FindItems(unit, LEVELS[level])
        local merged = math.floor(charges / need)
        if merged > 0 then
            local first = items[1]
            local firstSlot = FindSlot(unit, first)
            local owner = first:GetPurchaser() or unit
            -- Остаток остаётся в первом предмете уровня, остальные убираем
            local left = charges - merged * need
            for i = #items, 1, -1 do
                if i == 1 and left > 0 then
                    first:SetCurrentCharges(left)
                else
                    unit:RemoveItem(items[i])
                end
            end

            local upper = FindItems(unit, LEVELS[level + 1])[1]
            if upper then
                upper:SetCurrentCharges(upper:GetCurrentCharges() + merged)
            else
                upper = CreateItem(LEVELS[level + 1], owner, owner)
                upper:SetCurrentCharges(merged)
                unit:AddItem(upper)
                -- Новый уровень встаёт на место слитого
                local slot = FindSlot(unit, upper)
                if slot and left == 0 and slot ~= firstSlot then
                    unit:SwapItems(slot, firstSlot)
                end
            end
            OSC_Logger.Log("Anchor merged on " .. unit:GetUnitName() .. ": "
                .. merged .. " x " .. LEVELS[level + 1])
        end
    end
end

local IS_ANCHOR = {}
for _, name in ipairs(LEVELS) do
    IS_ANCHOR[name] = true
end

-- Слияние — на следующем кадре, когда предмет уже лёг в инвентарь (и движок
-- сложил одинаковые в стак). Ловит покупку, доставку курьером и подбор.
function OSC_Anchor.Init()
    GameRules:GetGameModeEntity():SetItemAddedToInventoryFilter(function(_, event)
        local item = event.item_entindex_const and EntIndexToHScript(event.item_entindex_const)
        local unit = event.inventory_parent_entindex_const
            and EntIndexToHScript(event.inventory_parent_entindex_const)
        if item and unit and IS_ANCHOR[item:GetAbilityName()] then
            unit:SetContextThink("osc_anchor_merge", function()
                if not unit:IsNull() then
                    OSC_Anchor.Merge(unit)
                end
            end, 0)
        end
        return true
    end, OSC_Anchor)
end
