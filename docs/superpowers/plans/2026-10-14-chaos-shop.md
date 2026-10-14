# Хаос-лавка (Chaos Shop) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sell `item_osc_ultimate_reroll` and `item_osc_anchor` only through a custom HUD "Хаос-лавка" (button + panel), with server-side stock, gold and placement checks.

**Architecture:** New server system `OSC_ChaosShop` (`osc/systems/chaos_shop.lua`) publishes `osc_state/shop_<team>` and handles `osc_shop_buy`; new Panorama module `OSC.ChaosShop` (`osc_chaos_shop.js`) renders the panel from that net table and sends purchases. Items get `ItemPurchasable "0"` so the standard shop no longer sells them.

**Tech Stack:** Dota 2 VScript Lua (LuaJIT), Panorama JS/XML/CSS, KV, offline tests on lupa (`tools/tests/run_tests.py`).

**Spec:** `docs/superpowers/specs/2026-10-14-chaos-shop-design.md` (approved). Implementers read both files.

## Execution model

Three implementers work **in parallel**, each in its own git worktree branched from the current HEAD of `stage-3-chaos-shop` (commit `81ee686`). File ownership is disjoint: an implementer never edits a file owned by another workstream. The merger (the user) merges the three branches afterwards (section "Merge & verify").

Worktree setup (run once by the user from the repo root, Git Bash):

```bash
git worktree add ../one_spell-shop-a -b stage-3-chaos-shop-a stage-3-chaos-shop
git worktree add ../one_spell-shop-b -b stage-3-chaos-shop-b stage-3-chaos-shop
git worktree add ../one_spell-shop-c -b stage-3-chaos-shop-c stage-3-chaos-shop
```

All commands below run from the root of the implementer's own worktree.

**Encoding rule:** files contain Cyrillic. Edit them only with the Write/Edit tools, never through bash heredocs, `echo`, `sed -i` or python stdin. Keep the file's existing line endings and indentation (tabs in `addon_*.txt` and `npc_items_custom.txt`, 4 spaces in Lua, 2 spaces in JS/CSS).

## Global Constraints

- Every number lives in the config; the mechanic is switched off by `CHAOS_SHOP_ENABLED` (game/todo.md, «Правила»).
- New texts only in `game/resource/addon_russian.txt` and `addon_english.txt`; HUD text via `$.Localize`.
- Logging only via `OSC_Logger` (`osc/core/logger.lua`); events to a player only via `OSC_Notifications.PlayerEvent` (`osc/core/notifications.lua`).
- Config is read only via `OSC_Config.Get` (checked by `run_tests.py` "Config reads"); read values at the moment of use, not at file load.
- Systems do not call neighbouring systems directly; core services (`OSC_ClientCommands`, `OSC_Notifications`, `OSC_Anchor`, `OSC_Heroes`) are allowed.
- Module tables survive `script_reload`: `OSC_ChaosShop = OSC_ChaosShop or { ... }`.
- Panorama panels created from JS only via `$.CreatePanel` (JS-created panels have no `BCreateChildren`).
- Code comments in Russian, in the style of surrounding code. Commit messages in English, conventional style, ending with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before each commit: `python tools/tests/run_tests.py` → `RESULT: OK` in your own worktree (no expected-red checks in this split, see below).

---

## Shared contract

Every name below is fixed. Do not rename, add or drop anything that crosses a workstream boundary.

### Lua module

| What | Value |
| --- | --- |
| File | `game/scripts/vscripts/osc/systems/chaos_shop.lua` |
| Global | `OSC_ChaosShop` (fields: `sold`, `Init`, `Publish(team)`, `OnBuy(sourceIndex, event)`) |
| Require | `require("osc/systems/chaos_shop")` in `addon_game_mode.lua`, right after `require("osc/systems/casino")` |
| Init | `SafeInit("ChaosShop", OSC_ChaosShop)` in `osc/core/game_mode.lua`, right after `SafeInit("Casino", OSC_Casino)` |

### Config keys (`osc/config/config.lua`)

```lua
CHAOS_SHOP_ENABLED = true,
CHAOS_SHOP_ITEMS = {
    { name = "item_osc_ultimate_reroll", team_stock = 5 }, -- 5 на команду за матч
    { name = "item_osc_anchor" },                          -- без лимита
},
```

`ANCHOR_COST` is removed. `ANCHOR_ENABLED` stays and also disables `item_osc_anchor` in the shop.

### Events

| Direction | Name | Payload |
| --- | --- | --- |
| client → server | `osc_shop_buy` | `{ item = "<item name>" }` (engine adds `PlayerID`) |
| server → player | `osc_shop_result` | success `{ ok = 1, item }`; refusal `{ ok = 0, item, error = "<loc key>" }` |
| server → player | `osc_hud_error` (existing) | `{ message = "<loc key>" }`, sent together with every `ok = 0` result |

Malformed requests (no player, no hero, `item` not in `CHAOS_SHOP_ITEMS`) get **no** reply, only `OSC_ClientCommands.LogRefusal("Chaos shop purchase", <player id>, <reason>)`.

When `CHAOS_SHOP_ENABLED ~= true` at `Init`, the listener is not registered and nothing is published, so the event is ignored (spec test "событие игнорируется"). `osc_shop_err_disabled` is for a disabled item (or the flag turned off after Init).

### Net table

Table `osc_state` (already registered), key `"shop_" .. team` for `DOTA_TEAM_GOODGUYS` (2) and `DOTA_TEAM_BADGUYS` (3):

```lua
{ items = { [i] = { name = "item_osc_ultimate_reroll", cost = 3500, stock = 3, max = 5 } } }
```

`stock = -1, max = -1` — unlimited. Disabled items are absent. Published at `Init` and after every successful purchase of that team. Panorama receives the Lua array as an object with keys `"1"`, `"2"`, ….

### Localization keys (all owned by Implementer A)

| Key | ru | en |
| --- | --- | --- |
| `osc_shop_button` | Хаос-лавка | Chaos Shop |
| `osc_shop_title` | ХАОС-ЛАВКА | CHAOS SHOP |
| `osc_shop_buy` | Купить | Buy |
| `osc_shop_close` | Закрыть | Close |
| `osc_shop_stock` | Осталось {d:stock} из {d:max} | {d:stock} of {d:max} left |
| `osc_shop_err_disabled` | Товар недоступен | Item is unavailable |
| `osc_shop_err_no_stock` | Товар закончился | Out of stock |
| `osc_shop_err_no_gold` | Недостаточно золота | Not enough gold |
| `osc_shop_err_no_space` | Нет места в тайнике | No room in the stash |

Item names on the client: `$.Localize("#DOTA_Tooltip_ability_" + name)` (existing keys `DOTA_Tooltip_Ability_item_osc_*`; Dota token lookup is case-insensitive, the casino already relies on this). Client code must not introduce any other `osc_shop_*` string.

### Panorama

| What | Value |
| --- | --- |
| Module file | `content/panorama/scripts/custom_game/osc_chaos_shop.js` |
| Global | `OSC.ChaosShop` = `{ Init, Toggle, Close }` |
| Include | in `osc_hud.xml` `<scripts>`, after `osc_casino.js` |
| Init call | `OSC.ChaosShop.Init();` in `osc_hud.js`, after `OSC.Casino.Init();` |
| Button | `#ChaosShopButton` (classes `OSCButton OSCButtonPrimary Hidden`), `onactivate="OSC.ChaosShop.Toggle()"` |
| Panel | `#ChaosShopPanel` (classes `OSCSurface OSCChaos`), XML after `#CasinoPanel`, before `#ChoicePanel`; children `#ChaosShopTitle`, `#ChaosShopItems`, `#ChaosShopClose` |
| Visible state | class `Visible` on `#ChaosShopPanel`; class `Hidden` on `#ChaosShopButton` while the shop is off |
| Sound | `OSC.Sounds.shopBuy = "General.Buy"` in `osc_core.js` |

---

## Workstreams and file ownership

| Implementer | Files (only these) |
| --- | --- |
| **A — server + localization + test runner** | Create `game/scripts/vscripts/osc/systems/chaos_shop.lua`, `tools/tests/test_chaos_shop.lua`. Modify `game/scripts/vscripts/osc/config/config.lua`, `game/scripts/vscripts/addon_game_mode.lua`, `game/scripts/vscripts/osc/core/game_mode.lua`, `game/scripts/npc/npc_items_custom.txt`, `tools/tests/harness.lua`, `tools/tests/test_reload.lua`, `tools/tests/run_tests.py`, `game/resource/addon_russian.txt`, `game/resource/addon_english.txt` |
| **B — client Panorama** | Create `content/panorama/scripts/custom_game/osc_chaos_shop.js`. Modify `content/panorama/layout/custom_game/osc_hud.xml`, `content/panorama/scripts/custom_game/osc_hud.js`, `content/panorama/scripts/custom_game/osc_core.js`, `content/panorama/styles/custom_game/osc_hud.css` |
| **C — documentation** | Modify `PROJECT_OVERVIEW.md`, `tools/tests/README.md` |

### Why localization moved from C to A

`run_tests.py` has two checks that tie files of different workstreams together:

1. **"Item costs"** (`ITEM_COSTS = {"item_osc_anchor": "ANCHOR_COST"}`) reads `OSC_CONFIG.ANCHOR_COST`. Removing `ANCHOR_COST` (config.lua, A) without removing this check (run_tests.py) makes it fail, so whoever removes `ANCHOR_COST` must own `run_tests.py`.
2. **"Localization"** only validates keys whose prefix is in `LOC_PREFIXES`; `osc_shop_` is not there yet. For the new keys to be checked at all, `run_tests.py` must get `"osc_shop_"` in `LOC_PREFIXES` and `"osc_shop_result"` in `NOT_LOC_KEYS`. Once that prefix exists, every `osc_shop_*` string in Lua (A: `osc_shop_buy` event name, `osc_shop_err_*`) must exist in both `addon_*.txt`.

With localization in C, A's worktree would be red on "Localization" until C merges. With localization in A, every worktree is green on its own:

| Worktree | Lua syntax | JS syntax | Localization | Item costs | Config reads | Lua tests |
| --- | --- | --- | --- | --- | --- | --- |
| A | OK | OK | OK (A adds prefix + all 9 keys) | removed by A | OK | OK |
| B | OK | OK | OK (old `run_tests.py` does not check `osc_shop_`; B uses only contract keys) | OK (untouched) | OK | OK |
| C | OK | OK | OK | OK | OK | OK |

**Expected-red checks per worktree: none.** After merging A and B, the Localization check starts validating B's keys against A's resource files — any typo in B shows up there (see Merge & verify).

## Review Focus

1. `GetItemCost(name)` returns `0`/`nil` for an item with `ItemPurchasable "0"` (unverified engine behaviour) → the purchase must be refused, never given for free. Test: `zero_cost_refused` (A).
2. `SpendGold` charges less than the cost (reliable/unreliable split, engine refusal) → exactly the charged amount is returned, no item, stock untouched. Test: `partial_charge_refunded` (A).
3. The item cannot be created or placed after gold was taken → gold returned, `osc_shop_err_no_space`. Test: `failed_give_refunds_gold` (A).
4. Inventory and backpack full while standing at the shop → item goes to the stash and the player's own items stay where they were. Test: `full_inventory_at_shop_goes_to_stash` (A).
5. The local player's team changes after the HUD loaded (team shuffle, reconnect) → the panel shows the current team's stock. Covered by B re-reading `shop_<team>` on every open and on every `shop_*` net table change; checked in game (Merge & verify).

---

## Workstream A — server, localization, test runner

### Task A1: Config, KV and test runner (remove ANCHOR_COST)

**Files:**
- Modify: `game/scripts/vscripts/osc/config/config.lua:32-36`
- Modify: `game/scripts/npc/npc_items_custom.txt`
- Modify: `tools/tests/run_tests.py`

**Interfaces:**
- Produces: config keys `CHAOS_SHOP_ENABLED`, `CHAOS_SHOP_ITEMS` (shape in Shared contract); `run_tests.py` without the "Item costs" check and with `osc_shop_` localization checking.

- [ ] **Step 1: Edit config.lua**

Replace (Edit tool) this block:

```lua
    -- Предмет «Якорь» (item_osc_anchor): пропустить ближайшую ротацию.
    -- ANCHOR_COST должен совпадать с ItemCost в npc_items_custom.txt
    -- (это проверяет tools/tests/run_tests.py)
    ANCHOR_ENABLED = true,
    ANCHOR_COST = 400,
```

with:

```lua
    -- Предмет «Якорь» (item_osc_anchor): пропустить ближайшую ротацию
    ANCHOR_ENABLED = true,
    -- Хаос-лавка (osc/systems/chaos_shop.lua): предметы режима продаются в
    -- своей панели HUD, а не в стандартном магазине. Цена — ItemCost в
    -- npc_items_custom.txt; team_stock — сколько штук команда может купить
    -- за матч, без него — без лимита. «Якорь» выключается и ANCHOR_ENABLED.
    CHAOS_SHOP_ENABLED = true,
    CHAOS_SHOP_ITEMS = {
        { name = "item_osc_ultimate_reroll", team_stock = 5 }, -- 5 на команду за матч
        { name = "item_osc_anchor" },                          -- без лимита
    },
```

- [ ] **Step 2: Edit npc_items_custom.txt**

In `item_osc_ultimate_reroll`: change `"ItemPurchasable"           "1"` to `"0"` and delete the two lines `"ItemStockMax"              "5"` and `"ItemStockTime"             "0"`. Add a comment line above the block, same style as the anchor's:

```
	// Реролл ультимейта. Продаётся только в Хаос-лавке (osc/systems/chaos_shop.lua),
	// лимит на команду — CHAOS_SHOP_ITEMS в config.lua
	"item_osc_ultimate_reroll"
```

In `item_osc_anchor`: change `"ItemPurchasable"` to `"0"` and replace the comment `// «Якорь»: пропустить ближайшую ротацию. Цена = OSC_CONFIG.ANCHOR_COST` with:

```
	// «Якорь»: пропустить ближайшую ротацию. Продаётся только в Хаос-лавке
```

`ItemCost` values (3500 and 400) stay untouched — they are the single source of the price.

- [ ] **Step 3: Run tests to see the "Item costs" check fail**

Run: `python tools/tests/run_tests.py`
Expected: `Item costs: FAIL` with `item_osc_anchor: ItemCost 400 != OSC_CONFIG.ANCHOR_COST None`; `RESULT: FAIL (1 problems)`.

- [ ] **Step 4: Edit run_tests.py**

1. In the module docstring, delete the line `   Цены предметов в npc_items_custom.txt совпадают с OSC_CONFIG.` (item 3 keeps only the localization sentence).
2. Delete the line `ITEMS_KV = ROOT / "game" / "scripts" / "npc" / "npc_items_custom.txt"`.
3. Delete the comment `# KV не может брать цену из Lua-конфига, поэтому держим их согласованными` and the `ITEM_COSTS = { ... }` dict.
4. Delete the functions `kv_item_cost` and `check_item_costs` entirely.
5. In `main()`, delete the tuple line `("Item costs", check_item_costs),`.
6. Add `"osc_shop_",` to `LOC_PREFIXES` (after `"osc_anchor_err_",`).
7. Change `NOT_LOC_KEYS = {"osc_hud_error"}` to `NOT_LOC_KEYS = {"osc_hud_error", "osc_shop_result"}`.

Leave the rest as is. `osc_shop_buy` is both an event name and a localization key (button text), so it must not go into `NOT_LOC_KEYS`.

- [ ] **Step 5: Run tests**

Run: `python tools/tests/run_tests.py`
Expected: no "Item costs" line; `Localization: OK`; `RESULT: OK`. (No Lua code uses `osc_shop_*` yet.)

- [ ] **Step 6: Commit**

```bash
git add game/scripts/vscripts/osc/config/config.lua game/scripts/npc/npc_items_custom.txt tools/tests/run_tests.py
git commit -m "feat: chaos shop config, remove ANCHOR_COST and standard shop sale" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A2: Localization keys

**Files:**
- Modify: `game/resource/addon_russian.txt` (after line 54 `"osc_anchor_err_disabled"`)
- Modify: `game/resource/addon_english.txt` (after line 51 `"osc_anchor_err_disabled"`)

**Interfaces:**
- Produces: the 9 keys of the Shared contract in both files.

- [ ] **Step 1: Add keys to addon_russian.txt**

With the Edit tool, after the line `		"osc_anchor_err_disabled"	"Якорь отключён"` insert (two leading tabs, tab between key and value, like the neighbouring lines):

```
		"osc_shop_button"	"Хаос-лавка"
		"osc_shop_title"	"ХАОС-ЛАВКА"
		"osc_shop_buy"	"Купить"
		"osc_shop_close"	"Закрыть"
		"osc_shop_stock"	"Осталось {d:stock} из {d:max}"
		"osc_shop_err_disabled"	"Товар недоступен"
		"osc_shop_err_no_stock"	"Товар закончился"
		"osc_shop_err_no_gold"	"Недостаточно золота"
		"osc_shop_err_no_space"	"Нет места в тайнике"
```

- [ ] **Step 2: Add keys to addon_english.txt**

After the line `			"osc_anchor_err_disabled"	"Anchor is disabled"` insert (three leading tabs, as in this file):

```
			"osc_shop_button"	"Chaos Shop"
			"osc_shop_title"	"CHAOS SHOP"
			"osc_shop_buy"	"Buy"
			"osc_shop_close"	"Close"
			"osc_shop_stock"	"{d:stock} of {d:max} left"
			"osc_shop_err_disabled"	"Item is unavailable"
			"osc_shop_err_no_stock"	"Out of stock"
			"osc_shop_err_no_gold"	"Not enough gold"
			"osc_shop_err_no_space"	"No room in the stash"
```

- [ ] **Step 3: Run tests**

Run: `python tools/tests/run_tests.py`
Expected: `Localization: OK` (key sets of ru/en equal), `RESULT: OK`.

- [ ] **Step 4: Commit**

```bash
git add game/resource/addon_russian.txt game/resource/addon_english.txt
git commit -m "feat: chaos shop localization" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A3: Harness mocks and failing tests

**Files:**
- Modify: `tools/tests/harness.lua`
- Create: `tools/tests/test_chaos_shop.lua`

**Interfaces:**
- Produces (harness): globals `DOTA_ModifyGold_PurchaseItem`, `DOTA_SHOP_HOME`, `DOTA_STASH_SLOT_1`…`DOTA_STASH_SLOT_6`, `CreateItem(name, owner, purchaser)`, `GetItemCost(name)` (reads `H.itemCosts`), `Hero:IsInRangeOfShop(shopType, physical)` (returns `hero.at_shop == true`), `Hero:SwapItems(slot1, slot2)`.

- [ ] **Step 1: Add mocks to harness.lua**

1. In the `H = { ... }` table add a field after `kv = {},`:

```lua
    itemCosts = {}, -- ItemCost предметов для GetItemCost
```

2. After the line `DOTA_ModifyGold_Unspecified = 0` add:

```lua
DOTA_ModifyGold_PurchaseItem = 4
DOTA_SHOP_HOME = 0
-- Слоты тайника как в Dota: 0-5 инвентарь, 6-8 рюкзак, 9-14 тайник
DOTA_STASH_SLOT_1 = 9
DOTA_STASH_SLOT_2 = 10
DOTA_STASH_SLOT_3 = 11
DOTA_STASH_SLOT_4 = 12
DOTA_STASH_SLOT_5 = 13
DOTA_STASH_SLOT_6 = 14
```

3. Replace the existing `H.NewItem` and the line before it so the block reads:

```lua
function ExecuteOrderFromTable(order) H.lastOrder = order end
function CreateUnitByName() return nil end
function CreateItem(name) return H.NewItem(name) end
function GetItemCost(name) return H.itemCosts[name] or 0 end
```

(`H.NewItem` itself stays unchanged right below.)

4. After `function Hero:AddItem(item) ... end` add:

```lua
-- Тест ставит hero.at_shop = true, когда герой стоит у базового магазина
function Hero:IsInRangeOfShop() return self.at_shop == true end
function Hero:SwapItems(first, second)
    self.items[first], self.items[second] = self.items[second], self.items[first]
end
```

- [ ] **Step 2: Write the failing tests**

Create `tools/tests/test_chaos_shop.lua`:

```lua
-- Хаос-лавка: покупка у магазина и в тайник, сток команды, отказы без
-- списания золота, выключенные товары

local REROLL, ANCHOR = "item_osc_ultimate_reroll", "item_osc_anchor"

-- opts: gold, alive, at_shop (по умолчанию герой жив и у магазина)
local function setup(opts)
    opts = opts or {}
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/chaos_shop")
    H.itemCosts = { [REROLL] = 3500, [ANCHOR] = 400 }
    local hero = H.NewHero({ alive = opts.alive })
    hero.at_shop = opts.at_shop ~= false
    H.AddPlayer(0, hero, { gold = opts.gold or 5000 })
    return hero
end

local function buy(item)
    OSC_ChaosShop.OnBuy(1, { PlayerID = 0, item = item })
end

local function shopItem(team, name)
    for _, item in ipairs(H.netTables["shop_" .. team].items) do
        if item.name == name then return item end
    end
end

local function fill(hero, first, last)
    for slot = first, last do
        hero.items[slot] = H.NewItem("item_branches")
    end
end

local function assertRefused(reason)
    local result = H.lastEvent("osc_shop_result")
    H.truthy(result, "result sent")
    H.eq(result.data.ok, 0, "refused")
    H.eq(result.data.error, reason, "error key")
    H.eq(H.lastEvent("osc_hud_error").data.message, reason, "HUD error")
end

return {
    init_publishes_both_teams = function()
        setup()
        OSC_ChaosShop.Init()
        for _, team in ipairs({ DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }) do
            local reroll = shopItem(team, REROLL)
            H.eq(reroll.cost, 3500, "reroll cost from KV")
            H.eq(reroll.stock, 5, "reroll stock")
            H.eq(reroll.max, 5, "reroll max")
            local anchor = shopItem(team, ANCHOR)
            H.eq(anchor.cost, 400, "anchor cost from KV")
            H.eq(anchor.stock, -1, "anchor unlimited stock")
            H.eq(anchor.max, -1, "anchor unlimited max")
        end
        H.truthy(H.listeners.osc_shop_buy, "listener registered")
    end,

    buy_at_shop_puts_item_in_inventory = function()
        local hero = setup()
        OSC_ChaosShop.Init()
        buy(REROLL)
        H.eq(H.players[0].gold, 1500, "gold charged by ItemCost")
        H.eq(hero.items[0] and hero.items[0].name, REROLL, "item in inventory")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 4, "team stock decreased")
        H.eq(shopItem(DOTA_TEAM_BADGUYS, REROLL).stock, 5, "other team untouched")
        local result = H.lastEvent("osc_shop_result")
        H.eq(result.data.ok, 1, "success result")
        H.eq(result.data.item, REROLL, "result item")
    end,

    unknown_item_refused_silently = function()
        local hero = setup()
        OSC_ChaosShop.Init()
        buy("item_rapier")
        H.eq(H.players[0].gold, 5000, "gold untouched")
        H.eq(hero.items[0], nil, "no item")
        H.eq(H.lastEvent("osc_shop_result"), nil, "no reply to a forged request")
        H.truthy(H.logged("Chaos shop purchase of player 0 refused: invalid_item"), "refusal logged")
    end,

    not_enough_gold_refused = function()
        local hero = setup({ gold = 1000 })
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_no_gold")
        H.eq(H.players[0].gold, 1000, "gold untouched")
        H.eq(hero.items[0], nil, "no item")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 5, "stock untouched")
    end,

    stock_runs_out = function()
        setup({ gold = 100000 })
        OSC_ChaosShop.Init()
        for _ = 1, 5 do buy(REROLL) end
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 0, "stock empty")
        buy(REROLL)
        assertRefused("osc_shop_err_no_stock")
        H.eq(H.players[0].gold, 100000 - 5 * 3500, "sixth not charged")
    end,

    away_from_shop_goes_to_stash = function()
        local hero = setup({ at_shop = false })
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        H.eq(hero.items[0], nil, "not in inventory")
        H.eq(hero.items[DOTA_STASH_SLOT_1] and hero.items[DOTA_STASH_SLOT_1].name, ANCHOR, "in stash")
        H.eq(H.players[0].gold, 4600, "charged")
    end,

    dead_hero_goes_to_stash = function()
        local hero = setup({ alive = false })
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        H.eq(hero.items[0], nil, "not in inventory")
        H.eq(hero.items[DOTA_STASH_SLOT_1] and hero.items[DOTA_STASH_SLOT_1].name, ANCHOR, "in stash")
    end,

    full_inventory_at_shop_goes_to_stash = function()
        local hero = setup()
        fill(hero, 0, 8)
        local backpackItem = hero.items[8]
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        H.eq(hero.items[DOTA_STASH_SLOT_1] and hero.items[DOTA_STASH_SLOT_1].name, ANCHOR, "in stash")
        H.eq(hero.items[8], backpackItem, "own backpack item back in place")
        H.eq(H.players[0].gold, 4600, "charged")
    end,

    stash_full_refused_without_charge = function()
        local hero = setup({ at_shop = false })
        fill(hero, DOTA_STASH_SLOT_1, DOTA_STASH_SLOT_6)
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        assertRefused("osc_shop_err_no_space")
        H.eq(H.players[0].gold, 5000, "gold untouched")
        H.eq(hero.items[0], nil, "no item")
    end,

    anchor_disabled = function()
        setup()
        OSC_CONFIG.ANCHOR_ENABLED = false
        OSC_ChaosShop.Init()
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, ANCHOR), nil, "anchor not in net table")
        H.truthy(shopItem(DOTA_TEAM_GOODGUYS, REROLL), "reroll still sold")
        buy(ANCHOR)
        assertRefused("osc_shop_err_disabled")
        H.eq(H.players[0].gold, 5000, "gold untouched")
    end,

    shop_disabled_ignores_event = function()
        setup()
        OSC_CONFIG.CHAOS_SHOP_ENABLED = false
        OSC_ChaosShop.Init()
        H.eq(H.listeners.osc_shop_buy, nil, "no listener")
        H.eq(H.netTables["shop_" .. DOTA_TEAM_GOODGUYS], nil, "nothing published")
    end,

    zero_cost_refused = function()
        local hero = setup()
        H.itemCosts[REROLL] = 0
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_disabled")
        H.eq(hero.items[0], nil, "not given for free")
    end,

    partial_charge_refunded = function()
        local hero = setup()
        PlayerResource.SpendGold = function(_, id) H.players[id].gold = H.players[id].gold - 100 end
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_no_gold")
        H.eq(H.players[0].gold, 5000, "partial charge returned")
        H.eq(hero.items[0], nil, "no item")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 5, "stock untouched")
    end,

    failed_give_refunds_gold = function()
        setup()
        CreateItem = function() return nil end
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_no_space")
        H.eq(H.players[0].gold, 5000, "gold returned")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 5, "stock untouched")
    end,
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `python tools/tests/run_tests.py`
Expected: every `test_chaos_shop.*` line is `FAIL ... module 'osc/systems/chaos_shop' not found`; all other tests PASS; `RESULT: FAIL (14 problems)`.

### Task A4: Server system OSC_ChaosShop and wiring

**Files:**
- Create: `game/scripts/vscripts/osc/systems/chaos_shop.lua`
- Modify: `game/scripts/vscripts/addon_game_mode.lua:21`
- Modify: `game/scripts/vscripts/osc/core/game_mode.lua:31`
- Modify: `tools/tests/test_reload.lua` (MODULES list)

**Interfaces:**
- Consumes: `OSC_ClientCommands.Check`, `OSC_ClientCommands.OneOf`, `OSC_ClientCommands.LogRefusal` (`osc/core/client_commands.lua`); `OSC_Notifications.PlayerEvent` (`osc/core/notifications.lua`); `OSC_Anchor.IsEnabled` (`osc/core/anchor.lua`); `OSC_Config.Get`; harness mocks from A3.
- Produces: `OSC_ChaosShop.Init()`, `OSC_ChaosShop.Publish(team)`, `OSC_ChaosShop.OnBuy(sourceIndex, event)`, events/net table exactly as in the Shared contract.

- [ ] **Step 1: Write chaos_shop.lua**

Create `game/scripts/vscripts/osc/systems/chaos_shop.lua`:

```lua
-- Хаос-лавка (флаг CHAOS_SHOP_ENABLED): предметы режима из CHAOS_SHOP_ITEMS
-- продаются в своей панели HUD (osc_chaos_shop.js). В стандартном магазине
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

-- sold[team][item] — сколько продано команде; переживает script_reload
OSC_ChaosShop = OSC_ChaosShop or { sold = {} }

local BACKPACK_LAST_SLOT = 8 -- 0-5 инвентарь, 6-8 рюкзак

local function GetItems()
    return OSC_Config.Get("CHAOS_SHOP_ITEMS") or {}
end

local function FindEntry(name)
    for _, entry in ipairs(GetItems()) do
        if entry.name == name then
            return entry
        end
    end
end

-- «Якорь» выключается своим флагом ANCHOR_ENABLED
local function IsItemEnabled(name)
    return name ~= "item_osc_anchor" or OSC_Anchor.IsEnabled()
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
    hero:AddItem(item)
    local slot = FindItemSlot(hero, item)
    if slot == nil then
        if freed then
            hero:SwapItems(BACKPACK_LAST_SLOT, stashSlot)
        end
        UTIL_Remove(item)
        return false
    end
    if stashSlot ~= nil and slot ~= stashSlot then
        hero:SwapItems(slot, stashSlot)
    end
    return true
end

-- Возврат так же, как списали: сначала надёжное золото (как ReturnGold в casino.lua)
local function ReturnGold(playerID, amount, reliableSpent)
    local reliablePart = math.min(amount, reliableSpent)
    if reliablePart > 0 then
        PlayerResource:ModifyGold(playerID, reliablePart, true, DOTA_ModifyGold_Unspecified)
    end
    if amount > reliablePart then
        PlayerResource:ModifyGold(playerID, amount - reliablePart, false, DOTA_ModifyGold_Unspecified)
    end
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

    -- Сверяем фактически списанное, как в casino.lua
    local goldBefore = PlayerResource:GetGold(playerID)
    local reliableBefore = PlayerResource:GetReliableGold(playerID)
    PlayerResource:SpendGold(playerID, cost, DOTA_ModifyGold_PurchaseItem)
    local spent = goldBefore - PlayerResource:GetGold(playerID)
    local reliableSpent = math.max(0, reliableBefore - PlayerResource:GetReliableGold(playerID))
    if spent ~= cost then
        if spent > 0 then
            ReturnGold(playerID, spent, reliableSpent)
        end
        OSC_Logger.Error("Chaos shop: " .. name .. " was not charged: expected "
            .. cost .. ", got " .. spent)
        Refuse("osc_shop_err_no_gold")
        return
    end

    if not GiveItem(hero, name, destination ~= "inventory" and destination or nil) then
        ReturnGold(playerID, spent, reliableSpent)
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
```

- [ ] **Step 2: Run tests**

Run: `python tools/tests/run_tests.py`
Expected: all `test_chaos_shop.*` PASS; `RESULT: OK`.

- [ ] **Step 3: Wire require and SafeInit**

In `game/scripts/vscripts/addon_game_mode.lua`, after `require("osc/systems/casino")` add:

```lua
require("osc/systems/chaos_shop")
```

In `game/scripts/vscripts/osc/core/game_mode.lua`, after `SafeInit("Casino", OSC_Casino)` add:

```lua
    SafeInit("ChaosShop", OSC_ChaosShop)
```

In `tools/tests/test_reload.lua`, in `MODULES` after the `osc/systems/casino` line add:

```lua
    { file = "osc/systems/chaos_shop", global = "OSC_ChaosShop" },
```

- [ ] **Step 4: Run tests**

Run: `python tools/tests/run_tests.py`
Expected: `test_game_mode.activate_validates_pools` PASS (Activate now also runs `ChaosShop` init; `H.logs` must not contain `ChaosShop init failed` — check with a quick look at the output if anything fails), `test_reload.modules_keep_their_table_on_reload` PASS, `RESULT: OK`.

- [ ] **Step 5: Commit**

```bash
git add game/scripts/vscripts/osc/systems/chaos_shop.lua game/scripts/vscripts/addon_game_mode.lua game/scripts/vscripts/osc/core/game_mode.lua tools/tests/harness.lua tools/tests/test_chaos_shop.lua tools/tests/test_reload.lua
git commit -m "feat: chaos shop server system with team stock and stash delivery" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Dota API facts used by A — verify in game

These are written from memory of the Dota VScript API and are **not verified**; the merger checks them in Workshop Tools (see Merge & verify). Fallbacks, if a check fails:

| Fact | Fallback if wrong |
| --- | --- |
| `GetItemCost(name)` returns `ItemCost` even with `ItemPurchasable "0"` | If it returns 0, purchases are refused by the `cost <= 0` guard (logged `Chaos shop: no ItemCost for ...`). Then read the price from the created item instead: `CreateItem(name, nil, nil):GetCost()` once per name in `Publish`/`OnBuy`, and `UTIL_Remove` the probe item. |
| `hero:IsInRangeOfShop(DOTA_SHOP_HOME, true)` is true at the base shop | If always false, purchases go to the stash (still correct, just slower). Alternative: distance from hero to the team's `ent_dota_fountain` (pattern in `couriers.lua` `FindTeamFountain`). |
| `DOTA_STASH_SLOT_1..6` are defined (= 9..14) | Use `OSC_Config.Get("COURIERS.STASH_FIRST_SLOT")` / `STASH_LAST_SLOT` (9/14), which the courier system already uses for the same slots. |
| `hero:SwapItems(inventorySlot, stashSlot)` moves an item into the stash away from the shop | If it refuses outside the shop, the item stays in the inventory (delivered instantly, no gold lost). Accept that degraded behaviour and report it to the user; do not invent another placement path without a decision. |
| `DOTA_ModifyGold_PurchaseItem` exists | Use `DOTA_ModifyGold_Unspecified` (as casino does). |
| `CreateItem(name, hero, hero)` sets owner and purchaser so the item is sellable and the courier picks it from the stash | If the courier ignores it, check `couriers.lua` `FindStashItem` (it only needs `GetItemInSlot`). |

---

## Workstream B — client Panorama

B has no unit-test harness for JS; the check is `run_tests.py` (JS syntax via `node --check`, localization of XML/JS keys) plus the in-game checks. Use only the contract keys listed in the Shared contract.

### Task B1: Module OSC.ChaosShop

**Files:**
- Create: `content/panorama/scripts/custom_game/osc_chaos_shop.js`
- Modify: `content/panorama/scripts/custom_game/osc_core.js` (`OSC.Sounds`)

**Interfaces:**
- Consumes: net table `osc_state/shop_<team>`, events `osc_shop_result`, `osc_shop_buy` (Shared contract); `OSC.Util.Loop`, `OSC.Util.PlaySound`, `OSC.Util.IsPostGame` (`osc_core.js`).
- Produces: `OSC.ChaosShop.Init()`, `OSC.ChaosShop.Toggle()`, `OSC.ChaosShop.Close()`; expects panels `#ChaosShopButton`, `#ChaosShopPanel`, `#ChaosShopItems` (Task B2).

- [ ] **Step 1: Add the purchase sound**

In `osc_core.js`, inside `OSC.Sounds`, after `casinoJackpot: "General.Coins",` add:

```js
  shopBuy: "General.Buy", // покупка в Хаос-лавке
```

- [ ] **Step 2: Write osc_chaos_shop.js**

```js
"use strict";

var OSC = OSC || {};

// Хаос-лавка: кнопка в правом нижнем углу и панель с предметами режима.
// Товары — osc_state/shop_<team> = { items = { [i] = { name, cost, stock, max } } }
// (stock = max = -1 — без лимита). Покупку решает сервер: osc_shop_buy { item },
// ответ osc_shop_result { ok, item, error }; ошибки показывает OSC.HudError.
OSC.ChaosShop = (function () {
  var GOLD_POLL = 0.25; // как часто обновлять кнопки, пока панель открыта

  var rows = []; // { item, button } — для обновления кнопок по золоту
  var open = false;
  var openToken = 0; // меняется при каждом открытии, чтобы не плодить опросы

  // Команду читаем каждый раз: после перемешивания команд она могла смениться
  function NetTableKey() {
    return "shop_" + Players.GetTeam(Players.GetLocalPlayer());
  }

  // Lua-массив приходит объектом { "1": ..., "2": ... }
  function ToList(table) {
    if (!table) return [];
    return Object.keys(table)
      .sort(function (a, b) {
        return Number(a) - Number(b);
      })
      .map(function (key) {
        return table[key];
      });
  }

  // Только подсказка: золото и остаток проверяет сервер
  function UpdateButtons() {
    var gold = Players.GetGold(Players.GetLocalPlayer());
    rows.forEach(function (row) {
      row.button.enabled =
        gold >= Number(row.item.cost) && Number(row.item.stock) !== 0;
    });
  }

  function AddLabel(parent, classes, text) {
    var label = $.CreatePanel("Label", parent, "");
    classes.forEach(function (name) {
      label.AddClass(name);
    });
    label.text = text;
    return label;
  }

  function BuildRow(list, item) {
    var row = $.CreatePanel("Panel", list, "");
    row.AddClass("ChaosShopRow");

    // Стандартная подсказка предмета Dota при наведении
    var image = $.CreatePanel("DOTAItemImage", row, "");
    image.itemname = item.name;
    image.SetPanelEvent("onmouseover", function () {
      $.DispatchEvent("DOTAShowAbilityTooltip", image, item.name);
    });
    image.SetPanelEvent("onmouseout", function () {
      $.DispatchEvent("DOTAHideAbilityTooltip", image);
    });

    var info = $.CreatePanel("Panel", row, "");
    info.AddClass("ChaosShopInfo");
    AddLabel(info, ["OSCTextBody", "OSCBold"], $.Localize("#DOTA_Tooltip_ability_" + item.name));
    AddLabel(info, ["OSCTextSmall", "OSCGold"], String(item.cost));
    if (Number(item.max) >= 0) {
      var stock = AddLabel(info, ["OSCTextSmall", "OSCMuted"], "");
      stock.SetDialogVariableInt("stock", Number(item.stock));
      stock.SetDialogVariableInt("max", Number(item.max));
      stock.text = $.Localize("#osc_shop_stock", stock);
    }

    var button = $.CreatePanel("Button", row, "");
    button.AddClass("OSCButton");
    button.AddClass("OSCButtonPrimary");
    button.AddClass("ChaosShopBuy");
    AddLabel(button, [], $.Localize("#osc_shop_buy"));
    button.SetPanelEvent("onactivate", function () {
      GameEvents.SendCustomGameEventToServer("osc_shop_buy", { item: item.name });
    });
    rows.push({ item: item, button: button });
  }

  function Refresh() {
    // Сервер публикует таблицы обеих команд, если лавка включена
    var enabled = !!CustomNetTables.GetTableValue(
      "osc_state",
      "shop_" + DOTATeam_t.DOTA_TEAM_GOODGUYS
    );
    $("#ChaosShopButton").SetHasClass("Hidden", !enabled);
    if (!enabled && open) SetOpen(false);

    var data = CustomNetTables.GetTableValue("osc_state", NetTableKey());
    var list = $("#ChaosShopItems");
    list.RemoveAndDeleteChildren();
    rows = [];
    ToList(data && data.items).forEach(function (item) {
      BuildRow(list, item);
    });
    UpdateButtons();
  }

  function SetOpen(show) {
    open = show;
    $("#ChaosShopPanel").SetHasClass("Visible", show);
    if (!show) return;
    Refresh();
    var token = ++openToken;
    OSC.Util.Loop(GOLD_POLL, function () {
      if (!open || token !== openToken || OSC.Util.IsPostGame()) return false;
      UpdateButtons();
    });
  }

  function Toggle() {
    SetOpen(!open);
  }

  function Close() {
    SetOpen(false);
  }

  function OnResult(event) {
    if (event && Number(event.ok) === 1) OSC.Util.PlaySound(OSC.Sounds.shopBuy);
  }

  function OnNetTableChanged(tableName, key) {
    if (key.indexOf("shop_") === 0) Refresh();
  }

  function Init() {
    CustomNetTables.SubscribeNetTableListener("osc_state", OnNetTableChanged);
    GameEvents.Subscribe("osc_shop_result", OnResult);
    // Переподключение: таблицы могли прийти до загрузки HUD
    Refresh();
  }

  return {
    Init: Init,
    Toggle: Toggle, // вызывается из XML
    Close: Close, // вызывается из XML
  };
})();
```

Notes for B:
- `osc_shop_buy` is the event name and also a localization key; both are in the contract, do not rename.
- Keep all `osc_shop_*` strings exactly as listed; after merge `run_tests.py` checks each one against A's resource files.
- `DOTAShowAbilityTooltip` on a `DOTAItemImage` shows the item tooltip — **verify in game**. Fallback: remove the two `SetPanelEvent` calls (a `DOTAItemImage` may already show its own tooltip) or use `DOTAShowAbilityTooltipForEntityIndex` — no entity here, so prefer the first fallback.
- `Players.GetTeam(playerID)` and `DOTATeam_t.DOTA_TEAM_GOODGUYS` are standard Panorama API — **verify in game** if the button never appears. Fallback: `Game.GetLocalPlayerInfo().player_team_id` and the literal `2`.

- [ ] **Step 3: Run tests**

Run: `python tools/tests/run_tests.py`
Expected: `JS syntax: OK`, `RESULT: OK`.

- [ ] **Step 4: Commit**

```bash
git add content/panorama/scripts/custom_game/osc_chaos_shop.js content/panorama/scripts/custom_game/osc_core.js
git commit -m "feat: chaos shop Panorama module" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B2: HUD markup, init and styles

**Files:**
- Modify: `content/panorama/layout/custom_game/osc_hud.xml`
- Modify: `content/panorama/scripts/custom_game/osc_hud.js`
- Modify: `content/panorama/styles/custom_game/osc_hud.css` (append at end)

**Interfaces:**
- Consumes: `OSC.ChaosShop` from B1.
- Produces: panels with ids/classes from the Shared contract.

- [ ] **Step 1: Include the script and add panels in osc_hud.xml**

In `<scripts>`, after `<include src="file://{resources}/scripts/custom_game/osc_casino.js" />` add:

```xml
        <include src="file://{resources}/scripts/custom_game/osc_chaos_shop.js" />
```

Between the closing `</Panel>` of `#CasinoPanel` and the comment `<!-- Выбор следующей способности: ...` add:

```xml
        <!-- Хаос-лавка (osc_chaos_shop.js): кнопка рядом со стандартным
             магазином и панель товаров; строки товаров создаются из JS -->
        <Button id="ChaosShopButton" class="OSCButton OSCButtonPrimary Hidden"
            onactivate="OSC.ChaosShop.Toggle()">
            <Label text="#osc_shop_button" />
        </Button>
        <Panel id="ChaosShopPanel" class="OSCSurface OSCChaos" hittest="true">
            <Label id="ChaosShopTitle" class="OSCTextTitle OSCChaosText" text="#osc_shop_title" />
            <Panel id="ChaosShopItems" />
            <Button id="ChaosShopClose" class="OSCButton" onactivate="OSC.ChaosShop.Close()">
                <Label text="#osc_shop_close" />
            </Button>
        </Panel>
```

- [ ] **Step 2: Call Init in osc_hud.js**

After `  OSC.Casino.Init();` add:

```js
  OSC.ChaosShop.Init();
```

- [ ] **Step 3: Append styles to osc_hud.css**

```css
/* ================= Хаос-лавка ================= */

/* Правый нижний угол рядом со стандартным магазином; отступы подогнать в игре */
#ChaosShopButton {
  min-width: 140px;
  min-height: 34px;
  horizontal-align: right;
  vertical-align: bottom;
  margin-right: 16px;
  margin-bottom: 290px;
}

#ChaosShopButton.Hidden {
  visibility: collapse;
}

#ChaosShopButton Label {
  font-size: 16px;
}

#ChaosShopPanel {
  width: 400px;
  padding: 16px;
  horizontal-align: right;
  vertical-align: bottom;
  margin-right: 16px;
  margin-bottom: 336px;
  flow-children: down;
  visibility: collapse;
}

#ChaosShopPanel.Visible {
  visibility: visible;
}

#ChaosShopTitle {
  horizontal-align: center;
}

#ChaosShopItems {
  width: 100%;
  margin: 12px 0px;
  flow-children: down;
}

.ChaosShopRow {
  width: 100%;
  margin-bottom: 8px;
  flow-children: right;
}

.ChaosShopRow DOTAItemImage {
  width: 64px;
  height: 48px;
  vertical-align: center;
}

.ChaosShopInfo {
  width: fill-parent-flow(1.0);
  margin: 0px 10px;
  vertical-align: center;
  flow-children: down;
}

.ChaosShopBuy {
  min-width: 96px;
  min-height: 36px;
  vertical-align: center;
}

.ChaosShopBuy:disabled {
  opacity: 0.45;
}

.ChaosShopBuy Label {
  font-size: 16px;
}

#ChaosShopClose {
  horizontal-align: center;
}
```

- [ ] **Step 4: Run tests**

Run: `python tools/tests/run_tests.py`
Expected: `JS syntax: OK`, `Localization: OK`, `RESULT: OK`.

- [ ] **Step 5: Commit**

```bash
git add content/panorama/layout/custom_game/osc_hud.xml content/panorama/scripts/custom_game/osc_hud.js content/panorama/styles/custom_game/osc_hud.css
git commit -m "feat: chaos shop button and panel in HUD" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Workstream C — documentation

### Task C1: PROJECT_OVERVIEW.md and tests README

**Files:**
- Modify: `PROJECT_OVERVIEW.md`
- Modify: `tools/tests/README.md`

**Interfaces:**
- Consumes: Shared contract names (describe them exactly; do not invent new ones).

- [ ] **Step 1: «Якорь» bullet (section «Ротация», ~line 125)**

Replace the first two lines of the bullet:

```markdown
- Предмет «Якорь» `item_osc_anchor` (`ANCHOR_ENABLED`, цена `ANCHOR_COST` =
  400, один заряд): основной герой ставит якорь (`osc/core/anchor.lua`),
```

with:

```markdown
- Предмет «Якорь» `item_osc_anchor` (`ANCHOR_ENABLED`, цена 400 — `ItemCost`
  в KV, один заряд, продаётся в Хаос-лавке): основной герой ставит якорь
  (`osc/core/anchor.lua`),
```

The rest of the bullet stays as is.

- [ ] **Step 2: New section after «Казино Огра» (before `### Уведомления и интерфейс`)**

```markdown
### Хаос-лавка

- Предметы режима (`item_osc_ultimate_reroll`, `item_osc_anchor`) продаются
  только в Хаос-лавке: кнопка в правом нижнем углу HUD рядом со стандартным
  магазином открывает панель с товарами. В стандартном магазине их нет
  (`ItemPurchasable "0"`), цена — `ItemCost` в `npc_items_custom.txt`.
- Список товаров и лимиты — `CHAOS_SHOP_ITEMS`: реролл ультимейта — 5 на
  команду за матч (`team_stock`), «Якорь» — без лимита; `CHAOS_SHOP_ENABLED`
  выключает лавку, `ANCHOR_ENABLED = false` убирает из неё «Якорь».
- Сервер (`osc/systems/chaos_shop.lua`, `OSC_ChaosShop`): клиент шлёт
  `osc_shop_buy { item }`, команда проходит `OSC_ClientCommands.Check`.
  Затем по порядку: товар выключен, кончился сток команды, не хватает
  золота, некуда положить — отказ без списания (`osc_shop_err_*`, красная
  строка `osc_hud_error` и `osc_shop_result { ok = 0, item, error }`).
- Герой жив и у базового магазина — предмет в инвентарь (инвентарь и рюкзак
  полны — в тайник); иначе — в свободный слот тайника, оттуда его доставит
  курьер. Золото списывается со сверкой фактически списанного, как в казино;
  если списалось не всё или предмет не выдался — золото возвращается.
- Net table `osc_state/shop_<team>` = `{ items = { [i] = { name, cost, stock, max } } }`
  (`stock = max = -1` — без лимита) публикуется при старте и после каждой
  покупки команды; сток переживает `script_reload`.
- Panorama: `osc_chaos_shop.js` (`OSC.ChaosShop`), панель `#ChaosShopPanel`.
  Кнопка «Купить» неактивна при нехватке золота или пустом стоке — это
  только подсказка, решает сервер.
```

- [ ] **Step 3: Net table key list (section «Сеть и контент»)**

In the bullet listing keys, after `` `anchor_<playerID>` («Якорь»), `` add `` `shop_<team>` (Хаос-лавка), ``.

- [ ] **Step 4: Config table (section «Основная конфигурация»)**

Replace the row

```markdown
| `ANCHOR_COST`                          |            `400` | Цена «Якоря» (= ItemCost в KV)            |
```

with:

```markdown
| `CHAOS_SHOP_ENABLED`                   |           `true` | Хаос-лавка                                |
| `CHAOS_SHOP_ITEMS`                     |   реролл 5, якорь | Товары лавки и лимит на команду (`team_stock`) |
```

- [ ] **Step 5: «Важные файлы для изменений» and «Офлайн-тесты»**

After `- Серверная логика автомата: \`osc/systems/casino.lua\`.` add:

```markdown
- Хаос-лавка: `osc/systems/chaos_shop.lua`.
```

In «Офлайн-тесты», replace these three lines:

```markdown
синтаксис Lua (LuaJIT) и Panorama JS, сверка ключей локализации ru/en,
цен предметов в KV с конфигом и
модульные тесты систем на моках Dota API. Запуск:
```

with (keep ` Запуск:` at the end of the second line):

```markdown
синтаксис Lua (LuaJIT) и Panorama JS, сверка ключей локализации ru/en,
прямые чтения `OSC_CONFIG` и модульные тесты систем на моках Dota API.
```

- [ ] **Step 6: tools/tests/README.md**

Delete the bullet `- цены предметов: \`ItemCost\` в \`npc_items_custom.txt\` совпадает с конфигом (\`ITEM_COSTS\` в \`run_tests.py\`);` (the check is removed by A: the price lives only in KV now).

- [ ] **Step 7: Check for leftovers and run tests**

Run: `grep -n "ANCHOR_COST\|ITEM_COSTS" PROJECT_OVERVIEW.md tools/tests/README.md`
Expected: no output.

Run: `python tools/tests/run_tests.py`
Expected: `RESULT: OK` (docs are not checked, this only confirms nothing else changed).

- [ ] **Step 8: Commit**

```bash
git add PROJECT_OVERVIEW.md tools/tests/README.md
git commit -m "docs: chaos shop" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Merge & verify (for the user)

- [ ] **1. Prepare the main worktree.** `config.lua` has an uncommitted local change (`DEVELOPMENT_MODE = true`). Stash it before merging, re-apply after: `git stash push game/scripts/vscripts/osc/config/config.lua` … `git stash pop` (A's edits are at lines 32-36, the local change at ~line 91 — the pop should apply cleanly).

- [ ] **2. Merge order** (on `stage-3-chaos-shop`): A, then B, then C. File sets are disjoint, so no conflicts are expected.

```bash
git merge --no-ff stage-3-chaos-shop-a
git merge --no-ff stage-3-chaos-shop-b
git merge --no-ff stage-3-chaos-shop-c
```

A first: from that point `run_tests.py` validates `osc_shop_*` keys, so the B merge immediately checks B's XML/JS keys against A's resource files.

- [ ] **3. Full test run:** `python tools/tests/run_tests.py` → `Localization: OK` (would print `used in code but missing in ...: osc_shop_...` on a key mismatch between B and A), `Lua tests: N passed, 0 failed`, `RESULT: OK`.

- [ ] **4. Leftover check:** `grep -rn "ANCHOR_COST\|ItemStockMax" game tools PROJECT_OVERVIEW.md` → no output.

- [ ] **5. In game** (Workshop Tools with bots, `DEVELOPMENT_MODE = true`; VScript console and mod log free of errors):
  - Button position next to the standard shop (tune `margin-*` of `#ChaosShopButton`/`#ChaosShopPanel` in `osc_hud.css`).
  - Panel: item icons with Dota tooltip on hover, names, prices, "Осталось N из 5" for the reroll only; "Купить" greyed out with too little gold.
  - Purchase at the fountain → item in inventory, gold reduced by `ItemCost`, `General.Buy` sound.
  - Purchase away from base and while dead → item in the stash, then delivered by the courier.
  - Inventory + backpack full at the fountain → item in stash, own items stay in place.
  - Sixth reroll for one team → "Товар закончился"; the other team still has 5.
  - Items no longer appear in the standard shop search.
  - Item is sellable back in the shop; the log has no `Chaos shop: no ItemCost` (otherwise apply the `GetItemCost` fallback from Workstream A).
  - Reconnect and team shuffle: the panel shows the stock of the current team.

- [ ] **6. Clean up worktrees:** `git worktree remove ../one_spell-shop-a` (same for b, c) and delete the `-a/-b/-c` branches.
