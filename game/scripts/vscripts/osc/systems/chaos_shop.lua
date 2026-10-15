-- Хаос-лавка (флаг CHAOS_SHOP_ENABLED): предметы режима из CHAOS_SHOP_ITEMS
-- продаются в своей панели HUD (osc_chaos_shop.ts). В стандартном магазине
-- их нет (ItemPurchasable "0"), цена — ItemCost из npc_items_custom.txt.
--
-- Клиент шлёт osc_shop_buy { item }. Предмет кладётся в инвентарь, если герой
-- жив и стоит у базового магазина, иначе — в тайник, оттуда его доставит
-- курьер. Ответ: osc_shop_result { ok = 1, item } или { ok = 0, item, error }
-- вместе с красной строкой osc_hud_error с тем же ключом.
--
-- Net table osc_state/shop_<team> = { items = { [i] = { name, cost, stock, max } } },
-- stock = max = -1 — без лимита; выключенных товаров в списке нет.

require("osc/core/runtime_config")
require("osc/core/client_commands")
require("osc/core/notifications")
require("osc/core/anchor")
require("osc/core/gold")

-- sold[team][item] — сколько продано команде; переживает script_reload
OSC_ChaosShop = OSC_ChaosShop or { sold = {} }

local BACKPACK_LAST_SLOT = 8 -- 0-5 инвентарь, 6-8 рюкзак

local function GetItems()
    return OSC_Config.Get("CHAOS_SHOP_ITEMS")
end

local function FindEntry(name)
    for _, entry in ipairs(GetItems()) do
        if entry.name == name then
            return entry
        end
    end
end

-- «Якорь» любого уровня выключается своим флагом ANCHOR_ENABLED
local function IsItemEnabled(name)
    return name:find("^item_osc_anchor") == nil or OSC_Anchor.IsEnabled()
end

-- Остаток товара у команды; -1 — без лимита
local function GetStock(team, entry)
    if entry.team_stock == nil then
        return -1
    end
    local sold = OSC_ChaosShop.sold[team] and OSC_ChaosShop.sold[team][entry.name] or 0
    return math.max(0, entry.team_stock - sold)
end

function OSC_ChaosShop.Publish(team)
    local items = {}
    for _, entry in ipairs(GetItems()) do
        if IsItemEnabled(entry.name) then
            table.insert(items, {
                name = entry.name,
                cost = GetItemCost(entry.name),
                stock = GetStock(team, entry),
                max = entry.team_stock or -1,
            })
        end
    end
    CustomNetTables:SetTableValue("osc_state", "shop_" .. team, { items = items })
end

function OSC_ChaosShop.Init()
    -- Лавка выключена: обработчика нет, событие покупки игнорируется
    if OSC_Config.Get("CHAOS_SHOP_ENABLED") ~= true then
        return
    end
    OSC_ChaosShop.sold = OSC_ChaosShop.sold or {}
    OSC_ChaosShop.Publish(DOTA_TEAM_GOODGUYS)
    OSC_ChaosShop.Publish(DOTA_TEAM_BADGUYS)
    CustomGameEventManager:RegisterListener("osc_shop_buy", OSC_ChaosShop.OnBuy)
end

-- ================= Выдача предмета =================

local function FindFreeSlot(hero, first, last)
    for slot = first, last do
        if not hero:GetItemInSlot(slot) then
            return slot
        end
    end
end

local function FindItemSlot(hero, item)
    for slot = 0, DOTA_STASH_SLOT_6 do
        if hero:GetItemInSlot(slot) == item then
            return slot
        end
    end
end

local function CountCharges(hero, name)
    local charges = 0
    for slot = 0, DOTA_STASH_SLOT_6 do
        local item = hero:GetItemInSlot(slot)
        if item and item:GetAbilityName() == name then
            charges = charges + item:GetCurrentCharges()
        end
    end
    return charges
end

-- Куда положить покупку: "inventory" — герой жив, у базового магазина и в
-- инвентаре или рюкзаке есть место; иначе номер свободного слота тайника;
-- nil — некуда
local function PickDestination(hero)
    if hero:IsAlive() and hero:IsInRangeOfShop(DOTA_SHOP_HOME, true)
        and FindFreeSlot(hero, 0, BACKPACK_LAST_SLOT) then
        return "inventory"
    end
    return FindFreeSlot(hero, DOTA_STASH_SLOT_1, DOTA_STASH_SLOT_6)
end

-- Выдаёт предмет: stashSlot = nil — в инвентарь, иначе в этот слот тайника.
-- AddItem кладёт в первый свободный слот инвентаря или рюкзака, в тайник
-- переносим сами через SwapItems. false — выдать не удалось.
local function GiveItem(hero, name, stashSlot)
    local item = CreateItem(name, hero, hero)
    if not item then
        return false
    end
    -- Инвентарь и рюкзак полны: предмет из последнего слота рюкзака на время
    -- уходит в тайник, а после выдачи возвращается на место
    local freed = stashSlot ~= nil and FindFreeSlot(hero, 0, BACKPACK_LAST_SLOT) == nil
    if freed then
        hero:SwapItems(BACKPACK_LAST_SLOT, stashSlot)
    end
    local chargesBefore = CountCharges(hero, name)
    hero:AddItem(item)
    local slot = IsValidEntity(item) and FindItemSlot(hero, item) or nil
    if slot == nil then
        if freed then
            hero:SwapItems(BACKPACK_LAST_SLOT, stashSlot)
        end
        -- Стакающийся предмет («Якорь») влился зарядом в уже лежащий
        if CountCharges(hero, name) > chargesBefore then
            return true
        end
        if IsValidEntity(item) then
            UTIL_Remove(item)
        end
        return false
    end
    if stashSlot ~= nil and slot ~= stashSlot then
        hero:SwapItems(slot, stashSlot)
    end
    return true
end

-- ================= Покупка =================

function OSC_ChaosShop.OnBuy(sourceIndex, event)
    local names = {}
    for _, entry in ipairs(GetItems()) do
        table.insert(names, entry.name)
    end
    local ok, cmd, refusal = OSC_ClientCommands.Check(sourceIndex, event, {
        hero = true,
        args = { { name = "item", check = OSC_ClientCommands.OneOf(names) } },
    })
    if not ok then
        OSC_ClientCommands.LogRefusal("Chaos shop purchase",
            cmd.player_id or (event and event.PlayerID), refusal)
        return
    end

    local player, playerID, hero = cmd.player, cmd.player_id, cmd.hero
    local name = cmd.args.item
    local entry = FindEntry(name)
    local team = hero:GetTeamNumber()

    -- Отказ: золото не тронуто (или уже возвращено)
    local function Refuse(reason)
        OSC_Notifications.PlayerEvent(player, "osc_hud_error", { message = reason })
        OSC_Notifications.PlayerEvent(player, "osc_shop_result", {
            ok = 0, item = name, error = reason,
        })
    end

    if OSC_Config.Get("CHAOS_SHOP_ENABLED") ~= true or not IsItemEnabled(name) then
        Refuse("osc_shop_err_disabled")
        return
    end
    local cost = GetItemCost(name)
    -- Без цены из KV бесплатно не отдаём
    if type(cost) ~= "number" or cost <= 0 then
        OSC_Logger.Error("Chaos shop: no ItemCost for " .. name)
        Refuse("osc_shop_err_disabled")
        return
    end
    if GetStock(team, entry) == 0 then
        Refuse("osc_shop_err_no_stock")
        return
    end
    if PlayerResource:GetGold(playerID) < cost then
        Refuse("osc_shop_err_no_gold")
        return
    end
    local destination = PickDestination(hero)
    if destination == nil then
        Refuse("osc_shop_err_no_space")
        return
    end

    local spent, reliableSpent = OSC_Gold.Spend(playerID, cost, DOTA_ModifyGold_PurchaseItem)
    if spent ~= cost then
        if spent > 0 then
            OSC_Gold.Refund(playerID, spent, reliableSpent)
        end
        OSC_Logger.Error("Chaos shop: " .. name .. " was not charged: expected "
            .. cost .. ", got " .. spent)
        Refuse("osc_shop_err_no_gold")
        return
    end

    if not GiveItem(hero, name, destination ~= "inventory" and destination or nil) then
        OSC_Gold.Refund(playerID, spent, reliableSpent)
        OSC_Logger.Error("Chaos shop: failed to give " .. name .. " to player " .. playerID)
        Refuse("osc_shop_err_no_space")
        return
    end

    if entry.team_stock ~= nil then
        OSC_ChaosShop.sold[team] = OSC_ChaosShop.sold[team] or {}
        OSC_ChaosShop.sold[team][name] = (OSC_ChaosShop.sold[team][name] or 0) + 1
    end
    OSC_ChaosShop.Publish(team)
    OSC_Logger.Log("Chaos shop: player " .. playerID .. " bought " .. name
        .. (destination == "inventory" and "" or " (stash)"))
    OSC_Notifications.PlayerEvent(player, "osc_shop_result", { ok = 1, item = name })
end
