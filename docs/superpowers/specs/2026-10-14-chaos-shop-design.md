# Хаос-лавка — дизайн

Дата: 2026-10-14. Ветка: `stage-3-chaos-shop`.

## Цель

Кастомные предметы режима (`item_osc_ultimate_reroll`, `item_osc_anchor`)
продаются в своей категории — «Хаос-лавке» с собственной кнопкой и панелью
в HUD, а не теряются в стандартном магазине Dota (вкладки стандартного
магазина фиксированы, своей вкладки там сделать нельзя).

## Решения (согласованы)

- Покупка как в обычном магазине: герой жив и в зоне базового магазина —
  предмет в инвентарь; иначе (вне зоны или мёртв) — в тайник, доставит
  курьер.
- Предметы продаются **только** в Хаос-лавке: в стандартном магазине их нет.
- Лимиты как сейчас: реролл ультимейта — 5 на команду за матч, «Якорь» —
  без лимита. Числа в конфиге.
- Открытие: кнопка в правом нижнем углу HUD рядом со стандартным магазином.

## Сервер

Новая система `game/scripts/vscripts/osc/systems/chaos_shop.lua`
(`OSC_ChaosShop`), флаг `CHAOS_SHOP_ENABLED`, инициализация через
`SafeInit("ChaosShop", OSC_ChaosShop)` в `osc/core/game_mode.lua`.
`require("osc/systems/chaos_shop")` — в `addon_game_mode.lua`, рядом с
остальными системами.

### Конфиг (`osc/config/config.lua`)

```lua
CHAOS_SHOP_ENABLED = true,
CHAOS_SHOP_ITEMS = {
    { name = "item_osc_ultimate_reroll", team_stock = 5 }, -- 5 на команду за матч
    { name = "item_osc_anchor" },                          -- без лимита
},
```

`ANCHOR_COST` и его комментарий удалить: значение нигде не читается, цена —
`ItemCost` в KV.

### KV (`game/scripts/npc/npc_items_custom.txt`)

У обоих предметов `ItemPurchasable "0"`. У реролла убрать `ItemStockMax` и
`ItemStockTime` — лимит держит сервер. `ItemCost` остаётся единственным
источником цены (сервер читает его через `GetItemCost(name)`).

### Покупка: событие `osc_shop_buy { item }`

1. `OSC_ClientCommands.Check` (`osc/core/client_commands.lua`): игрок
   существует, есть основной герой, `item` — строка из `CHAOS_SHOP_ITEMS`.
   Иначе отказ (в лог через `LogRefusal`, клиенту ничего не выдаём).
2. Проверки по порядку, при отказе золото не трогается:
   - механика выключена или товар выключен (`item_osc_anchor` при
     `ANCHOR_ENABLED = false`) → `osc_shop_err_disabled`;
   - у команды кончился сток → `osc_shop_err_no_stock`;
   - золота меньше `GetItemCost(item)` → `osc_shop_err_no_gold`;
   - некуда положить предмет → `osc_shop_err_no_space`.
3. Место: герой жив и `IsInRangeOfShop(DOTA_SHOP_HOME, true)` → инвентарь
   (если инвентарь и рюкзак полны — тайник). Иначе — свободный слот тайника
   (слоты `DOTA_STASH_SLOT_1`…`DOTA_STASH_SLOT_6`). Нет места — отказ.
4. Списание: `PlayerResource:SpendGold(playerID, cost, DOTA_ModifyGold_PurchaseItem)`
   со сверкой фактически списанного, как в `osc/systems/casino.lua`
   (`goldBefore - GetGold`). Не списалось полностью — вернуть списанное и
   отказать. Если предмет после списания выдать не удалось — вернуть золото.
5. Успех: уменьшить сток команды (если у товара есть `team_stock`),
   опубликовать net table, ответить клиенту.
6. Ответ клиенту: `osc_shop_result { ok = 1, item }` при успехе. Отказы из
   п. 2 — через существующее `osc_hud_error { message = <ключ> }`
   (`OSC_Notifications.PlayerEvent`) и `osc_shop_result { ok = 0, item, error }`.

### Состояние: net table `osc_state`, ключ `shop_<team>`

```lua
{ items = { [i] = { name = "...", cost = 3500, stock = 3, max = 5 } } }
```

`stock = -1`, `max = -1` — без лимита. Выключенные товары в список не
попадают. Публикуется для `DOTA_TEAM_GOODGUYS` и `DOTA_TEAM_BADGUYS` при
`Init` и после каждой успешной покупки команды. Сток хранится в
`OSC_ChaosShop` и переживает `script_reload`, как состояние других систем.

## Клиент (Panorama)

- Модуль `content/panorama/scripts/custom_game/osc_chaos_shop.js`
  (`OSC.ChaosShop`), подключается в `osc_hud.xml`, `Init` в `osc_hud.js`.
- Разметка в `osc_hud.xml`: кнопка `#ChaosShopButton` (правый нижний угол,
  рядом со стандартным магазином; отступы подгоняются в игре) и панель
  `#ChaosShopPanel` (`OSCSurface OSCChaos`). Панель стоит в XML перед
  `#ChoicePanel` и после `#CasinoPanel`. Стили — в `osc_hud.css`.
- Строка товара: `DOTAItemImage itemname=<name>` (стандартная подсказка
  Dota при наведении), название `#DOTA_Tooltip_ability_<name>`, цена,
  остаток «осталось N из M» (только если `max >= 0`), кнопка «Купить».
  Кнопка неактивна, если `Players.GetGold(local) < cost` или `stock == 0`
  — только подсказка, решает сервер.
- Данные — из `osc_state/shop_<team локального игрока>`, обновление по
  подписке на net table; золото — `Players.GetGold`, опрос через
  `OSC.Util.Loop`, пока панель открыта.
- Клик → `GameEvents.SendCustomGameEventToServer("osc_shop_buy", { item })`.
  `osc_shop_result` с `ok = 1` — звук покупки. Ошибки показывает
  существующий обработчик `osc_hud_error` (`osc_core.js`).
- Создание панелей — только через `$.CreatePanel` (у созданных из JS
  панелей нет `BCreateChildren`).

## Локализация

Новые ключи в `game/resource/addon_russian.txt` и `addon_english.txt`:
`osc_shop_button`, `osc_shop_title`, `osc_shop_buy`, `osc_shop_close`,
`osc_shop_stock` (с `{d:stock}` и `{d:max}`), `osc_shop_err_disabled`,
`osc_shop_err_no_stock`, `osc_shop_err_no_gold`, `osc_shop_err_no_space`.

## Тесты (`tools/tests/test_chaos_shop.lua`)

Офлайн на существующем harness (недостающие моки Dota API добавить в
`tools/tests/harness.lua`):

- успешная покупка у магазина: золото списано на `ItemCost`, предмет в
  инвентаре, сток команды уменьшился, net table обновлена;
- чужое имя предмета и нехватка золота: отказ, золото и сток не тронуты;
- сток кончился: отказ;
- не у магазина (или мёртв): предмет в тайнике;
- тайник полон: отказ без списания;
- `ANCHOR_ENABLED = false`: якоря нет в net table, покупка отклонена;
- `CHAOS_SHOP_ENABLED = false`: событие игнорируется.

## Документация

Раздел «Хаос-лавка» в `PROJECT_OVERVIEW.md` и строки конфига в таблице
настроек; убрать упоминание `ANCHOR_COST`.

## Проверить в игре

- Положение кнопки рядом со стандартным магазином.
- Выдача в тайник вне базы и доставка курьером.
- Предметов больше нет в поиске стандартного магазина.
