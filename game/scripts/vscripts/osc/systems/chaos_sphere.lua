-- Сфера хаоса (флаг CHAOS_SPHERE_ENABLED): предмет item_osc_chaos_sphere
-- падает с Рошана. Владелец применяет её (item_chaos_sphere.lua -> Offer) и
-- в окне HUD (osc_chaos_sphere.ts) выбирает одно из двух:
--   ultimate — легендарный ультимейт из CHAOS_SPHERE_ULTIMATE_CHOICES
--     вариантов, с CHAOS_SPHERE_MIN_LEVEL уровня (проверяется при выборе);
--   enemies — новая случайная способность каждому основному герою врагов,
--     кроме тех, у кого стоит «Якорь» (якорь при этом не тратится).
-- Предмет расходуется только после успешного выбора; cancel закрывает окно.
--
-- Протокол:
--   сервер -> игрок  osc_sphere_offer { options = { [i] = { name, label, rarity } },
--                                       ultimate_allowed = 1 | 0, min_level }
--   игрок -> сервер  osc_sphere_pick  { mode = "ultimate" | "enemies" | "cancel", ability }
--   отказы — лог и osc_hud_error { message = "osc_sphere_err_*" }
-- Предложение — в состоянии героя: sphere_offer = { item = entindex,
--   options = { имена }, ultimate_allowed }.

require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/hero_state")
require("osc/core/client_commands")
require("osc/core/notifications")
require("osc/core/anchor")
require("osc/systems/ability_selection")
require("osc/systems/abilities")

-- listening — обработчик entity_killed уже стоит (переживает script_reload)
OSC_ChaosSphere = OSC_ChaosSphere or { listening = false }

local ITEM_NAME = "item_osc_chaos_sphere"
local ROSHAN = "npc_dota_roshan"
local BACKPACK_LAST_SLOT = 8 -- 0-5 инвентарь, 6-8 рюкзак

function OSC_ChaosSphere.IsEnabled()
    return OSC_Config.Get("CHAOS_SPHERE_ENABLED") == true
end

local function OwnerPlayer(hero)
    return PlayerResource:GetPlayer(hero:GetPlayerOwnerID())
end

local function HudError(player, reason)
    if player then
        OSC_Notifications.PlayerEvent(player, "osc_hud_error", { message = reason })
    end
end

local function LogRefusal(senderKey, reason)
    OSC_ClientCommands.LogRefusal("Chaos sphere pick", tostring(senderKey), tostring(reason))
end

local function MinLevel()
    return OSC_Config.Get("CHAOS_SPHERE_MIN_LEVEL") or 0
end

local function Contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

-- Сфера ещё у героя: в инвентаре или рюкзаке
local function HeroHasItem(hero, item)
    for slot = 0, BACKPACK_LAST_SLOT do
        if hero:GetItemInSlot(slot) == item then
            return true
        end
    end
    return false
end

-- ================= Выпадение =================

function OSC_ChaosSphere.OnEntityKilled(event)
    if not OSC_ChaosSphere.IsEnabled() then return end
    local killed = event and event.entindex_killed and EntIndexToHScript(event.entindex_killed)
    if not IsValidEntity(killed) or not killed.GetUnitName
        or killed:GetUnitName() ~= ROSHAN then
        return
    end

    local item = CreateItem(ITEM_NAME, nil, nil)
    if not item then
        OSC_Logger.Error("Chaos sphere: failed to create " .. ITEM_NAME)
        return
    end
    -- Рядом с Аегисом, но не в той же точке
    local offset = OSC_Config.Get("CHAOS_SPHERE_DROP_OFFSET") or 0
    CreateItemOnPositionSync(killed:GetAbsOrigin() + RandomVector(offset), item)
    OSC_Logger.Log("Chaos sphere dropped by Roshan")
    OSC_Notifications.Notify("chaos_sphere_dropped")
end

-- ================= Предложение =================

-- Открывает выбор владельцу сферы. Возвращает true или false и причину
-- (предмет в этом случае не тратится).
function OSC_ChaosSphere.Offer(hero, item)
    local player = IsValidEntity(hero) and OwnerPlayer(hero) or nil
    if not OSC_ChaosSphere.IsEnabled() then
        HudError(player, "osc_sphere_err_disabled")
        return false, "disabled"
    end
    if not OSC_Heroes.IsMainHero(hero) then
        OSC_Logger.Log("Chaos sphere refused: not a main hero")
        HudError(player, "osc_sphere_err_main_hero")
        return false, "not main hero"
    end

    local count = OSC_Config.Get("CHAOS_SPHERE_ULTIMATE_CHOICES")
    if type(count) ~= "number" or count < 1 then
        error("[OSC] CHAOS_SPHERE_ULTIMATE_CHOICES must be at least 1")
    end

    -- Без кандидатов (пустой пул) окно всё равно открывается: остаётся «Хаос врагам»
    local names, options = {}, {}
    local ok, picked = pcall(OSC_AbilitySelection.PickCandidates, hero, "ultimate",
        math.floor(count), { rarity = "legendary" })
    if ok then
        for index, entry in ipairs(picked) do
            names[index] = entry.name
            options[index] = {
                name = entry.name,
                label = entry.label or entry.name,
                rarity = OSC_AbilitySelection.GetRarity(entry),
            }
        end
    else
        OSC_Logger.Error("Chaos sphere: no ultimate candidates: " .. tostring(picked))
    end

    local allowed = hero:GetLevel() >= MinLevel()
    OSC_HeroState.Get(hero).sphere_offer = {
        item = item:entindex(),
        options = names,
        ultimate_allowed = allowed,
    }
    OSC_Notifications.PlayerEvent(player, "osc_sphere_offer", {
        options = options,
        ultimate_allowed = allowed and 1 or 0,
        min_level = MinLevel(),
    })
    return true
end

-- ================= Выбор =================

local function Consume(hero, item)
    OSC_HeroState.Get(hero).sphere_offer = nil
    hero:RemoveItem(item)
end

-- Новая случайная способность каждому основному герою врагов без «Якоря»;
-- герои, ещё не получившие способности режима, пропускаются, как в ротации
local function HitEnemies(hero)
    local team = hero:GetTeamNumber()
    OSC_Heroes.ForEachPlayerHero(function(enemy, playerID)
        local state = OSC_HeroState.Get(enemy)
        if enemy:GetTeamNumber() ~= team and state.initialized and not OSC_Anchor.IsActive(enemy) then
            local ok, err = pcall(OSC_Abilities.GiveRandom, enemy, true)
            if not ok then
                OSC_Logger.Error("Chaos sphere: ability for player " .. playerID .. ": " .. tostring(err))
            end
        end
    end)
end

function OSC_ChaosSphere.OnPick(sourceIndex, event)
    local ok, cmd, reason = OSC_ClientCommands.Check(sourceIndex, event, {
        hero = true,
        args = { { name = "mode", check = OSC_ClientCommands.OneOf({ "ultimate", "enemies", "cancel" }) } },
    })
    if not ok then
        LogRefusal(cmd.player_id or (event and event.PlayerID), reason)
        return
    end

    local hero, player = cmd.hero, cmd.player
    local state = OSC_HeroState.Get(hero)
    local offer = state.sphere_offer
    if not offer then
        LogRefusal(cmd.player_id, "no offer")
        return
    end

    local mode = cmd.args.mode
    if mode == "cancel" then
        state.sphere_offer = nil
        return
    end

    local item = EntIndexToHScript(offer.item)
    if not IsValidEntity(item) or not HeroHasItem(hero, item) then
        state.sphere_offer = nil
        LogRefusal(cmd.player_id, "no item")
        HudError(player, "osc_sphere_err_no_item")
        return
    end
    if not OSC_ChaosSphere.IsEnabled() then
        HudError(player, "osc_sphere_err_disabled")
        return
    end

    if mode == "enemies" then
        HitEnemies(hero)
        Consume(hero, item)
        OSC_Notifications.Notify("chaos_sphere_enemies", { player_id = cmd.player_id })
        return
    end

    -- mode == "ultimate"
    if hero:GetLevel() < MinLevel() then
        LogRefusal(cmd.player_id, "level " .. hero:GetLevel())
        HudError(player, "osc_sphere_err_level")
        return
    end
    local ability = event and event.ability
    if type(ability) ~= "string" or not Contains(offer.options, ability) then
        LogRefusal(cmd.player_id, "not offered: " .. tostring(ability))
        return
    end
    local entry = OSC_AbilitySelection.FindEntry(ability)
    if not entry or not OSC_Abilities.Give(hero, "ultimate", entry, true) then
        LogRefusal(cmd.player_id, "give failed: " .. ability)
        return
    end
    Consume(hero, item)
end

function OSC_ChaosSphere.Init()
    CustomGameEventManager:RegisterListener("osc_sphere_pick", function(sourceIndex, event)
        OSC_ChaosSphere.OnPick(sourceIndex, event)
    end)
    if OSC_ChaosSphere.listening then return end
    OSC_ChaosSphere.listening = true
    ListenToGameEvent("entity_killed", function(event)
        OSC_ChaosSphere.OnEntityKilled(event)
    end, nil)
end
