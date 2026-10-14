# Редкость способностей, расширение пула, Сфера хаоса, справка — дизайн

Дата: 2026-10-14. Ветка: `stage-4-rarity-sphere`. Версия после слияния — 1.3.0.

## Цель

Сделать каждую ротацию событием («мне повезло — легендарка!»), расширить
пул способностей, дать смысл Рошану в рамках режима и объяснить правила
новичкам.

## Решения (согласованы)

- Пул: +~40 основных способностей и +~20 ультимейтов, только «самостоятельные».
- Редкость влияет на шанс выпадения и оформление; сила способностей не меняется.
- Сфера хаоса: владелец при применении выбирает одно из двух —
  «Легендарный ультимейт» (выбор из трёх) или «Хаос врагам».
- Справка: только по кнопке «?» (без автопоказа; хранилища «уже видел»
  между матчами у кастомок нет).
- Реализация — три агента параллельно (см. «Раздача»).

Общие правила проекта (`game/todo.md`): числа и флаги — в конфиг, тексты — в
оба `addon_*.txt`, лог — `OSC_Logger`, уведомления — `OSC_Notifications`,
соседние системы друг друга не вызывают (общие сервисы `OSC_Abilities`,
`OSC_AbilitySelection`, `OSC_Notifications` — можно), перед коммитом
`python tools/tests/run_tests.py`.

---

## Часть 1. Редкость (агент А)

### Данные

Поле записи пула `rarity`: `"rare"` или `"legendary"`; нет поля — обычная
(`"common"`). Описание поля — в шапке `OSC_ABILITY_POOL` в
`osc/config/ability_pools.lua` рядом с описанием `tags`.

`OSC_ABILITY_RARITIES = { "common", "rare", "legendary" }` — в
`ability_pools.lua` рядом с `OSC_ABILITY_TAGS`.

### Конфиг (`osc/config/config.lua`)

```lua
-- Редкость способностей (поле rarity в ability_pools.lua): итоговый вес
-- записи = weight × ABILITY_RARITY_WEIGHT[редкость]. Выключено — все обычные.
ABILITY_RARITY_ENABLED = true,
ABILITY_RARITY_WEIGHT = { common = 4, rare = 2, legendary = 1 },
```

### Выбор (`osc/systems/ability_selection.lua`)

- `GetWeight(entry)` = `weight` (по умолчанию 4) × множитель редкости, если
  `ABILITY_RARITY_ENABLED`; иначе как сейчас. Множитель — целое ≥ 1; неверное
  значение в конфиге — `OSC_Logger.Error` и множитель 1.
- `OSC_AbilitySelection.GetRarity(entry)` → `"common" | "rare" | "legendary"`
  (с учётом флага: выключено — всегда `"common"`). Публичная: её читают
  клиентские публикации и Сфера.
- `ValidatePools`: запись с `rarity` не из `OSC_ABILITY_RARITIES` убирается с
  причиной `invalid rarity <x>` (как неверные теги).
- `PickCandidates(hero, slot, count, opts)`: новое `opts.rarity` — строка;
  если задана, в кандидаты идут только записи этой редкости. Если таких
  меньше `count`, недостающие добираются **без** фильтра редкости тем же
  взвешенным выбором (без повторов). Сигнатура фиксирована — на неё опирается
  агент В.

### Клиент: выбор из трёх

- `rotation_choice.lua` `ClientOptions`: каждому варианту добавить
  `rarity = GetRarity(entry)`.
- `osc_rotation_choice.js` / CSS: карточке класс `RarityRare` или
  `RarityLegendary`. Рамка: редкая — синяя `#4B8BFF`, легендарная — золотая
  `#FFC23A` с мягким пульсирующим свечением. Обычная — без изменений.

### Объявление легендарки

- Новый тип уведомления `legendary_ability` в `osc/config/notifications.lua`:
  `feed` с `scope` для всех, цвет золотой, токен
  `#osc_notify_legendary_ability` (`{s:player}` получил легендарную
  способность `{s:ability}`!); `particle` — эффект над героем (можно
  `hero_levelup` или любой стандартный «золотой» эффект); звук через HUD-событие.
- Вызов: обёртка `OSC_Notifications.LegendaryAbility(hero, entry)`;
  вызывается из `OSC_Abilities` в точке фактической выдачи (`ApplyGive`,
  включая отложенную выдачу), если `GetRarity(entry) == "legendary"`.
  Стартовая способность при появлении героя тоже объявляется.
- HUD: на `osc_ability_changed` (уже есть) — передать `rarity`, чтобы
  всплывающее окно новой способности тоже получило рамку.

### Разметка текущего пула

Проставить `rarity` существующим записям: ~15% легендарных, ~30% редких.
Ориентиры. Легендарные ульты: `tidehunter_ravage`,
`magnataur_reverse_polarity`, `earthshaker_echo_slam`,
`necrolyte_reapers_scythe`, `juggernaut_omni_slash`, `bane_fiends_grip`.
Легендарные основные: `pudge_meat_hook`, `puck_illusory_orb`,
`antimage_blink`. Остальное — по усмотрению агента с одной строкой
обоснования в описании коммита.

### Тесты (`tools/tests/test_rarity.lua`)

- вес = weight × множитель; флаг выключен — множитель не применяется;
- неверная редкость убирается `ValidatePools`;
- `opts.rarity` отдаёт только записи редкости; при нехватке добирает из остальных без повторов;
- `ClientOptions` содержит `rarity`;
- выдача легендарки вызывает `LegendaryAbility`, обычной — нет.

---

## Часть 2. Расширение пула (агент Б)

### Отбор

+~40 записей в `OSC_ABILITY_POOL`, +~20 в `OSC_ULTIMATE_POOL`, у каждой
`name`, `hero`, `label`, `tags`, `rarity` (кроме обычных).

Не брать:
- формы и превращения (Metamorphosis, True Form, Chemical Rage и т. п.);
- переключатели и способности с парной активацией без `linked`
  (если пара нужна — оформить `linked`, как `puck_illusory_orb`);
- способности, зависящие от других родных способностей или ресурсов героя
  (Invoker, Earth Spirit, Meepo, стаки Bristleback/Slark и т. п.);
- управляемые призывы (Lone Druid, Visage, Broodmother spiderlings и т. п.);
- глобальные телепорты и способности, ломающие карту/фонтан.

Сомнительные — не в пул, а в `game/todo.md` раздел «Кандидаты в пул — на
проверку» с причиной.

Имена способностей сверять с KV игры (папка Dota
`game/dota/pak01_dir.vpk` — индекс имён; или `scripts/npc/npc_abilities.txt`
если доступен). Неверное имя не уронит игру — `ValidatePools` уберёт его с
ошибкой в логе, — но такой записи быть не должно.

### Прекэш

Каждый новый `hero` прекэшируется целиком (`addon_game_mode.lua`,
`PrecacheUnitByNameSync`). Агент считает число уникальных героев в пулах до
и после и пишет в отчёт. Замер времени загрузки — ручная проверка в игре
(см. ниже); если загрузка заметно выросла, это отдельная задача (прекэш
только частиц/звуков), в эту ветку не входит.

### Тесты

Существующие тесты проходят; добавить в `test_tags.lua` (или новый файл)
проверку, что у всех записей пулов теги и редкость валидны и имена не повторяются.

---

## Часть 3. Сфера хаоса (агент В)

### Конфиг

```lua
-- Сфера хаоса (osc/systems/chaos_sphere.lua): падает с Рошана, владелец
-- выбирает легендарный ультимейт (из CHAOS_SPHERE_ULTIMATE_CHOICES) или
-- новую случайную способность всем врагам
CHAOS_SPHERE_ENABLED = true,
CHAOS_SPHERE_ULTIMATE_CHOICES = 3,
CHAOS_SPHERE_MIN_LEVEL = 6,       -- для варианта «ультимейт»
```

### Предмет (`npc_items_custom.txt`, `osc/items/item_chaos_sphere.lua`)

`item_osc_chaos_sphere`: `item_lua`, `DOTA_ABILITY_BEHAVIOR_NO_TARGET`,
`ItemPurchasable "0"`, `ItemCost "0"`, `ItemSellable "0"`,
`ItemShareability "ITEM_NOT_SHAREABLE"`, `ItemDroppable "0"`, иконка из
стандартных (например `item_aghanims_shard` или `item_refresher_shard`),
`ItemInitialCharges "1"`. `OnSpellStart` вызывает
`OSC_ChaosSphere.Offer(hero, item)` — сам ничего не выдаёт.

### Система (`osc/systems/chaos_sphere.lua`, `OSC_ChaosSphere`)

`SafeInit("ChaosSphere", OSC_ChaosSphere)` в `game_mode.lua`, `require` в
`addon_game_mode.lua`, флаг `CHAOS_SPHERE_ENABLED`.

**Выпадение.** `ListenToGameEvent("entity_killed", ...)` (как в
`stats.lua`): убит юнит с `GetUnitName() == "npc_dota_roshan"` →
`CreateItem("item_osc_chaos_sphere", nil, nil)` +
`CreateItemOnPositionSync(позиция Рошана + небольшое смещение)`; объявление
всем (`chaos_sphere_dropped`).

**Предложение.** `Offer(hero, item)`:
- только основной герой (`OSC_Heroes.IsMainHero`), иначе отказ;
- кандидаты ультимейта: `OSC_AbilitySelection.PickCandidates(hero,
  "ultimate", CHAOS_SPHERE_ULTIMATE_CHOICES, { rarity = "legendary" })`
  (до слияния агента А `opts.rarity` игнорируется — это нормально);
- состояние в `OSC_HeroState.Get(hero).sphere_offer = { item = entindex
  предмета, options = { имена }, ultimate_allowed = level >= MIN_LEVEL }`;
- игроку событие `osc_sphere_offer { options = [{name,label,rarity}],
  ultimate_allowed }`.

**Выбор: событие `osc_sphere_pick { mode, ability }`.**
`OSC_ClientCommands.Check` (`hero = true`, `mode` — `OneOf({"ultimate",
"enemies", "cancel"})`). Затем:
- нет `sphere_offer` или предмет больше не в инвентаре героя → отказ в лог;
- `cancel` → `sphere_offer = nil`, сфера остаётся;
- `ultimate`: `ultimate_allowed` и `ability` ∈ `options` → `OSC_Abilities.Give(hero,
  "ultimate", entry, true)`; при успехе предмет удаляется;
- `enemies`: каждому основному герою вражеских команд (`OSC_Heroes.ForEachPlayerHero`)
  без `anchored` → `OSC_Abilities.GiveRandom(enemy, true)`; «Якорь» не тратится;
  предмет удаляется; объявление всем `chaos_sphere_enemies` с именем игрока.
- Отказы — `OSC_ClientCommands.LogRefusal`, клиенту `osc_hud_error` с
  ключом `osc_sphere_err_*` (низкий уровень, нет предмета).

### Клиент

Окно `#ChaosSpherePanel` в HUD (новый `osc_chaos_sphere.js` + разметка и стили
в `osc_hud.xml/css`, по образцу выбора из трёх): заголовок, две кнопки-режима;
после «Легендарный ультимейт» — три карточки (с рамкой редкости — классы
агента А, до слияния без них), «Отмена». Кнопка ультимейта неактивна, если
`ultimate_allowed = false`, с подсказкой.

### Тесты (`tools/tests/test_chaos_sphere.lua`)

- смерть Рошана создаёт предмет, другого юнита — нет; флаг выключен — нет;
- `Offer` пишет состояние и шлёт событие; не основной герой — отказ;
- `ultimate`: вариант не из списка / уровень ниже — отказ, предмет цел;
  верный — `Give` вызван, предмет удалён;
- `enemies`: выдача всем врагам кроме anchored, союзникам — нет; предмет удалён;
- `cancel` и повторный pick без offer.

Моки — в `tools/tests/harness.lua` (по образцу `test_chaos_shop.lua`).

---

## Часть 4. Справка «?» (агент Б)

- Кнопка `#HelpButton` «?» рядом с `#ChaosShopButton` (`osc_hud.xml/css`),
  панель `#HelpPanel` с прокруткой, кнопка закрытия; повторное нажатие «?» —
  закрыть. Логика — `osc_help.js` (`OSC.Help { Init, Toggle }`), подключить в
  `osc_hud.xml`, `Init` из `osc_hud.js`.
- Разделы (заголовок + 1–3 предложения, ключи `osc_hud_help_*`): Ротация и
  выбор из трёх; Якорь; Редкость; Хаос-раунды; Хаос-лавка; Казино Огра;
  Сфера хаоса. Тексты не дублируют числа из конфига, кроме общеизвестных.
- Только клиент; сервер не меняется.

---

## Локализация

Все новые ключи в обоих `addon_russian.txt` / `addon_english.txt`; новые
префиксы `osc_sphere_`, `osc_notify_legendary_`, `osc_hud_help_` — добавить в
`LOC_PREFIXES` в `tools/tests/run_tests.py`, имена событий (`osc_sphere_offer`,
`osc_sphere_pick`) — в `NOT_LOC_KEYS`.

## Раздача и слияние

| Агент | Часть | Основные файлы |
|---|---|---|
| А | 1. Редкость | `ability_selection.lua`, `rotation_choice.lua`, `abilities.lua`, `notifications*.lua`, `osc_rotation_choice.js`, CSS выбора, `config.lua`, разметка `rarity` в текущих записях пула |
| Б | 2. Пул + 4. Справка | новые записи в `ability_pools.lua`, `osc_help.js`, `osc_hud.xml/css` (кнопка/панель), `todo.md` |
| В | 3. Сфера хаоса | `chaos_sphere.lua`, `item_chaos_sphere.lua`, `npc_items_custom.txt`, `osc_chaos_sphere.js`, `osc_hud.xml/css` (окно), `game_mode.lua`, `addon_game_mode.lua` |

Пересечения: `ability_pools.lua` (А — поле у старых записей, Б — новые
записи в конце списков), `osc_hud.xml/css` (Б и В — разные блоки),
`config.lua`, локализация, `run_tests.py`. Порядок слияния: А → Б → В,
конфликты разрешает координатор. Каждый агент: своя ветка от
`stage-4-rarity-sphere`, тесты зелёные, отчёт — что сделано и что проверить в игре.

## Документация

`PROJECT_OVERVIEW.md`: разделы «Редкость», «Сфера хаоса», «Справка», таблица
конфига. Версия 1.3.0 — после приёмки в игре, отдельным коммитом.

## Проверить в игре

1. Выбор из трёх: рамки редкости; легендарка — объявление всем и звук.
2. Новые способности: несколько ротаций с `-reroll`, ошибки `ValidatePools` в логе; время загрузки до/после.
3. Рошан: сфера падает рядом с Аегисом; оба режима; отмена; уровень < 6.
4. «?»: открывается/закрывается, тексты на двух языках.
