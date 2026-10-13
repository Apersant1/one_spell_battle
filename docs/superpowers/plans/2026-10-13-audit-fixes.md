# Исправления по аудиту — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Исправить проблемы, найденные аудитом 2026-10-13: непереведённые ключи, небезопасная замена способностей, рассинхрон копий героя, слабые места казино/курьеров/погоды, остатки шаблона и устаревшая документация.

**Architecture:** Правки точечные, в рамках существующих модулей `OSC_*`. Новая логика способностей (связанные подспособности, проверка пулов, синхронизация копий) живёт в `osc/systems/abilities.lua`. Для проверки добавляется офлайн-набор тестов на LuaJIT (через Python `lupa`) с моками Dota API в `tools/tests/` — в игру он не попадает.

**Tech Stack:** Dota 2 VScript (LuaJIT 2.1), Panorama JS/XML/CSS, KV-файлы локализации, Python 3 + `lupa` для тестов, `node --check` для синтаксиса JS.

**Spec:** отчёт аудита в переписке (2026-10-13) + правила `game/todo.md` («Общие правила для исполнителя»).

## Global Constraints

- Все числа — в `osc/config/config.lua`, не в коде.
- Новые тексты — в `game/resource/addon_russian.txt` и `addon_english.txt`; в HUD — `$.Localize`, а не готовые строки.
- Логирование — только `OSC_Logger`, уведомления — только `OSC_Notifications`.
- Существующее поведение не ломать; `DEVELOPMENT_MODE` в коммитах остаётся `false`.
- Отдельная ветка, каждый этап — отдельный коммит.
- Не трогать без решения владельца: Git LFS, перенос репозитория из OneDrive, удаление карт/текстур, значение `CASINO_ACCESS`.

## Review Focus

- Новая способность не добавилась (`AddAbility` вернул nil) — у героя должна остаться старая. Тест: `give_random_keeps_old_when_add_fails`.
- Ротация у героя с постоянными копиями (клоны Meepo) — копии получают ту же способность. Тест: `sync_copies_updates_clone`.
- Способность из пула отсутствует в KV (патч Dota её удалил) — исключается при старте, а не ломает выдачу. Тест: `validate_removes_unknown`.
- Мёртвый герой пытается крутить автомат — отказ с переведённой ошибкой. Тест: `spin_refused_when_dead`.
- Отложенный удар погоды после досрочного конца раунда — не срабатывает. Тест: `after_skips_when_round_changed`.

---

### Task 1: Офлайн-тесты и проверки

**Files:**
- Create: `tools/tests/run_tests.py` — раннер: синтаксис всех `.lua` (компиляция LuaJIT), `node --check` всех `.js`, сверка локализации, запуск `test_*.lua` (каждый тест в свежем рантайме).
- Create: `tools/tests/harness.lua` — моки Dota API: `Vector`, `class`, `RandomInt/RandomFloat` (детерминированные), `GameRules`, `PlayerResource`, `HeroList`, `CustomNetTables`, `CustomGameEventManager`, `GetAbilityKeyValuesByName`, фейковые герои/способности.
- Create: `tools/tests/README.md` — как запустить (`pip install lupa`, `python tools/tests/run_tests.py`).

Проверка локализации: ключи с префиксами `osc_casino_err_`, `osc_casino_result_`, `osc_casino_items_`, `osc_hud_`, `osc_notify_`, `osc_ts_`, найденные в строковых литералах Lua/JS/XML, должны быть в обоих файлах; наборы ключей ru и en совпадают.

- [ ] Step 1: Написать раннер и harness.
- [ ] Step 2: Запустить — ожидается FAIL локализации (`osc_casino_err_bad_item`, `osc_casino_err_item_not_yours`, `osc_casino_err_item_unsellable`, расхождение ru/en).
- [ ] Step 3: Коммит `test: add offline Lua/JS checks with Dota API mocks`.

### Task 2: Локализация и тексты HUD

**Files:**
- Modify: `game/resource/addon_russian.txt`, `game/resource/addon_english.txt` — недостающие ключи казино (`bad_item`, `item_not_yours`, `item_unsellable`, `dead`, `items_empty`; в en — `too_far`, `wrong_team`, `owner_only`), ключи HUD (`osc_hud_timer_pregame`, `osc_hud_timer_next`, `osc_hud_chaos_header`, `osc_hud_chaos_waiting`, `osc_hud_chaos_active_fallback`, `osc_hud_chaos_soon_fallback`, `osc_hud_chaos_soon_desc`, `osc_hud_chaos_time_left`, `osc_hud_chaos_time_until`, `osc_hud_popup_title`); описание казино — «играть может любой герой рядом» (соответствует `CASINO_ACCESS = "all"`).
- Modify: `content/panorama/scripts/custom_game/osc_timer.js` — тексты через `$.Localize`, длительность цикла из `data.interval`.
- Modify: `game/scripts/vscripts/osc/systems/rotation.lua` — `PublishTimer` пишет `interval = OSC_CONFIG.ROTATION_INTERVAL`.
- Modify: `content/panorama/scripts/custom_game/osc_chaos_round.js`, `content/panorama/layout/custom_game/osc_hud.xml` — запасные тексты через ключи.
- Modify: `content/panorama/scripts/custom_game/osc_ability_popup.js` — заголовок через ключ, имя способности из `#DOTA_Tooltip_Ability_<name>` с запасным `label`.
- Modify: `osc_hud.xml` + `osc_hud.css` — добавить `#CasinoItemsEmpty` и правило `.Hidden` для него.
- Modify: `content/panorama/scripts/custom_game/osc_casino.js` — баланс обновляется опросом `Players.GetGold` пока окно открыто и спина нет.

- [ ] Step 1: Внести правки.
- [ ] Step 2: `python tools/tests/run_tests.py` — проверки локализации и `node --check` проходят.
- [ ] Step 3: Коммит `fix: localize HUD texts and missing casino errors`.

### Task 3: Безопасная замена способностей, связанные подспособности, копии, проверка пулов

**Files:**
- Modify: `game/scripts/vscripts/osc/systems/abilities.lua`
- Modify: `game/scripts/vscripts/osc/systems/hero_lifecycle.lua`
- Modify: `game/scripts/vscripts/osc/config/ability_pools.lua` — поле `linked`.
- Modify: `game/scripts/vscripts/osc/core/game_mode.lua` — вызов `OSC_Abilities.ValidatePools()` до инициализации систем.
- Test: `tools/tests/test_abilities.lua`

**Interfaces (Produces):**
- `OSC_Abilities.ValidatePools() -> removedCount:number` — удаляет из `OSC_ABILITY_POOL`/`OSC_ULTIMATE_POOL` записи, которых нет в KV или с неверным `weight`; из `linked` — отсутствующие подспособности.
- `OSC_Abilities.IsCopy(unit) -> boolean` — иллюзия / Tempest Double / клон.
- `OSC_Abilities.SyncCopies(owner)` — пересобирает способности всех копий владельца (`HeroList`, тот же `GetPlayerOwnerID`).
- `OSC_Abilities.SetEntryLevel(hero, name, level)` — уровень способности и её `linked`, не ниже текущего.
- Запись пула: `{ name, hero, label, weight?, linked? = { { name, hidden? } } }`.

Поведение:
- `GiveRandom`: выбрать → `AddAbility(new)`; при неудаче — лог, старая остаётся, возврат `nil`. Иначе удалить старую (прервать ченнел, выключить тоггл, удалить её `linked`), поставить новую в слот 0, добавить `linked` в свободные слоты 2–4, `EndCooldown`, уведомить, `SyncCopies`.
- `GiveRandomUltimate`: тот же порядок, слот 5, `SyncCopies`.
- `CopyFromOwner`: копирует и `linked`.
- `OnPlayerLevelUp`: пропускает неинициализированных героев, обёрнут в `pcall`, использует `SetEntryLevel` и затем `SyncCopies`.
- `linked` в пулах: `puck_illusory_orb → puck_ethereal_jaunt`, `bane_nightmare → bane_nightmare_end (hidden)`, `crystal_maiden_freezing_field → crystal_maiden_freezing_field_stop (hidden)`; если имени нет в KV — `ValidatePools` убирает его с записью в лог.

Тесты: `validate_removes_unknown`, `validate_drops_missing_linked`, `give_random_keeps_old_when_add_fails`, `give_random_adds_linked`, `give_random_removes_old_linked`, `sync_copies_updates_clone`, `toggle_turned_off_before_removal`.

- [ ] Step 1: Написать тесты, убедиться, что падают.
- [ ] Step 2: Реализовать.
- [ ] Step 3: Тесты проходят.
- [ ] Step 4: Коммит `fix: safe ability swap, linked sub-abilities, copy sync, pool validation`.

### Task 4: Казино (сервер)

**Files:**
- Modify: `game/scripts/vscripts/osc/systems/casino.lua`
- Modify: `game/scripts/vscripts/osc/core/commands.lua` — `-casino <symbol|off>` под `DEVELOPMENT_MODE`.
- Test: `tools/tests/test_casino.lua`

**Interfaces (Produces):**
- `OSC_Casino.ValidateOutcomes(outcomes) -> ok:boolean, errOrEv` — шанс — целое > 0, множитель ≥ 0, символ из `circle/diamond/star/seven`, без повторов, сумма шансов ≤ 100; при успехе второе значение — ожидание выплаты (доля ставки).

Поведение: `CanUseMachine` отказывает мёртвому (`osc_casino_err_dead`); `SpawnMachine` не вызывает `GetPlayer(nil)`; `Init` логирует EV или ошибку конфига; список символов для проигрышных барабанов — общая константа.

Тесты: `validate_outcomes_current_config_ev` (0.90), `validate_outcomes_rejects_over_100`, `validate_outcomes_rejects_unknown_symbol`, `spin_refused_when_dead`.

- [ ] Step 1: Тесты → FAIL. Step 2: реализация. Step 3: PASS. Step 4: коммит `fix: casino dead-player check, outcome validation, dev -casino command`.

### Task 5: Курьеры, погода, перемешивание команд

**Files:**
- Modify: `game/scripts/vscripts/osc/systems/couriers.lua` — `OSC_Couriers.GetHomePositions(origin, forward, right, count)` на N курьеров (первые две позиции как раньше, далее ряды через `HOME_ROW_SPACING`); мёртвый курьер ничего не делает.
- Modify: `game/scripts/vscripts/osc/config/config.lua` — `COURIERS.HOME_ROW_SPACING = 200`.
- Modify: `game/scripts/vscripts/osc/systems/chaos_events/weather_common.lua` — `After` проверяет, что раунд тот же (`event` и `endTime`).
- Modify: `game/scripts/vscripts/osc/systems/team_shuffle.lua` — `OnMove` принимает только Radiant/Dire.
- Test: `tools/tests/test_misc.lua` — `home_positions_keep_first_two`, `home_positions_support_four`, `after_skips_when_round_changed`, `after_runs_when_round_same`, `team_move_rejects_unknown_team`.

- [ ] Step 1: Тесты → FAIL. Step 2: реализация. Step 3: PASS. Step 4: коммит `fix: courier robustness, weather delay guard, team move whitelist`.

### Task 6: Остатки шаблона и документация

**Files:**
- Modify: `game/scripts/vscripts/addon_game_mode.lua` — убрать `CAddonTemplateGameMode`.
- Modify: `game/scripts/npc/npc_abilities_custom.txt` — убрать `templar_assassin_refraction_holdout`.
- Modify: `game/scripts/npc/npc_units_custom.txt` — убрать `npc_dota_creature_gnoll_assassin`.
- Delete: пустая папка `scripts/` в корне (не в git).
- Modify: `PROJECT_OVERVIEW.md` — версия, ставка, исходы и EV казино, перезарядка, 6 хаос-событий, ставки предметами, «Заблудший» курьер, `-casino`, `linked`, проверка пулов, тесты.
- Modify: `game/todo.md` — отметить сделанное (проверка пулов из 2.3, выключение тоггла из 2.1, EV из 3.3).

- [ ] Step 1: Правки. Step 2: `run_tests.py` зелёный. Step 3: коммит `chore: remove template leftovers, sync docs`.

### Task 7: Финальная проверка

- [ ] `python tools/tests/run_tests.py` — всё зелёное, вывод приложить к отчёту.
- [ ] `git diff master --stat`, просмотр диффа целиком.
- [ ] Перечислить, что нужно проверить вручную в Dota (подспособности, Meepo, курьеры, локализация HUD на английском клиенте).
