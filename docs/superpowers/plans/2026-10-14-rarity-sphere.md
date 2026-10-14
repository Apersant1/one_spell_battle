# Редкость, расширение пула, Сфера хаоса, справка — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Цель:** у способностей появляется редкость (шанс + рамка + объявление легендарки), пул расширяется на ~40 основных и ~20 ультимейтов, с Рошана падает Сфера хаоса (легендарный ультимейт на выбор или хаос врагам), в HUD появляется справка «?».

**Архитектура:** три независимых трека в трёх worktree. A меняет общий сервис выбора (`OSC_AbilitySelection`: вес × множитель редкости, фильтр `opts.rarity`) и точку выдачи (`OSC_Abilities` → `OSC_Notifications.LegendaryAbility`), плюс рамки в Panorama. B дописывает записи в конец пулов и делает чисто клиентскую панель справки. C добавляет систему `OSC_ChaosSphere` (выпадение по `entity_killed`, предложение, выбор по клиентской команде) с предметом и окном HUD; от A он зависит только сигнатурой `PickCandidates(..., { rarity = "legendary" })`, которая до слияния просто игнорируется.

**Стек:** Dota 2 VScript Lua (LuaJIT), Panorama JS/XML/CSS, KV, офлайн-тесты на lupa (`tools/tests/run_tests.py`).

**Спек:** `docs/superpowers/specs/2026-10-14-rarity-sphere-design.md` (утверждён). Исполнитель читает спек и свой трек этого плана; чужие треки читать не нужно.

## Модель исполнения

Три исполнителя работают **параллельно**, каждый в своём git worktree от текущего HEAD ветки `stage-4-rarity-sphere`. Владение файлами разнесено так, что пересечения есть только в известных местах (см. «Слияние»), и каждый трек вставляет код в свои, разные места этих файлов.

Создание worktree (один раз, координатор, из корня репозитория, Git Bash):

```bash
git worktree add ../one_spell-rarity-a -b stage-4-rarity-sphere-a stage-4-rarity-sphere
git worktree add ../one_spell-rarity-b -b stage-4-rarity-sphere-b stage-4-rarity-sphere
git worktree add ../one_spell-rarity-c -b stage-4-rarity-sphere-c stage-4-rarity-sphere
```

Все команды трека выполняются из корня **своего** worktree. Ветку не пушить, в другие ветки не коммитить.

## Global Constraints

- Перед правками прочитать затрагиваемые файлы целиком (`game/todo.md`, «Правила»).
- Все числа и флаги — в `game/scripts/vscripts/osc/config/config.lua`; конфиг читается только через `OSC_Config.Get("PATH")` / `OSC_Config.Get("A.B")` в момент использования (это проверяет `run_tests.py`, «Config reads»). Тесты могут писать `OSC_CONFIG.X = ...` напрямую.
- Все новые тексты — в обоих `game/resource/addon_russian.txt` (два таба отступа) и `game/resource/addon_english.txt` (три таба), в HUD — через `$.Localize`. Наборы ключей ru/en обязаны совпадать.
- Лог — только `OSC_Logger.Log` / `OSC_Logger.Error`; уведомления — только `OSC_Notifications` (`Notify`, `PlayerEvent`, обёртки).
- Системы не вызывают соседние системы; общие сервисы `OSC_Abilities`, `OSC_AbilitySelection`, `OSC_Notifications`, `OSC_ClientCommands`, `OSC_Heroes`, `OSC_HeroState`, `OSC_Anchor` — можно.
- Таблица модуля переживает `script_reload`: `OSC_X = OSC_X or { ... }`.
- Новое поле состояния героя — только через `FIELDS` в `osc/core/hero_state.lua`.
- Panorama: панели из JS — только `$.CreatePanel(type, parent, id)` (у таких панелей нет `BCreateChildren`); `@font-face` не поддерживается — не использовать; каждая частица — `ParticleManager:ReleaseParticleIndex`.
- **Кодировка (Windows):** файлы с кириллицей правятся только инструментами Edit/Write. Никаких bash heredoc, `echo`, `python -c`/stdin, `sed -i` с кириллицей — это портит кодировку. `sed` допустим только для ASCII-шаблонов. Сохранять отступы файла: 4 пробела в Lua, 2 в JS/CSS, табы в `addon_*.txt` и `npc_items_custom.txt`.
- `DEVELOPMENT_MODE = false` в `config.lua` не трогать и никогда не коммитить `true`.
- Перед **каждым** коммитом: `python tools/tests/run_tests.py` → `RESULT: OK`. Базовая линия на старте: `Lua tests: 171 passed, 0 failed`.
- Комментарии в коде — по-русски, в стиле соседнего кода. Сообщения коммитов — по-английски, conventional style, последней строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (через второй `-m`).
- Ничего не пушить.
- В конце трека — отчёт координатору: что сделано, список изменённых файлов, что проверить вручную в игре.

## Review Focus

1. **Редкость, которой в пуле мало или нет** (ультимейтов-легендарок меньше `CHAOS_SPHERE_ULTIMATE_CHOICES`, `ABILITY_RARITY_ENABLED = false`) → `PickCandidates` с `opts.rarity` добирает недостающих без фильтра, без повторов и без ошибки. Тесты A: `rarity_filter_fills_without_duplicates`, `rarity_filter_without_matches_still_picks`.
2. **Легендарка, выданная с отсрочкой фазы каста** → объявление уходит один раз, в момент фактической выдачи, а не в момент запроса. Тест A: `deferred_legendary_announced_once`.
3. **Неверный множитель редкости в конфиге** (0, дробь, строка) → множитель 1 и **одна** строка ошибки в логе, а не по строке на каждый взвешенный выбор. Тест A: `bad_multiplier_logged_once`.
4. **Сфера уже не в инвентаре в момент выбора** (переложена в тайник, продана через консоль, игрок применил и выкинул) → отказ, способность не выдана. Тест C: `pick_without_item_refused`.
5. **Подделанный выбор сферы** (вариант не из предложения, мусорный `mode`, повторный pick после отмены) → отказ в лог, предмет цел, ничего не выдано. Тесты C: `ultimate_not_offered_refused`, `forged_mode_refused`, `cancel_keeps_item`.

---

## Трек A — Редкость (Часть 1 спека)

### Владение файлами трека A

Только эти файлы:

- `game/scripts/vscripts/osc/config/config.lua` — блок после `ROTATION_CHOICE_COUNT = 3,`
- `game/scripts/vscripts/osc/config/ability_pools.lua` — шапка, `OSC_ABILITY_RARITIES`, поле `rarity` у **существующих** записей (кроме последней записи каждого пула — см. A5)
- `game/scripts/vscripts/osc/config/notifications.lua` — тип `legendary_ability` в разделе «Способности»
- `game/scripts/vscripts/osc/core/notifications.lua` — `AbilityChanged` (+ `rarity`), новая `LegendaryAbility`
- `game/scripts/vscripts/osc/systems/ability_selection.lua`
- `game/scripts/vscripts/osc/systems/abilities.lua` — только `ApplyGive`
- `game/scripts/vscripts/osc/systems/rotation_choice.lua` — `ClientOptions` и шапка
- `content/panorama/scripts/custom_game/osc_rotation_choice.js`, `osc_ability_popup.js`, `osc_core.js`
- `content/panorama/styles/custom_game/osc_hud.css` — только раздел «Выбор следующей способности» и блок `#PopupIcon`
- `game/resource/addon_russian.txt`, `addon_english.txt` — одна строка после `osc_notify_ability_changed`
- Создать: `tools/tests/test_rarity.lua`

`run_tests.py` и `harness.lua` трек A **не меняет**: префикс `osc_notify_` уже в `LOC_PREFIXES`.

### Контракт трека A (на него опираются B, C и координатор)

| Что | Значение |
| --- | --- |
| Поле записи | `rarity = "rare"` или `"legendary"`; нет поля — обычная; `"common"` явно — тоже допустимо |
| Список | `OSC_ABILITY_RARITIES = { "common", "rare", "legendary" }` в `ability_pools.lua` |
| Конфиг | `ABILITY_RARITY_ENABLED = true`, `ABILITY_RARITY_WEIGHT = { common = 4, rare = 2, legendary = 1 }` |
| `OSC_AbilitySelection.GetRarity(entry)` | `"common" \| "rare" \| "legendary"`; флаг выключен или `entry == nil` → `"common"` |
| `OSC_AbilitySelection.GetWeight(entry)` | `(entry.weight or 4) × множитель`; ошибка при неверном `weight` (как сейчас) |
| `PickCandidates(hero, slot, count, opts)` | новое `opts.rarity` (строка): сначала только эта редкость, недостающие — без фильтра, без повторов |
| Клиент выбора из трёх | `options[i] = { name, label, rarity }` в событии и net table `choice_<id>` |
| HUD-событие | `osc_ability_changed { ability, label, rarity, player_id }` |
| Уведомление | тип `legendary_ability`, токен `#osc_notify_legendary_ability`, обёртка `OSC_Notifications.LegendaryAbility(hero, entry)` |
| CSS-классы | `.ChoiceCard.RarityRare`, `.ChoiceCard.RarityLegendary` (их же наденет на свои карточки трек C), `#PopupCard.RarityRare`, `#PopupCard.RarityLegendary` |

### Task A1: Конфиг, список редкостей, вес и редкость записи

**Files:**
- Modify: `game/scripts/vscripts/osc/config/config.lua` (после строки 28 `ROTATION_CHOICE_COUNT = 3,`)
- Modify: `game/scripts/vscripts/osc/config/ability_pools.lua:19-32`
- Modify: `game/scripts/vscripts/osc/systems/ability_selection.lua:17, 65-71, 296-312`
- Create: `tools/tests/test_rarity.lua`

**Interfaces:**
- Produces: `OSC_ABILITY_RARITIES`, конфиг `ABILITY_RARITY_ENABLED`, `ABILITY_RARITY_WEIGHT`, `OSC_AbilitySelection.GetRarity(entry)`, `OSC_AbilitySelection.GetWeight(entry)`.

- [ ] **Step 1: Написать падающие тесты**

Создать `tools/tests/test_rarity.lua` (Write tool):

```lua
-- Редкость способностей: вес, проверка пулов, фильтр кандидатов, клиент,
-- объявление легендарки

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/rotation_choice")
end

-- Теги разные, чтобы правило серии тегов не вмешивалось в выбор
local TAGS = { "damage", "disable", "mobility", "passive", "support" }
local tagIndex = 0

local function entry(name, rarity, weight)
    H.DefineAbility(name)
    tagIndex = tagIndex % #TAGS + 1
    return { name = name, hero = "npc_dota_hero_axe", label = name,
        tags = { TAGS[tagIndex] }, rarity = rarity, weight = weight }
end

local function heroWith(name)
    local hero = H.NewHero({ abilities = { name }, level = 3 })
    H.AddPlayer(0, hero)
    local state = OSC_HeroState.Get(hero)
    state.ability = name
    state.initialized = true
    return hero
end

local function countLogs(pattern)
    local count = 0
    for _, line in ipairs(H.logs) do
        if string.find(line, pattern, 1, true) then count = count + 1 end
    end
    return count
end

return {
    weight_multiplied_by_rarity = function()
        setup()
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_c")), 16, "common: 4 x 4")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_r", "rare")), 8, "rare: 4 x 2")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_l", "legendary")), 4, "legendary: 4 x 1")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_l2", "legendary", 2)), 2, "own weight kept")
        H.eq(OSC_AbilitySelection.GetRarity(entry("test_r2", "rare")), "rare", "rarity read")
        H.eq(OSC_AbilitySelection.GetRarity(entry("test_c2")), "common", "no field = common")
        H.eq(OSC_AbilitySelection.GetRarity(nil), "common", "nil entry = common")
    end,

    flag_off_ignores_rarity = function()
        setup()
        OSC_CONFIG.ABILITY_RARITY_ENABLED = false
        local legendary = entry("test_l", "legendary")
        H.eq(OSC_AbilitySelection.GetWeight(legendary), 4, "no multiplier")
        H.eq(OSC_AbilitySelection.GetRarity(legendary), "common", "everything common")
    end,

    bad_multiplier_logged_once = function()
        setup()
        OSC_CONFIG.ABILITY_RARITY_WEIGHT = { common = 4, rare = 0, legendary = 1.5 }
        local rare = entry("test_r", "rare")
        H.eq(OSC_AbilitySelection.GetWeight(rare), 4, "bad multiplier -> 1")
        H.eq(OSC_AbilitySelection.GetWeight(rare), 4, "still 1")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_l", "legendary")), 4, "fraction -> 1")
        H.eq(countLogs("ABILITY_RARITY_WEIGHT.rare"), 1, "rare error logged once")
        H.eq(countLogs("ABILITY_RARITY_WEIGHT.legendary"), 1, "legendary error logged once")
    end,
}
```

- [ ] **Step 2: Запустить тесты — убедиться, что падают**

Run: `python tools/tests/run_tests.py`
Expected: `FAIL test_rarity.weight_multiplied_by_rarity: ... attempt to call field 'GetWeight' (a nil value)` и так же два других; остальное PASS; `RESULT: FAIL (3 problems)`.

- [ ] **Step 3: Конфиг**

В `config.lua` после строки `    ROTATION_CHOICE_COUNT = 3,` вставить (Edit tool):

```lua
    -- Редкость способностей (поле rarity в ability_pools.lua): итоговый вес
    -- записи = weight × ABILITY_RARITY_WEIGHT[редкость]. Выключено — все обычные.
    ABILITY_RARITY_ENABLED = true,
    ABILITY_RARITY_WEIGHT = { common = 4, rare = 2, legendary = 1 },
```

- [ ] **Step 4: Шапка пула и список редкостей**

В `ability_pools.lua` после строки `-- MAX_SAME_TAG_STREAK в config.lua).` (строка 24) вставить:

```lua
-- rarity — "rare" или "legendary" (из OSC_ABILITY_RARITIES); без поля —
-- обычная. Редкость меняет только шанс выпадения (множитель веса
-- ABILITY_RARITY_WEIGHT в config.lua) и оформление в HUD, но не силу.
```

Строку `-- Способности, которых нет в KV, с неверным весом или тегами, при старте` заменить на `-- Способности, которых нет в KV, с неверным весом, тегами или редкостью, при старте`.

После строки `OSC_ABILITY_TAGS = { "damage", "disable", "mobility", "passive", "support" }` вставить:

```lua

-- Редкости записей пула: common — обычная (поле rarity можно не писать)
OSC_ABILITY_RARITIES = { "common", "rare", "legendary" }
```

- [ ] **Step 5: GetRarity и GetWeight**

В `ability_selection.lua` заменить функцию `local function GetWeight(entry) ... end` (строки 65-71) на:

```lua
function OSC_AbilitySelection.GetRarity(entry)
    if OSC_Config.Get("ABILITY_RARITY_ENABLED") ~= true then
        return "common"
    end
    return entry and entry.rarity or "common"
end

-- Неверный множитель редкости пишется в лог один раз на редкость: вес
-- считается на каждый взвешенный выбор
local warnedRarities = {}

local function RarityMultiplier(entry)
    if OSC_Config.Get("ABILITY_RARITY_ENABLED") ~= true then
        return 1
    end
    local rarity = OSC_AbilitySelection.GetRarity(entry)
    local multiplier = OSC_Config.Get("ABILITY_RARITY_WEIGHT." .. rarity)
    if type(multiplier) ~= "number" or multiplier < 1 or multiplier ~= math.floor(multiplier) then
        if not warnedRarities[rarity] then
            warnedRarities[rarity] = true
            OSC_Logger.Error("ABILITY_RARITY_WEIGHT." .. rarity
                .. " must be a positive integer, got " .. tostring(multiplier))
        end
        return 1
    end
    return multiplier
end

-- Итоговый вес записи: weight (по умолчанию DEFAULT_WEIGHT) × множитель редкости
function OSC_AbilitySelection.GetWeight(entry)
    local weight = entry.weight == nil and DEFAULT_WEIGHT or entry.weight
    if not IsValidWeight(weight) then
        error("[OSC] Invalid weight for ability: " .. tostring(entry.name))
    end
    return weight * RarityMultiplier(entry)
end
```

В `PickWeighted` (строки 296-312) заменить оба вызова `GetWeight(entry)` на `OSC_AbilitySelection.GetWeight(entry)`.

`require("osc/core/logger")` в `ability_selection.lua` не нужен: его подтягивает `runtime_config`.

- [ ] **Step 6: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: три теста `test_rarity.*` PASS, все старые тесты PASS (распределения в `test_tags` не меняются: у записей без `rarity` все веса умножаются на одно и то же), `RESULT: OK`.

- [ ] **Step 7: Commit**

```bash
git add game/scripts/vscripts/osc/config/config.lua game/scripts/vscripts/osc/config/ability_pools.lua game/scripts/vscripts/osc/systems/ability_selection.lua tools/tests/test_rarity.lua
git commit -m "feat: ability rarity weight multiplier" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A2: Проверка редкости в ValidatePools и фильтр opts.rarity

**Files:**
- Modify: `game/scripts/vscripts/osc/systems/ability_selection.lua` (`KnownTags`, `ValidatePools`, `PickCandidates`)
- Test: `tools/tests/test_rarity.lua`

**Interfaces:**
- Consumes: `OSC_ABILITY_RARITIES`, `GetRarity` из A1.
- Produces: `PickCandidates(hero, slot, count, opts)` с `opts.rarity`; сигнатура не меняется (на неё опирается трек C).

- [ ] **Step 1: Добавить падающие тесты**

В таблицу, которую возвращает `test_rarity.lua`, дописать (перед закрывающей `}`):

```lua
    validate_removes_invalid_rarity = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_ok", "rare"), entry("test_plain", "common"), entry("test_epic", "epic"),
        }
        H.DefineAbility("test_ult", { ultimate = true })
        OSC_ULTIMATE_POOL = { { name = "test_ult", hero = "npc_dota_hero_axe", label = "U", tags = { "damage" } } }

        local removed = OSC_AbilitySelection.ValidatePools()

        H.eq(removed, 1, "only the bad rarity removed")
        H.eq(#OSC_ABILITY_POOL, 2, "rare and explicit common kept")
        H.truthy(H.logged("test_epic (invalid rarity epic)"), "reason logged")
    end,

    rarity_filter_returns_only_that_rarity = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_c1"), entry("test_c2"), entry("test_c3"),
            entry("test_l1", "legendary"), entry("test_l2", "legendary"), entry("test_l3", "legendary"),
        }
        local hero = heroWith("test_c1")
        for _ = 1, 20 do
            local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
            H.eq(#picked, 3, "three candidates")
            for _, item in ipairs(picked) do
                H.eq(item.rarity, "legendary", "only legendary " .. item.name)
            end
        end
    end,

    rarity_filter_fills_without_duplicates = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_c1"), entry("test_c2"), entry("test_c3"), entry("test_c4"),
            entry("test_l1", "legendary"),
        }
        local hero = heroWith("test_c1")
        for _ = 1, 20 do
            local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
            H.eq(#picked, 3, "filled up to count")
            H.eq(picked[1].name, "test_l1", "legendary first")
            local seen = {}
            for _, item in ipairs(picked) do
                H.eq(seen[item.name], nil, "no duplicates: " .. item.name)
                H.truthy(item.name ~= "test_c1", "current ability not offered")
                seen[item.name] = true
            end
        end
    end,

    rarity_filter_without_matches_still_picks = function()
        setup()
        OSC_CONFIG.ABILITY_RARITY_ENABLED = false -- все записи считаются обычными
        OSC_ABILITY_POOL = {
            entry("test_c1"), entry("test_c2"), entry("test_c3"), entry("test_l1", "legendary"),
        }
        local hero = heroWith("test_c1")
        local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
        H.eq(#picked, 3, "picked from the whole pool without error")
    end,
```

- [ ] **Step 2: Запустить тесты — убедиться, что падают**

Run: `python tools/tests/run_tests.py`
Expected: `validate_removes_invalid_rarity` FAIL (`only the bad rarity removed: expected 1, got 0`), `rarity_filter_returns_only_that_rarity` FAIL (`only legendary ...: expected legendary, got nil`), `rarity_filter_fills_without_duplicates` FAIL (`legendary first`); `rarity_filter_without_matches_still_picks` может уже проходить — это нормально. `RESULT: FAIL`.

- [ ] **Step 3: ValidatePools**

В `ability_selection.lua` после функции `KnownTags` добавить:

```lua
local function KnownRarities()
    local known = {}
    for _, rarity in ipairs(OSC_ABILITY_RARITIES or {}) do
        known[rarity] = true
    end
    return known
end
```

В комментарии над `ValidatePools` заменить `-- с неверным весом или тегами (нет тегов, тег не из OSC_ABILITY_TAGS,` на `-- с неверным весом, тегами (нет тегов, тег не из OSC_ABILITY_TAGS,` и строку `-- повтор), а из linked — отсутствующие подспособности.` на `-- повтор) или редкостью (не из OSC_ABILITY_RARITIES), а из linked —` + новая строка `-- отсутствующие подспособности.`

В теле: после `local knownTags = KnownTags()` добавить `local knownRarities = KnownRarities()`, а в цепочку проверок после ветки `elseif tagsReason then ... ` добавить:

```lua
            elseif entry.rarity ~= nil and not knownRarities[entry.rarity] then
                reasons[index] = "invalid rarity " .. tostring(entry.rarity)
```

- [ ] **Step 4: PickCandidates с opts.rarity**

Тело текущей `OSC_AbilitySelection.PickCandidates` разделить: отбор по ступеням уходит в локальную функцию `Collect`, публичная функция добавляет фильтр редкости. Заменить всю функцию (строки 314-358 вместе с комментарием) на:

```lua
-- До count записей пула по ступеням отбора (см. BuildTiers), взвешенный
-- выбор без повторов. filter(entry) — дополнительное условие или nil.
local function Collect(hero, slot, count, exclude, filter)
    local pool = OSC_AbilitySelection.GetPool(slot)
    local chosen, chosenNames = {}, {}
    for tierIndex, tier in ipairs(BuildTiers(hero, slot, exclude)) do
        if #chosen >= count or (tier.only_if_empty and #chosen > 0) then
            break
        end
        local candidates = {}
        for _, entry in ipairs(pool) do
            if not chosenNames[entry.name] and tier.accepts(entry)
                and (filter == nil or filter(entry)) then
                table.insert(candidates, entry)
            end
        end
        if tierIndex > 1 and #candidates > 0 then
            OSC_Logger.Log("Ability pick for " .. hero:GetUnitName() .. " (" .. slot
                .. ") relaxed to rule '" .. tier.name .. "'")
        end
        while #chosen < count and #candidates > 0 do
            local index = PickWeighted(candidates)
            if not index then
                break
            end
            local entry = table.remove(candidates, index)
            chosenNames[entry.name] = true
            table.insert(chosen, entry)
        end
    end
    return chosen
end

-- До count разных записей пула для слота героя ("ability" или "ultimate")
-- по правилам режима, взвешенный выбор без повторов. Сначала берутся
-- кандидаты самой строгой ступени, недостающие — из следующих: так
-- ослабляется правило серии тегов. opts.exclude — имена, которые не
-- предлагать (например, уже показанные игроку). opts.rarity — только
-- записи этой редкости (GetRarity); если их меньше count, недостающие
-- добираются без фильтра редкости тем же выбором, без повторов.
-- Ошибка, если не нашлось ни одной записи.
function OSC_AbilitySelection.PickCandidates(hero, slot, count, opts)
    opts = opts or {}
    local exclude = {}
    for _, name in ipairs(opts.exclude or {}) do
        exclude[name] = true
    end

    local chosen
    if opts.rarity then
        chosen = Collect(hero, slot, count, exclude, function(entry)
            return OSC_AbilitySelection.GetRarity(entry) == opts.rarity
        end)
        if #chosen < count then
            for _, entry in ipairs(chosen) do
                exclude[entry.name] = true
            end
            for _, entry in ipairs(Collect(hero, slot, count - #chosen, exclude)) do
                table.insert(chosen, entry)
            end
        end
    else
        chosen = Collect(hero, slot, count, exclude)
    end

    if #chosen == 0 then
        error("[OSC] No eligible abilities in pool for slot " .. tostring(slot))
    end
    return chosen
end
```

`Pick(hero, slot)` не меняется.

- [ ] **Step 5: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: все `test_rarity.*` PASS, `test_tags.*` и `test_rotation_choice.*` PASS, `RESULT: OK`.

- [ ] **Step 6: Commit**

```bash
git add game/scripts/vscripts/osc/systems/ability_selection.lua tools/tests/test_rarity.lua
git commit -m "feat: validate rarity and filter candidates by rarity" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A3: Объявление легендарки и rarity в HUD-событии

**Files:**
- Modify: `game/scripts/vscripts/osc/config/notifications.lua` (раздел `-- ===== Способности =====`)
- Modify: `game/scripts/vscripts/osc/core/notifications.lua:141-150`
- Modify: `game/scripts/vscripts/osc/systems/abilities.lua:511-529` (`ApplyGive`)
- Modify: `game/resource/addon_russian.txt` (после строки 66), `game/resource/addon_english.txt` (после строки 65)
- Test: `tools/tests/test_rarity.lua`

**Interfaces:**
- Consumes: `OSC_AbilitySelection.GetRarity`.
- Produces: `OSC_Notifications.AbilityChanged(hero, entry, rarity)` (третий аргумент необязателен, по умолчанию `"common"`), `OSC_Notifications.LegendaryAbility(hero, entry)`, тип `legendary_ability`, ключ `osc_notify_legendary_ability`.

Решение: объявление легендарки идёт в ветке `if notify then` в `ApplyGive` — как и обычное уведомление. Все текущие вызовы (`GiveRandom`/`Give` из ротации, `hero_lifecycle` — стартовая способность и первый ультимейт, `-reroll`, предмет реролла) передают `notify = true`, поэтому стартовая способность тоже объявляется; тихая выдача (`notify = false`) остаётся тихой. Звук легендарки слышит только её владелец — через HUD-событие `osc_ability_changed` (A4); лента — у всех.

- [ ] **Step 1: Добавить падающие тесты**

Дописать в `test_rarity.lua`:

```lua
    client_options_have_rarity = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_cur"), entry("test_l1", "legendary"), entry("test_r1", "rare"), entry("test_c1"),
        }
        local hero = heroWith("test_cur")

        H.truthy(OSC_RotationChoice.Offer(hero, 1, 10), "offer sent")

        local options = H.lastEvent("osc_rotation_choice_offer").data.options
        H.eq(#options, 3, "three options")
        for _, option in ipairs(options) do
            local expected = OSC_AbilitySelection.GetRarity(OSC_AbilitySelection.FindEntry(option.name))
            H.eq(option.rarity, expected, "event rarity of " .. option.name)
        end
        for _, option in ipairs(H.netTables["choice_0"].options) do
            H.truthy(option.rarity, "net table rarity of " .. option.name)
        end
    end,

    legendary_give_announced = function()
        setup()
        local legendary, common = entry("test_l", "legendary"), entry("test_c")
        OSC_ABILITY_POOL = { entry("test_cur"), legendary, common }
        local hero = heroWith("test_cur")
        local announced = {}
        OSC_Notifications.LegendaryAbility = function(_, given) table.insert(announced, given.name) end

        OSC_Abilities.Give(hero, "ability", legendary, true)
        H.eq(#announced, 1, "legendary announced")
        H.eq(announced[1], "test_l", "announced entry")
        H.eq(H.lastEvent("osc_ability_changed").data.rarity, "legendary", "popup gets rarity")

        OSC_Abilities.Give(hero, "ability", common, true)
        H.eq(#announced, 1, "common not announced")
        H.eq(H.lastEvent("osc_ability_changed").data.rarity, "common", "popup common")
    end,

    legendary_feed_goes_to_everyone = function()
        setup()
        local hero = heroWith("test_cur")

        OSC_Notifications.LegendaryAbility(hero, entry("test_l", "legendary"))

        local feed = H.lastEvent("osc_notification")
        H.truthy(feed, "feed sent")
        H.eq(feed.player, nil, "to all clients")
        H.eq(feed.data.token, "#osc_notify_legendary_ability", "token")
        H.eq(feed.data.params.player_id, "0", "player for the name")
        H.eq(feed.data.params.ability, "#DOTA_Tooltip_Ability_test_l", "ability token")
    end,

    deferred_legendary_announced_once = function()
        setup()
        local legendary = entry("test_l", "legendary")
        OSC_ABILITY_POOL = { entry("test_cur"), legendary }
        local hero = heroWith("test_cur")
        local old = hero:FindAbilityByName("test_cur")
        old.in_phase = true
        local announced = 0
        OSC_Notifications.LegendaryAbility = function() announced = announced + 1 end

        OSC_Abilities.Give(hero, "ability", legendary, true)
        H.eq(announced, 0, "not announced while the old one is casting")

        old.in_phase = false
        H.time = 0.25
        H.RunThink("osc_deferred_ability")
        H.eq(OSC_HeroState.Get(hero).ability, "test_l", "given after the cast")
        H.eq(announced, 1, "announced once at the real give")
    end,
```

- [ ] **Step 2: Запустить тесты — убедиться, что падают**

Run: `python tools/tests/run_tests.py`
Expected: `client_options_have_rarity` FAIL (`event rarity of ...: expected common, got nil`), `legendary_give_announced` FAIL (`legendary announced: expected 1, got 0`), `legendary_feed_goes_to_everyone` FAIL (`attempt to call field 'LegendaryAbility'`), `deferred_legendary_announced_once` FAIL (`announced once ...: expected 1, got 0`).

- [ ] **Step 3: Тип уведомления**

В `osc/config/notifications.lua` после блока `ability_changed = { ... },` вставить:

```lua

        -- Легендарная способность: лента всем и частица над героем; звук —
        -- у владельца, по HUD-событию osc_ability_changed (rarity)
        legendary_ability = {
            category = "ability",
            particle = { name = "particles/generic_hero_status/hero_levelup.vpcf" },
            feed = { token = "#osc_notify_legendary_ability", color = "#FFC23A" },
        },
```

Частица `hero_levelup` уже прекэширована в `addon_game_mode.lua`; более «золотой» эффект подбирается в игре (это пункт ручной проверки, а не задача ветки).

- [ ] **Step 4: Обёртки**

В `osc/core/notifications.lua` заменить `OSC_Notifications.AbilityChanged` на:

```lua
-- rarity — редкость записи (OSC_AbilitySelection.GetRarity) для рамки
-- всплывающего окна; по умолчанию "common"
function OSC_Notifications.AbilityChanged(hero, entry, rarity)
    local playerID = hero:GetPlayerOwnerID()
    OSC_Notifications.Notify("ability_changed", {
        unit = hero,
        team = hero:GetTeamNumber(),
        player_id = playerID,
        ability = "#DOTA_Tooltip_Ability_" .. entry.name,
        hud = { ability = entry.name, label = entry.label, rarity = rarity or "common" },
    })
end

-- Герой получил легендарную способность: объявление всем игрокам
function OSC_Notifications.LegendaryAbility(hero, entry)
    OSC_Notifications.Notify("legendary_ability", {
        unit = hero,
        player_id = hero:GetPlayerOwnerID(),
        ability = "#DOTA_Tooltip_Ability_" .. entry.name,
    })
end
```

`player_id` уходит клиенту строкой, лента сама подставляет `{s:player_name}` (`osc_notification_feed.js`, `ResolvePlayerName`). Поле `player` — служебное (`SERVICE_KEYS`) и клиенту не уходит, поэтому в токене используется `{s:player_name}`, а не `{s:player}` из спека.

- [ ] **Step 5: ApplyGive**

В `osc/systems/abilities.lua` в `ApplyGive` заменить

```lua
    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end
```

на

```lua
    -- Здесь же проходит и отложенная выдача (ProcessDeferred): объявление
    -- уходит в момент фактической смены, один раз
    if notify then
        local rarity = OSC_AbilitySelection.GetRarity(entry)
        OSC_Notifications.AbilityChanged(hero, entry, rarity)
        if rarity == "legendary" then
            OSC_Notifications.LegendaryAbility(hero, entry)
        end
    end
```

- [ ] **Step 6: ClientOptions**

В `osc/systems/rotation_choice.lua` в `ClientOptions` заменить строку `options[index] = { name = name, label = entry and entry.label or name }` на:

```lua
        options[index] = {
            name = name,
            label = entry and entry.label or name,
            rarity = OSC_AbilitySelection.GetRarity(entry),
        }
```

В шапке файла строку `--     options = { [1] = { name, label }, ... }; после смены options = {},` заменить на `--     options = { [1] = { name, label, rarity }, ... }; после смены options = {},`.

- [ ] **Step 7: Локализация**

`addon_russian.txt`, после строки `		"osc_notify_ability_changed" "{s:player_name} получает способность «{s:ability}»"` (Edit tool, два таба):

```
		"osc_notify_legendary_ability"	"{s:player_name} получает ЛЕГЕНДАРНУЮ способность «{s:ability}»!"
```

`addon_english.txt`, после строки `			"osc_notify_ability_changed" "{s:player_name} gets ability “{s:ability}”"` (три таба):

```
			"osc_notify_legendary_ability"	"{s:player_name} got a LEGENDARY ability “{s:ability}”!"
```

- [ ] **Step 8: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `Localization: OK`, все `test_rarity.*` PASS, `test_cast_phase.*` PASS (их заглушка `AbilityChanged` принимает лишний аргумент), `RESULT: OK`.

- [ ] **Step 9: Commit**

```bash
git add game/scripts/vscripts/osc/config/notifications.lua game/scripts/vscripts/osc/core/notifications.lua game/scripts/vscripts/osc/systems/abilities.lua game/scripts/vscripts/osc/systems/rotation_choice.lua game/resource/addon_russian.txt game/resource/addon_english.txt tools/tests/test_rarity.lua
git commit -m "feat: announce legendary abilities and send rarity to the HUD" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A4: Рамки редкости в выборе из трёх и во всплывающем окне

**Files:**
- Modify: `content/panorama/scripts/custom_game/osc_rotation_choice.js` (`ToOptionList`, `CreateCard`, комментарий у `options`)
- Modify: `content/panorama/scripts/custom_game/osc_ability_popup.js` (`OnAbilityChanged`)
- Modify: `content/panorama/scripts/custom_game/osc_core.js` (`OSC.Sounds`)
- Modify: `content/panorama/styles/custom_game/osc_hud.css` (между `.ChoiceCard:hover {}` и `.ChoiceCard.Picked {}`; после `#PopupIcon {}`)

**Interfaces:**
- Consumes: `options[i].rarity` (A3), `osc_ability_changed.rarity` (A3).
- Produces: CSS-классы `RarityRare` / `RarityLegendary` на `.ChoiceCard` и `#PopupCard`; `OSC.Sounds.legendaryAbility`.

- [ ] **Step 1: osc_rotation_choice.js**

В `ToOptionList` заменить `return { name: String(option.name || ""), label: String(option.label || "") };` на:

```js
        return {
          name: String(option.name || ""),
          label: String(option.label || ""),
          rarity: String(option.rarity || "common"),
        };
```

Комментарий `var options = []; // [{ name, label }] в порядке ключей "1", "2", "3"` → `// [{ name, label, rarity }] ...`.

В `CreateCard` после `card.SetAttributeString("osc_ability", option.name);` добавить:

```js
    // Рамка редкости (osc_hud.css): обычная — без рамки
    card.SetHasClass("RarityRare", option.rarity === "rare");
    card.SetHasClass("RarityLegendary", option.rarity === "legendary");
```

- [ ] **Step 2: osc_ability_popup.js**

В `OnAbilityChanged` внутри `$.Schedule(FLIP_DURATION, ...)` заменить строку `OSC.Util.PlaySound(OSC.Sounds.abilityChanged);` на:

```js
      card.SetHasClass("RarityRare", event.rarity === "rare");
      card.SetHasClass("RarityLegendary", event.rarity === "legendary");
      OSC.Util.PlaySound(
        event.rarity === "legendary" ? OSC.Sounds.legendaryAbility : OSC.Sounds.abilityChanged,
      );
```

- [ ] **Step 3: osc_core.js**

В `OSC.Sounds` после `abilityChanged: "",` добавить:

```js
  legendaryAbility: "DOTA_Item.Refresher.Activate", // своя легендарная способность
```

(Звук предметов загружен всегда; если в игре не звучит или не подходит — подобрать в Asset Browser, это пункт ручной проверки.)

- [ ] **Step 4: CSS**

В `osc_hud.css` между блоком `.ChoiceCard:hover { ... }` и блоком `.ChoiceCard.Picked { ... }` вставить (порядок важен: `Picked` объявлен позже и при равной специфичности перекрывает рамку редкости, а свечение-анимация остаётся):

```css
/* Редкость: редкая — синяя рамка, легендарная — золотая с пульсирующим
   свечением; обычная — без изменений. Те же классы у карточек Сферы хаоса */
@keyframes 'OSCLegendaryGlow' {
  0% {
    box-shadow: #ffc23a55 0px 0px 6px 0px;
  }
  50% {
    box-shadow: #ffc23acc 0px 0px 16px 2px;
  }
  100% {
    box-shadow: #ffc23a55 0px 0px 6px 0px;
  }
}

.ChoiceCard.RarityRare {
  border: 2px solid #4b8bff;
}

.ChoiceCard.RarityLegendary {
  border: 2px solid #ffc23a;
  animation-name: OSCLegendaryGlow;
  animation-duration: 1.6s;
  animation-iteration-count: infinite;
  animation-timing-function: ease-in-out;
}
```

После блока `#PopupIcon { ... }` вставить:

```css
#PopupCard.RarityRare #PopupIcon {
  border: 2px solid #4b8bff;
  box-shadow: #4b8bffaa 0px 0px 16px 0px;
}

#PopupCard.RarityLegendary #PopupIcon {
  border: 2px solid #ffc23a;
  animation-name: OSCLegendaryGlow;
  animation-duration: 1.6s;
  animation-iteration-count: infinite;
  animation-timing-function: ease-in-out;
}
```

- [ ] **Step 5: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `JS syntax: OK`, `RESULT: OK`.

- [ ] **Step 6: Commit**

```bash
git add content/panorama/scripts/custom_game/osc_rotation_choice.js content/panorama/scripts/custom_game/osc_ability_popup.js content/panorama/scripts/custom_game/osc_core.js content/panorama/styles/custom_game/osc_hud.css
git commit -m "feat: rarity frames in choice cards and ability popup" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task A5: Разметка редкости текущего пула

**Files:**
- Modify: `game/scripts/vscripts/osc/config/ability_pools.lua` (записи `OSC_ABILITY_POOL` и `OSC_ULTIMATE_POOL`)

**Interfaces:**
- Consumes: `OSC_ABILITY_RARITIES` (A1); тест `test_tags.every_pool_entry_has_valid_tags` после A2 проверяет и редкость.

Правило ради слияния с треком B: **последнюю запись каждого пула не размечать** (`tidehunter_kraken_shell` и `elder_titan_earth_splitter` остаются обычными). Трек B дописывает новые записи сразу после них; если A изменит эти строки, git даст конфликт.

Разметка (≈15% легендарных, ≈30% редких; 89 записей → 14 легендарных, 28 редких). В каждую запись добавить поле `rarity = "..."` в конце строки, перед закрывающей `}` (у записей с `linked` — после `tags = { ... },` на первой строке, `linked` остаётся на второй). Пример: `{ name = "pudge_meat_hook", ..., tags = { "disable", "damage" }, rarity = "legendary" },`.

| Пул | Легендарные | Редкие |
| --- | --- | --- |
| `OSC_ABILITY_POOL` (58) | `pudge_meat_hook`, `puck_illusory_orb`, `antimage_blink` (спек); `dazzle_shallow_grave`, `lion_voodoo`, `sandking_burrowstrike`, `disruptor_kinetic_field` | `lina_light_strike_array`, `lion_impale`, `sven_storm_bolt`, `crystal_maiden_frostbite`, `earthshaker_fissure`, `queenofpain_blink`, `mirana_arrow`, `shadow_shaman_voodoo`, `axe_berserkers_call`, `centaur_hoof_stomp`, `windrunner_shackleshot`, `puck_waning_rift`, `jakiro_ice_path`, `witch_doctor_paralyzing_cask`, `phantom_assassin_phantom_strike`, `bane_nightmare`, `shadow_demon_disruption`, `spirit_breaker_greater_bash` |
| `OSC_ULTIMATE_POOL` (31) | `tidehunter_ravage`, `magnataur_reverse_polarity`, `earthshaker_echo_slam`, `necrolyte_reapers_scythe`, `juggernaut_omni_slash`, `bane_fiends_grip` (спек); `zuus_thundergods_wrath` | `lion_finger_of_death`, `sven_gods_strength`, `crystal_maiden_freezing_field`, `lich_chain_frost`, `sandking_epicenter`, `pudge_dismember`, `axe_culling_blade`, `disruptor_static_storm`, `witch_doctor_death_ward`, `phantom_assassin_coup_de_grace` |

Сверх спека выбраны: легендарные основные — способности, которые сами по себе решают драку (Shallow Grave спасает от смерти, хекс и Kinetic Field — гарантированный контроль, Burrowstrike — вход + оглушение); легендарный ультимейт `zuus_thundergods_wrath` — глобальный урон. Редкие — сильный контроль или мобильность, но не «выигрывающие» способности.

- [ ] **Step 1: Проставить rarity** (Edit tool, по записи или блоками строк).

- [ ] **Step 2: Проверить счёт**

Run: `grep -c 'rarity = "legendary"' game/scripts/vscripts/osc/config/ability_pools.lua; grep -c 'rarity = "rare"' game/scripts/vscripts/osc/config/ability_pools.lua`
Expected: `14` и `28`.

Run: `grep -n 'kraken_shell\|earth_splitter' game/scripts/vscripts/osc/config/ability_pools.lua`
Expected: обе строки без `rarity`.

- [ ] **Step 3: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `test_tags.every_pool_entry_has_valid_tags` PASS (ничего не убрано), `RESULT: OK`.

- [ ] **Step 4: Commit** (в описании — одна строка обоснования, как требует спек)

```bash
git add game/scripts/vscripts/osc/config/ability_pools.lua
git commit -m "feat: mark rarity of existing pool entries" -m "Legendary: fight-deciding spells (save, guaranteed disable, global damage) plus the spec list; rare: strong disables and mobility." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Отчёт трека A

Что сделано (по задачам A1–A5), список изменённых файлов, итог `run_tests.py`. Проверить в игре: рамки на карточках выбора из трёх (синяя/золотая, свечение легендарки); всплывающее окно новой способности с рамкой; при легендарке — строка в ленте у **всех** игроков, частица над героем, звук у владельца (если частица/звук не подходят — предложить замену); `-reroll` несколько раз — в логе нет `ABILITY_RARITY_WEIGHT` и `invalid rarity`.

---

## Трек B — Расширение пула (Часть 2) и справка «?» (Часть 4)

### Владение файлами трека B

Только эти файлы:

- `game/scripts/vscripts/osc/config/ability_pools.lua` — **только новые записи в конце** `OSC_ABILITY_POOL` (после `tidehunter_kraken_shell`) и `OSC_ULTIMATE_POOL` (после `elder_titan_earth_splitter`); существующие строки и шапку не трогать
- `tools/tests/test_tags.lua` — новый тест в конце таблицы
- `game/todo.md` — новый раздел
- Создать: `content/panorama/scripts/custom_game/osc_help.js`
- `content/panorama/layout/custom_game/osc_hud.xml` — include после `osc_chaos_shop.js`; блок справки **перед** комментарием `<!-- Хаос-лавка (osc_chaos_shop.js)`
- `content/panorama/scripts/custom_game/osc_hud.js` — строка после `OSC.ChaosShop.Init();`
- `content/panorama/styles/custom_game/osc_hud.css` — раздел **в самом конце файла**
- `game/resource/addon_russian.txt`, `addon_english.txt` — ключи `osc_hud_help_*` после строки `osc_hud_title_storm_chaser_desc` (последний ключ перед закрывающими `}`)

`addon_game_mode.lua` не меняется: `Precache` уже прекэширует героя каждой записи пула. `run_tests.py` не меняется: префикс `osc_hud_` уже в `LOC_PREFIXES`. Поле `OSC_ABILITY_RARITIES` и проверку редкости делает трек A — в треке B редкость новых записей проверяет собственный тест.

### Task B1: Тест целостности пулов

**Files:**
- Modify: `tools/tests/test_tags.lua` (в конец возвращаемой таблицы)

**Interfaces:**
- Produces: тест `test_tags.pool_entries_unique_and_well_formed`.

- [ ] **Step 1: Написать тест**

Дописать в таблицу `test_tags.lua` перед закрывающей `}`:

```lua
    -- Записи реальных пулов: имена не повторяются (в том числе между пулами
    -- и с linked), редкость из списка, hero и label заданы
    pool_entries_unique_and_well_formed = function()
        setup()
        local rarities = { common = true, rare = true, legendary = true }
        local seen, problems = {}, {}
        local function Claim(name)
            if seen[name] then table.insert(problems, "duplicate " .. name) end
            seen[name] = true
        end
        for _, pool in ipairs({ OSC_ABILITY_POOL, OSC_ULTIMATE_POOL }) do
            for _, item in ipairs(pool) do
                Claim(item.name)
                for _, link in ipairs(item.linked or {}) do Claim(link.name) end
                if item.rarity ~= nil and not rarities[item.rarity] then
                    table.insert(problems, "rarity " .. item.name .. "=" .. tostring(item.rarity))
                end
                if type(item.hero) ~= "string" or string.sub(item.hero, 1, 14) ~= "npc_dota_hero_" then
                    table.insert(problems, "hero " .. item.name)
                end
                if type(item.label) ~= "string" or item.label == "" then
                    table.insert(problems, "label " .. item.name)
                end
            end
        end
        H.eq(table.concat(problems, ", "), "", "pool entries")
    end,
```

- [ ] **Step 2: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `PASS test_tags.pool_entries_unique_and_well_formed` (текущий пул корректен), `RESULT: OK`. Тест охраняет следующую задачу: проверено, что он ловит повтор — временно продублировать любую запись, увидеть `FAIL ... duplicate <имя>`, вернуть.

- [ ] **Step 3: Commit**

```bash
git add tools/tests/test_tags.lua
git commit -m "test: pool entries are unique and well formed" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B2: Новые записи пулов

**Files:**
- Modify: `game/scripts/vscripts/osc/config/ability_pools.lua` (конец `OSC_ABILITY_POOL` после строки `tidehunter_kraken_shell`, конец `OSC_ULTIMATE_POOL` после строки `elder_titan_earth_splitter`)
- Modify: `game/todo.md`

**Interfaces:**
- Consumes: формат записи из шапки `ability_pools.lua`: `name`, `hero`, `label`, `tags` (из `damage`, `disable`, `mobility`, `passive`, `support`), необязательные `weight` (пассивки в пуле — `weight = 2`), `linked`, `rarity` (`"rare"`/`"legendary"`, обычным поле не писать).

- [ ] **Step 1: Замер «до»**

Run: `grep -oE 'hero = "[a-z_]+"' game/scripts/vscripts/osc/config/ability_pools.lua | sort -u | wc -l`
Expected: `41` (уникальных героев в пулах сейчас). Записать в отчёт.

- [ ] **Step 2: Индекс имён способностей из игры**

Сохранить в **свой scratchpad** (не в репозиторий; файл ASCII, можно Write tool) скрипт `vpk_names.py`:

```python
# Prints ability names defined in Dota KV (scripts/npc/heroes/*.txt and npc_abilities.txt
# inside pak01_dir.vpk), one per line. Usage: python vpk_names.py "<dota 2 beta>/game/dota"
import os
import re
import struct
import sys

D = sys.argv[1]
f = open(os.path.join(D, "pak01_dir.vpk"), "rb")
sig, ver, tree = struct.unpack("<III", f.read(12))
if ver == 2:
    f.read(16)
end = f.tell() + tree


def cstr():
    b = bytearray()
    while True:
        c = f.read(1)
        if c == b"\0":
            return b.decode("utf-8", "replace")
        b += c


# Top-level keys of DOTAAbilities: a quoted name alone on a line followed by "{"
KEY = re.compile(r'^[ \t]*"([A-Za-z0-9_]+)"[ \t]*\r?\n[ \t]*\{', re.M)
out = set()
while True:
    ext = cstr()
    if not ext:
        break
    while True:
        path = cstr()
        if not path:
            break
        while True:
            name = cstr()
            if not name:
                break
            crc, pre, arch, off, ln, term = struct.unpack("<IHHIIH", f.read(18))
            preload = f.read(pre)
            full = path + "/" + name + "." + ext
            if ext == "txt" and (path == "scripts/npc/heroes" or full == "scripts/npc/npc_abilities.txt"):
                if arch == 0x7FFF:
                    pos = f.tell()
                    f.seek(end + off)
                    data = f.read(ln)
                    f.seek(pos)
                else:
                    with open(os.path.join(D, "pak01_%03d.vpk" % arch), "rb") as a:
                        a.seek(off)
                        data = a.read(ln)
                text = (preload + data).decode("utf-8", "replace")
                for m in KEY.finditer(text):
                    out.add(m.group(1))
for n in sorted(out):
    print(n)
```

Run (Git Bash, `<scratch>` — путь своего scratchpad):

```bash
python "<scratch>/vpk_names.py" "/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota" | tr -d '\r' | sort -u > "<scratch>/names.txt"
wc -l < "<scratch>/names.txt"
grep -oE 'name = "[a-z0-9_]+"' game/scripts/vscripts/osc/config/ability_pools.lua | cut -d'"' -f2 | sort -u | comm -23 - "<scratch>/names.txt"
```

Expected: ~4800 имён; последняя команда печатает только `drunk`, `lost`, `ogre_magi_casino` (способности курьера и своя способность Огра — их в KV игры нет, это нормально). Если печатает что-то ещё — индекс устарел или скрипт сломан; разобраться до добавления записей.

- [ ] **Step 3: Отобрать записи**

Ниже — кандидаты, уже сверенные с индексом игры (14.10.2026) и с правилами отбора спека (не формы, не тогглы и пары без `linked`, не зависят от родных способностей/ресурсов героя, не управляемые призывы, не глобальные телепорты). Взять **40 основных и 20 ультимейтов**. При выборе между равными предпочитать героев, которые уже есть в пулах (помечены «уже в пуле»): они не добавляют прекэша. Имя героя — `npc_dota_hero_<hero>`.

Основные (`OSC_ABILITY_POOL`):

| name | hero | label | tags | rarity |
| --- | --- | --- | --- | --- |
| `tidehunter_gush` | tidehunter (уже в пуле) | Gush | damage | |
| `ogre_magi_ignite` | ogre_magi (уже) | Ignite | damage | |
| `magnataur_shockwave` | magnataur (уже) | Shockwave | damage | |
| `magnataur_skewer` | magnataur (уже) | Skewer | mobility, disable | rare |
| `mirana_leap` | mirana (уже) | Leap | mobility | |
| `lich_frost_shield` | lich (уже) | Frost Shield | support | |
| `centaur_double_edge` | centaur (уже) | Double Edge | damage | |
| `shadow_shaman_ether_shock` | shadow_shaman (уже) | Ether Shock | damage | |
| `queenofpain_shadow_strike` | queenofpain (уже) | Shadow Strike | damage | |
| `earthshaker_enchant_totem` | earthshaker (уже) | Enchant Totem | damage | |
| `tusk_ice_shards` | tusk | Ice Shards | disable, damage | |
| `nyx_assassin_impale` | nyx_assassin | Impale (Nyx) | disable, damage | rare |
| `dragon_knight_dragon_tail` | dragon_knight | Dragon Tail | disable | |
| `dragon_knight_breathe_fire` | dragon_knight | Breathe Fire | damage | |
| `chaos_knight_chaos_bolt` | chaos_knight | Chaos Bolt | disable, damage | |
| `skeleton_king_hellfire_blast` | skeleton_king | Wraithfire Blast | disable, damage | |
| `night_stalker_void` | night_stalker | Void | damage, disable | |
| `tiny_avalanche` | tiny | Avalanche | damage, disable | |
| `leshrac_split_earth` | leshrac | Split Earth | damage, disable | |
| `kunkka_torrent` | kunkka | Torrent | damage, disable | |
| `dark_seer_vacuum` | dark_seer | Vacuum | disable | rare |
| `batrider_sticky_napalm` | batrider | Sticky Napalm | damage | |
| `faceless_void_time_walk` | faceless_void | Time Walk | mobility | rare |
| `slark_pounce` | slark | Pounce | mobility, disable | |
| `ember_spirit_searing_chains` | ember_spirit | Searing Chains | disable, damage | |
| `weaver_shukuchi` | weaver | Shukuchi | mobility, damage | |
| `bounty_hunter_shuriken_toss` | bounty_hunter | Shuriken Toss | damage, disable | |
| `sniper_shrapnel` | sniper | Shrapnel | damage | |
| `oracle_fortunes_end` | oracle | Fortune's End | disable, damage | |
| `oracle_purifying_flames` | oracle | Purifying Flames | support, damage | |
| `treant_leech_seed` | treant | Leech Seed | damage, support | |
| `warlock_shadow_word` | warlock | Shadow Word | damage, support | |
| `bloodseeker_blood_bath` | bloodseeker | Blood Rite | damage, disable | |
| `dark_willow_bramble_maze` | dark_willow | Bramble Maze | disable | |
| `snapfire_scatterblast` | snapfire | Scatterblast | damage | |
| `snapfire_firesnap_cookie` | snapfire | Firesnap Cookie | mobility, support | rare |
| `void_spirit_aether_remnant` | void_spirit | Aether Remnant | disable | |
| `mars_spear` | mars | Spear of Mars | damage, disable | rare |
| `monkey_king_boundless_strike` | monkey_king | Boundless Strike | damage, disable | |
| `legion_commander_overwhelming_odds` | legion_commander | Overwhelming Odds | damage | |
| `legion_commander_press_the_attack` | legion_commander | Press the Attack | support | |
| `death_prophet_silence` | death_prophet | Silence (DP) | disable | |
| `obsidian_destroyer_astral_imprisonment` | obsidian_destroyer | Astral Imprisonment | disable, support | rare |
| `naga_siren_ensnare` | naga_siren | Ensnare | disable | |
| `abyssal_underlord_pit_of_malice` | abyssal_underlord | Pit of Malice | disable | |
| `spectre_spectral_dagger` | spectre | Spectral Dagger | damage, mobility | |
| `ancient_apparition_cold_feet` | ancient_apparition | Cold Feet | disable, damage | |
| `templar_assassin_refraction` | templar_assassin | Refraction | support | |
| `muerta_dead_shot` | muerta | Dead Shot | damage, disable | |

Ультимейты (`OSC_ULTIMATE_POOL`):

| name | hero | label | tags | rarity |
| --- | --- | --- | --- | --- |
| `abaddon_borrowed_time` | abaddon (уже) | Borrowed Time | support | rare |
| `enigma_black_hole` | enigma | Black Hole | disable, damage | legendary |
| `faceless_void_chronosphere` | faceless_void | Chronosphere | disable | legendary |
| `doom_bringer_doom` | doom_bringer | Doom | disable, damage | legendary |
| `winter_wyvern_winters_curse` | winter_wyvern | Winter's Curse | disable | legendary |
| `sniper_assassinate` | sniper | Assassinate | damage | |
| `kunkka_ghostship` | kunkka | Ghostship | damage, disable | rare |
| `legion_commander_duel` | legion_commander | Duel | disable | rare |
| `bloodseeker_rupture` | bloodseeker | Rupture | damage | |
| `beastmaster_primal_roar` | beastmaster | Primal Roar | disable, damage | rare |
| `batrider_flaming_lasso` | batrider | Flaming Lasso | disable | rare |
| `obsidian_destroyer_sanity_eclipse` | obsidian_destroyer | Sanity's Eclipse | damage | |
| `silencer_global_silence` | silencer | Global Silence | disable | rare |
| `nyx_assassin_vendetta` | nyx_assassin | Vendetta | mobility, damage | |
| `treant_overgrowth` | treant | Overgrowth | disable | rare |
| `grimstroke_soul_chain` | grimstroke | Soulbind | disable | |
| `mars_arena_of_blood` | mars | Arena of Blood | disable | rare |
| `snapfire_mortimer_kisses` | snapfire | Mortimer Kisses | damage | |
| `void_spirit_astral_step` | void_spirit | Astral Step | mobility, damage | |
| `death_prophet_exorcism` | death_prophet | Exorcism | damage | |
| `ursa_enrage` | ursa | Enrage | support | |
| `razor_eye_of_the_storm` | razor | Eye of the Storm | damage | |
| `medusa_stone_gaze` | medusa | Stone Gaze | disable | rare |

Если при проверке (Step 5) или по знанию игры кандидат оказывается сомнительным — не брать его, а записать в `todo.md` (Step 6) и взять следующего.

- [ ] **Step 4: Вписать записи**

Edit tool: после строки записи `tidehunter_kraken_shell` (последняя в `OSC_ABILITY_POOL`) вставить строку-комментарий `    -- Расширение пула (1.3)` и затем выбранные основные записи в формате соседних строк, например:

```lua
    { name = "tidehunter_gush",              hero = "npc_dota_hero_tidehunter",      label = "Gush", tags = { "damage" } },
    { name = "magnataur_skewer",             hero = "npc_dota_hero_magnataur",       label = "Skewer", tags = { "mobility", "disable" }, rarity = "rare" },
```

Так же после строки `elder_titan_earth_splitter` (последняя в `OSC_ULTIMATE_POOL`) — `    -- Расширение пула (1.3)` и ультимейты, например:

```lua
    { name = "enigma_black_hole",             hero = "npc_dota_hero_enigma",          label = "Black Hole", tags = { "disable", "damage" }, rarity = "legendary" },
```

Существующие строки не менять (трек A размечает их редкостью).

- [ ] **Step 5: Сверить имена и посчитать**

```bash
grep -oE 'name = "[a-z0-9_]+"' game/scripts/vscripts/osc/config/ability_pools.lua | cut -d'"' -f2 | sort -u | comm -23 - "<scratch>/names.txt"
grep -oE 'hero = "[a-z_]+"' game/scripts/vscripts/osc/config/ability_pools.lua | sort -u | wc -l
```

Expected: первая — снова только `drunk`, `lost`, `ogre_magi_casino`; вторая — число героев «после» (в отчёт; при всех кандидатах из таблиц ≈ 80).

- [ ] **Step 6: todo.md**

В `game/todo.md` (Edit tool) перед разделом `Финальная проверка после каждого этапа` вставить:

```
Кандидаты в пул — на проверку
- ancient_apparition_ice_blast — парная активация с ancient_apparition_ice_blast_release: оформить linked и проверить в игре.
- naga_siren_song_of_the_siren — отмена отдельной способностью naga_siren_song_of_the_siren_cancel: проверить linked.
- keeper_of_the_light_illuminate — ченнел с отдельным завершением keeper_of_the_light_illuminate_end.
- alchemist_unstable_concoction — бросок отдельной способностью alchemist_unstable_concoction_throw.
- primal_beast_onslaught — разгон с отдельным отпусканием.
- tiny_toss, hoodwink_bushwhack — зависят от окружения (юнит рядом, деревья): проверить, не бесполезны ли.
- warlock_rain_of_chaos, dark_seer_wall_of_replica — управляемые голем и иллюзии.
- Время загрузки после расширения пула (прекэш героев целиком): если выросло заметно — прекэшить только частицы и звуки способностей.
```

Дописать сюда же любых кандидатов, отброшенных на Step 3, с причиной.

- [ ] **Step 7: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `test_tags.every_pool_entry_has_valid_tags` PASS (теги новых записей из `OSC_ABILITY_TAGS`, ничего не убрано), `test_tags.pool_entries_unique_and_well_formed` PASS, `RESULT: OK`.

- [ ] **Step 8: Commit**

```bash
git add game/scripts/vscripts/osc/config/ability_pools.lua game/todo.md
git commit -m "feat: expand ability pools with 40 abilities and 20 ultimates" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task B3: Справка «?»

**Files:**
- Create: `content/panorama/scripts/custom_game/osc_help.js`
- Modify: `content/panorama/layout/custom_game/osc_hud.xml`
- Modify: `content/panorama/scripts/custom_game/osc_hud.js`
- Modify: `content/panorama/styles/custom_game/osc_hud.css` (в конец)
- Modify: `game/resource/addon_russian.txt`, `game/resource/addon_english.txt`

**Interfaces:**
- Produces: `OSC.Help = { Init, Toggle, Close }`, `#HelpButton`, `#HelpPanel` (класс `Visible`), ключи `osc_hud_help_*`.

Тексты разделов лежат прямо в XML (`text="#osc_hud_help_..."`): так `run_tests.py` («Localization») находит каждый ключ и сверяет его с обоими `addon_*.txt`. Собирать ключи в JS из строки `"#osc_hud_help_" + id` нельзя — проверка их не увидит.

- [ ] **Step 1: osc_help.js**

```js
"use strict";

var OSC = OSC || {};

// Справка по правилам режима: кнопка «?» рядом с Хаос-лавкой открывает и
// закрывает панель, тексты разделов — в osc_hud.xml (ключи osc_hud_help_*).
// Только клиент: сервер о справке не знает.
OSC.Help = (function () {
  function SetOpen(open) {
    $("#HelpPanel").SetHasClass("Visible", open);
  }

  function Toggle() {
    SetOpen(!$("#HelpPanel").BHasClass("Visible"));
  }

  function Close() {
    SetOpen(false);
  }

  function Init() {
    SetOpen(false);
  }

  return { Init: Init, Toggle: Toggle, Close: Close };
})();
```

- [ ] **Step 2: osc_hud.xml**

В `<scripts>` после строки `<include src="file://{resources}/scripts/custom_game/osc_chaos_shop.js" />` добавить:

```xml
        <include src="file://{resources}/scripts/custom_game/osc_help.js" />
```

Перед строкой `        <!-- Хаос-лавка (osc_chaos_shop.js): кнопка рядом со стандартным` вставить:

```xml
        <!-- Справка (osc_help.js): кнопка «?» рядом с Хаос-лавкой и панель правил -->
        <Button id="HelpButton" class="OSCButton" onactivate="OSC.Help.Toggle()">
            <Label text="#osc_hud_help_button" />
        </Button>
        <Panel id="HelpPanel" class="OSCSurface OSCChaos" hittest="true">
            <Label id="HelpTitle" class="OSCTextTitle OSCChaosText" text="#osc_hud_help_title" />
            <Panel id="HelpSections">
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_rotation_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_rotation_text" />
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_anchor_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_anchor_text" />
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_rarity_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_rarity_text" />
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_chaos_rounds_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_chaos_rounds_text" />
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_chaos_shop_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_chaos_shop_text" />
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_casino_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_casino_text" />
                <Label class="HelpHeading OSCTextBody OSCBold OSCGold" text="#osc_hud_help_chaos_sphere_title" />
                <Label class="HelpText OSCTextSmall" text="#osc_hud_help_chaos_sphere_text" />
            </Panel>
            <Button id="HelpClose" class="OSCButton" onactivate="OSC.Help.Close()">
                <Label text="#osc_hud_help_close" />
            </Button>
        </Panel>

```

- [ ] **Step 3: osc_hud.js**

После строки `  OSC.ChaosShop.Init();` добавить `  OSC.Help.Init();`.

- [ ] **Step 4: CSS (в самый конец osc_hud.css)**

```css

/* ================= Справка ================= */

/* Слева от кнопки Хаос-лавки (#ChaosShopButton: margin-right 16px,
   min-width 140px, margin-bottom 290px); отступы подогнать в игре */
#HelpButton {
  width: 34px;
  height: 34px;
  horizontal-align: right;
  vertical-align: bottom;
  margin-right: 164px;
  margin-bottom: 290px;
}

#HelpButton Label {
  font-size: 18px;
  horizontal-align: center;
  vertical-align: center;
}

#HelpPanel {
  width: 520px;
  height: 560px;
  padding: 16px;
  horizontal-align: center;
  vertical-align: center;
  flow-children: down;
  visibility: collapse;
}

#HelpPanel.Visible {
  visibility: visible;
}

#HelpTitle {
  horizontal-align: center;
}

#HelpSections {
  width: 100%;
  height: fill-parent-flow(1.0);
  margin: 12px 0px;
  flow-children: down;
  overflow: squish scroll;
}

.HelpHeading {
  width: 100%;
  margin-top: 10px;
}

.HelpText {
  width: 100%;
  margin-top: 2px;
}

#HelpClose {
  horizontal-align: center;
}
```

- [ ] **Step 5: Локализация**

`addon_russian.txt`, после строки `		"osc_hud_title_storm_chaser_desc"		"Нанёс {d:value} урона в хаос-раундах"` (Edit tool, два таба, таб между ключом и значением):

```
		"osc_hud_help_button"	"?"
		"osc_hud_help_title"	"КАК ИГРАТЬ"
		"osc_hud_help_close"	"Закрыть"
		"osc_hud_help_rotation_title"	"Ротация и выбор из трёх"
		"osc_hud_help_rotation_text"	"Через равные промежутки все герои получают новую основную способность. Перед сменой вам предложат три варианта — кликните по любому; не успели выбрать — достанется случайный из трёх. Ультимейт появляется с 6-го уровня."
		"osc_hud_help_anchor_title"	"Якорь"
		"osc_hud_help_anchor_text"	"Предмет из Хаос-лавки. Используйте его — и ближайшая смена способностей вас пропустит: текущая способность останется ещё на одну ротацию."
		"osc_hud_help_rarity_title"	"Редкость"
		"osc_hud_help_rarity_text"	"Способности бывают обычными, редкими (синяя рамка) и легендарными (золотая рамка). Редкость влияет только на шанс выпадения, а не на силу. О каждой выпавшей легендарке узнают все игроки."
		"osc_hud_help_chaos_rounds_title"	"Хаос-раунды"
		"osc_hud_help_chaos_rounds_text"	"Время от времени матч ненадолго меняет правила: быстрые перезарядки, бесплатная мана, золотой дождь, непогода, странности с экраном и мышью. О раунде предупреждает панель справа вверху."
		"osc_hud_help_chaos_shop_title"	"Хаос-лавка"
		"osc_hud_help_chaos_shop_text"	"Кнопка рядом со стандартным магазином. Здесь продаются предметы режима: реролл ультимейта (ограниченное число на команду) и Якорь. Если вы не у фонтана, покупку доставит курьер."
		"osc_hud_help_casino_title"	"Казино Огра"
		"osc_hud_help_casino_text"	"Огр-маг ставит игровой автомат. Сыграть может любой герой: подойдите к автомату, кликните по нему и сделайте ставку золотом или предметом."
		"osc_hud_help_chaos_sphere_title"	"Сфера хаоса"
		"osc_hud_help_chaos_sphere_text"	"Падает с Рошана. Примените её и выберите: легендарный ультимейт на выбор или новую случайную способность каждому врагу."
```

`addon_english.txt`, после строки `			"osc_hud_title_storm_chaser_desc"	...` (три таба):

```
			"osc_hud_help_button"	"?"
			"osc_hud_help_title"	"HOW TO PLAY"
			"osc_hud_help_close"	"Close"
			"osc_hud_help_rotation_title"	"Rotation and choice of three"
			"osc_hud_help_rotation_text"	"At regular intervals every hero gets a new main ability. Before the change you are offered three options — click any of them; if you do not pick in time, you get a random one of the three. The ultimate unlocks at level 6."
			"osc_hud_help_anchor_title"	"Anchor"
			"osc_hud_help_anchor_text"	"An item from the Chaos Shop. Use it and the next ability rotation skips you: your current ability stays for one more rotation."
			"osc_hud_help_rarity_title"	"Rarity"
			"osc_hud_help_rarity_text"	"Abilities are common, rare (blue frame) or legendary (gold frame). Rarity only changes how often an ability drops, not how strong it is. Every player hears about each legendary drop."
			"osc_hud_help_chaos_rounds_title"	"Chaos rounds"
			"osc_hud_help_chaos_rounds_text"	"From time to time the match changes its rules for a short while: fast cooldowns, free mana, gold rain, bad weather, tricks with the screen and the mouse. The panel at the top right warns you in advance."
			"osc_hud_help_chaos_shop_title"	"Chaos Shop"
			"osc_hud_help_chaos_shop_text"	"The button next to the regular shop. It sells the mode's items: the ultimate reroll (limited per team) and the Anchor. If you are away from the fountain, the courier delivers your purchase."
			"osc_hud_help_casino_title"	"Ogre Casino"
			"osc_hud_help_casino_text"	"Ogre Magi places a slot machine. Any hero can play: walk up to the machine, click it and bet gold or an item."
			"osc_hud_help_chaos_sphere_title"	"Chaos Sphere"
			"osc_hud_help_chaos_sphere_text"	"Dropped by Roshan. Use it and choose: a legendary ultimate of your choice or a new random ability for every enemy."
```

(Тексты без чисел из конфига, кроме общеизвестного «6-й уровень» ультимейта.)

- [ ] **Step 6: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `JS syntax: OK`, `Localization: OK` (17 новых ключей есть в обоих файлах), `RESULT: OK`.

- [ ] **Step 7: Commit**

```bash
git add content/panorama/scripts/custom_game/osc_help.js content/panorama/layout/custom_game/osc_hud.xml content/panorama/scripts/custom_game/osc_hud.js content/panorama/styles/custom_game/osc_hud.css game/resource/addon_russian.txt game/resource/addon_english.txt
git commit -m "feat: help panel with mode rules behind the ? button" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Отчёт трека B

Что сделано, список файлов, итог `run_tests.py`; **число уникальных героев в пулах до (41) и после**; какие кандидаты отброшены и почему (они же в `todo.md`). Проверить в игре: несколько ротаций с `-reroll` (новые способности работают, в логе нет `OSC_ABILITY_POOL: removed`), время загрузки карты до/после; кнопка «?» рядом с Хаос-лавкой, панель открывается/закрывается кнопкой «?» и «Закрыть», прокрутка, тексты на русском и английском.

---

## Трек C — Сфера хаоса (Часть 3)

### Владение файлами трека C

Только эти файлы:

- `game/scripts/vscripts/osc/config/config.lua` — блок после `CHAOS_SHOP_ITEMS = { ... },`
- `game/scripts/vscripts/osc/config/notifications.lua` — два типа в разделе «События игроков» после `courier_wrong_delivery`
- `game/scripts/vscripts/osc/core/hero_state.lua` — поле `sphere_offer` в `FIELDS`
- `game/scripts/vscripts/osc/core/game_mode.lua` — `SafeInit` после `ChaosShop`
- `game/scripts/vscripts/addon_game_mode.lua` — два `require` после `osc/systems/chaos_shop`
- Создать: `game/scripts/vscripts/osc/systems/chaos_sphere.lua`, `game/scripts/vscripts/osc/items/item_chaos_sphere.lua`
- `game/scripts/npc/npc_items_custom.txt` — новый блок в конце
- Создать: `content/panorama/scripts/custom_game/osc_chaos_sphere.js`
- `content/panorama/layout/custom_game/osc_hud.xml` — include после `osc_rotation_choice.js`; окно **после** `#ChaosShopPanel` и перед комментарием `<!-- Выбор следующей способности`
- `content/panorama/scripts/custom_game/osc_hud.js` — строка после `OSC.RotationChoice.Init();`
- `content/panorama/styles/custom_game/osc_hud.css` — раздел **перед** строкой `/* ---------- Хаос-раунд ---------- */`
- `game/resource/addon_russian.txt`, `addon_english.txt` — блок после `osc_anchor_err_disabled`
- `tools/tests/run_tests.py` — `LOC_PREFIXES`, `NOT_LOC_KEYS`
- `tools/tests/harness.lua`, `tools/tests/test_reload.lua`
- Создать: `tools/tests/test_chaos_sphere.lua`

Связь с треком A: `PickCandidates(hero, "ultimate", n, { rarity = "legendary" })` — в этом worktree `opts.rarity` игнорируется, тесты C на редкость не опираются. Редкость варианта для клиента берётся через `OSC_AbilitySelection.GetRarity`, если она есть (после слияния A), иначе `"common"`. Карточки окна используют классы `ChoiceCard` / `ChoiceIcon` / `ChoiceName` выбора из трёх и классы `RarityRare` / `RarityLegendary` — рамки появятся сами после слияния A.

### Контракт трека C

| Что | Значение |
| --- | --- |
| Модуль | `osc/systems/chaos_sphere.lua`, глобал `OSC_ChaosSphere` = `{ listening, IsEnabled, Init, OnEntityKilled(event), Offer(hero, item), OnPick(sourceIndex, event) }` |
| Предмет | `item_osc_chaos_sphere`, `osc/items/item_chaos_sphere.lua`, `OnSpellStart` → `OSC_ChaosSphere.Offer(self:GetCaster(), self)` |
| Конфиг | `CHAOS_SPHERE_ENABLED = true`, `CHAOS_SPHERE_ULTIMATE_CHOICES = 3`, `CHAOS_SPHERE_MIN_LEVEL = 6`, `CHAOS_SPHERE_DROP_OFFSET = 150` |
| Состояние | `OSC_HeroState.Get(hero).sphere_offer = { item = <entindex>, options = { имена }, ultimate_allowed = bool }` |
| сервер → игрок | `osc_sphere_offer { options = { [i] = { name, label, rarity } }, ultimate_allowed = 1 \| 0, min_level }` |
| игрок → сервер | `osc_sphere_pick { mode = "ultimate" \| "enemies" \| "cancel", ability }` |
| Отказы | лог `OSC_ClientCommands.LogRefusal("Chaos sphere pick", id, reason)`; клиенту `osc_hud_error { message = "osc_sphere_err_disabled" \| "_main_hero" \| "_level" \| "_no_item" }` |
| Лента | типы `chaos_sphere_dropped` (`#osc_notify_chaos_sphere_dropped`), `chaos_sphere_enemies` (`#osc_notify_chaos_sphere_enemies`, `{s:player_name}`) — всем |
| Panorama | `osc_chaos_sphere.js`, `OSC.ChaosSphere = { Init, ChooseUltimate, ChooseEnemies, Cancel }`; `#ChaosSpherePanel` (классы `Visible`, `Cards`) |

Решения сверх спека:
- `CHAOS_SPHERE_DROP_OFFSET` — «небольшое смещение» от Рошана вынесено в конфиг (правило «все числа — в конфиг»).
- Уровень для «ультимейта» проверяется **в момент выбора** по текущему уровню героя (уровень только растёт; герой, взявший 6-й с открытым окном, не наказан); `ultimate_allowed` в состоянии и событии — подсказка для клиента.
- В режиме `enemies` пропускаются враги без `initialized` (герой ещё не получил способности режима — как в ротации) и с «Якорем»; выдача каждому врагу в `pcall`, ошибка одного не мешает другим.
- Повторное применение сферы с открытым окном перезаписывает предложение новыми вариантами.
- Иконка `item_ultimate_orb` (сфера — orb), плюс `"ItemKillable" "0"`, чтобы сферу на земле нельзя было уничтожить атакой.

### Task C1: Конфиг, KV предмета, тестовый раннер, локализация

**Files:**
- Modify: `game/scripts/vscripts/osc/config/config.lua`
- Modify: `game/scripts/npc/npc_items_custom.txt`
- Modify: `tools/tests/run_tests.py:29-40`
- Modify: `game/resource/addon_russian.txt` (после строки 54), `game/resource/addon_english.txt` (после строки 51)

**Interfaces:**
- Produces: ключи конфига, KV предмета, все ключи локализации трека.

- [ ] **Step 1: config.lua**

После строки `    },` которая закрывает `CHAOS_SHOP_ITEMS = {` (сразу перед `    -- Статистика матча по игрокам`) вставить:

```lua
    -- Сфера хаоса (osc/systems/chaos_sphere.lua): падает с Рошана, владелец
    -- выбирает легендарный ультимейт (из CHAOS_SPHERE_ULTIMATE_CHOICES) или
    -- новую случайную способность всем врагам
    CHAOS_SPHERE_ENABLED = true,
    CHAOS_SPHERE_ULTIMATE_CHOICES = 3,
    CHAOS_SPHERE_MIN_LEVEL = 6,       -- для варианта «ультимейт»
    CHAOS_SPHERE_DROP_OFFSET = 150,   -- на сколько от Рошана падает сфера
```

- [ ] **Step 2: npc_items_custom.txt**

Перед последней строкой файла `}` (после блока `item_osc_anchor`) вставить (табы, как у соседних блоков):

```
	// Сфера хаоса: падает с Рошана (osc/systems/chaos_sphere.lua), не продаётся.
	// При использовании открывает выбор режима, расходуется после выбора
	"item_osc_chaos_sphere"
	{
		"BaseClass"                 "item_lua"
		"ScriptFile"                "scripts/vscripts/osc/items/item_chaos_sphere.lua"
		"AbilityTextureName"        "item_ultimate_orb"
		"AbilityBehavior"           "DOTA_ABILITY_BEHAVIOR_NO_TARGET"
		"AbilityCooldown"           "0"
		"ItemCost"                  "0"
		"ItemPurchasable"           "0"
		"ItemSellable"              "0"
		"ItemDroppable"             "0"
		"ItemKillable"              "0"
		"ItemInitialCharges"        "1"
		"ItemStackable"             "0"
		"ItemShareability"          "ITEM_NOT_SHAREABLE"
	}
```

(Перед вставкой — пустая строка-разделитель, как между существующими блоками.)

- [ ] **Step 3: run_tests.py**

В `LOC_PREFIXES` после `"osc_shop_",` добавить `"osc_sphere_",`. Строку `NOT_LOC_KEYS = {"osc_hud_error", "osc_shop_buy", "osc_shop_result"}` заменить на:

```python
NOT_LOC_KEYS = {"osc_hud_error", "osc_shop_buy", "osc_shop_result", "osc_sphere_offer", "osc_sphere_pick"}
```

(Ключи `osc_notify_chaos_sphere_*` уже покрыты префиксом `osc_notify_`.)

- [ ] **Step 4: Локализация**

`addon_russian.txt`, после строки `		"osc_anchor_err_disabled"	"Якорь отключён"` (Edit tool, два таба):

```
		"DOTA_Tooltip_Ability_item_osc_chaos_sphere"	"Сфера хаоса"
		"DOTA_Tooltip_Ability_item_osc_chaos_sphere_Description"	"Падает с Рошана. При использовании выберите: легендарный ультимейт на выбор или новую случайную способность каждому врагу. Расходуется после выбора."
		"osc_sphere_title"	"СФЕРА ХАОСА"
		"osc_sphere_mode_ultimate"	"Легендарный ультимейт"
		"osc_sphere_mode_enemies"	"Хаос врагам"
		"osc_sphere_level_hint"	"Ультимейт — с {d:level}-го уровня"
		"osc_sphere_choose"	"Выберите ультимейт"
		"osc_sphere_cancel"	"Отмена"
		"osc_sphere_err_disabled"	"Сфера хаоса отключена"
		"osc_sphere_err_main_hero"	"Сферу может использовать только сам герой"
		"osc_sphere_err_level"	"Слишком низкий уровень для ультимейта"
		"osc_sphere_err_no_item"	"Сферы хаоса больше нет в инвентаре"
		"osc_notify_chaos_sphere_dropped"	"Рошан повержен — выпала Сфера хаоса!"
		"osc_notify_chaos_sphere_enemies"	"{s:player_name} обрушивает хаос: у всех врагов новая способность!"
```

`addon_english.txt`, после строки `			"osc_anchor_err_disabled"	"Anchor is disabled"` (три таба):

```
			"DOTA_Tooltip_Ability_item_osc_chaos_sphere"	"Chaos Sphere"
			"DOTA_Tooltip_Ability_item_osc_chaos_sphere_Description"	"Dropped by Roshan. On use, choose: a legendary ultimate of your choice or a new random ability for every enemy. Consumed once you choose."
			"osc_sphere_title"	"CHAOS SPHERE"
			"osc_sphere_mode_ultimate"	"Legendary ultimate"
			"osc_sphere_mode_enemies"	"Chaos to enemies"
			"osc_sphere_level_hint"	"Ultimate from level {d:level}"
			"osc_sphere_choose"	"Choose an ultimate"
			"osc_sphere_cancel"	"Cancel"
			"osc_sphere_err_disabled"	"Chaos Sphere is disabled"
			"osc_sphere_err_main_hero"	"Only the hero itself can use the Sphere"
			"osc_sphere_err_level"	"Level too low for the ultimate"
			"osc_sphere_err_no_item"	"The Chaos Sphere is no longer in your inventory"
			"osc_notify_chaos_sphere_dropped"	"Roshan has fallen — a Chaos Sphere dropped!"
			"osc_notify_chaos_sphere_enemies"	"{s:player_name} unleashes chaos: every enemy gets a new ability!"
```

- [ ] **Step 5: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `Localization: OK` (ключи есть, но код их ещё не использует — это нормально), `RESULT: OK`.

- [ ] **Step 6: Commit**

```bash
git add game/scripts/vscripts/osc/config/config.lua game/scripts/npc/npc_items_custom.txt tools/tests/run_tests.py game/resource/addon_russian.txt game/resource/addon_english.txt
git commit -m "feat: chaos sphere config, item KV and localization" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task C2: Моки и падающие тесты

**Files:**
- Modify: `tools/tests/harness.lua` (`H`, `H.NewItem`)
- Create: `tools/tests/test_chaos_sphere.lua`

**Interfaces:**
- Produces (harness): `H.drops` — `{ { position, item } }`; `CreateItemOnPositionSync(position, item)`; у предметов `H.NewItem` поле `index` (с 1001), метод `item:entindex()` и запись в `H.entities[index]` (для `EntIndexToHScript`).

- [ ] **Step 1: harness.lua**

1. В таблице `H = { ... }` после строки `    itemCosts = {}, -- ItemCost предметов для GetItemCost` добавить:

```lua
    drops = {}, -- предметы на земле: { position, item } (CreateItemOnPositionSync)
```

2. Заменить функцию `H.NewItem` целиком на:

```lua
-- Индексы предметов не пересекаются с юнитами, которые тесты кладут в
-- H.entities руками (там малые числа)
local itemCounter = 1000

function H.NewItem(name)
    itemCounter = itemCounter + 1
    local item = {
        name = name,
        index = itemCounter,
        IsNull = function() return false end,
        GetAbilityName = function(self) return self.name end,
        entindex = function(self) return self.index end,
    }
    H.entities[item.index] = item
    return item
end

function CreateItemOnPositionSync(position, item)
    table.insert(H.drops, { position = position, item = item })
    return {}
end
```

- [ ] **Step 2: Тесты**

Создать `tools/tests/test_chaos_sphere.lua`:

```lua
-- Сфера хаоса: выпадение с Рошана, предложение, оба режима, отмена и отказы

local ULTS = { "test_ult_a", "test_ult_b", "test_ult_c", "test_ult_d" }
local BASICS = { "test_q1", "test_q2", "test_q3" }
local TAGS = { "damage", "disable", "mobility", "support" }

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/chaos_sphere")
    require("osc/items/item_chaos_sphere")
    OSC_ABILITY_POOL, OSC_ULTIMATE_POOL = {}, {}
    for index, name in ipairs(BASICS) do
        H.DefineAbility(name)
        table.insert(OSC_ABILITY_POOL, { name = name, hero = "npc_dota_hero_axe",
            label = name, tags = { TAGS[index] } })
    end
    for index, name in ipairs(ULTS) do
        H.DefineAbility(name, { ultimate = true })
        table.insert(OSC_ULTIMATE_POOL, { name = name, hero = "npc_dota_hero_axe",
            label = "Label " .. name, tags = { TAGS[index] }, rarity = "legendary" })
    end
    OSC_ChaosSphere.Init()
end

-- Основной герой игрока с основной способностью test_q1
local function addHero(playerID, team, opts)
    opts = opts or {}
    local hero = H.NewHero({ playerID = playerID, team = team, level = opts.level or 6,
        abilities = { "test_q1" } })
    H.AddPlayer(playerID, hero)
    local state = OSC_HeroState.Get(hero)
    state.ability = "test_q1"
    state.initialized = true
    state.anchored = opts.anchored == true
    return hero
end

local function giveSphere(hero)
    local item = H.NewItem("item_osc_chaos_sphere")
    hero.items[0] = item
    return item
end

local function pick(playerID, mode, ability)
    H.listeners.osc_sphere_pick(playerID + 1, { PlayerID = playerID, mode = mode, ability = ability })
end

local function kill(index, unitName)
    H.entities[index] = {
        IsNull = function() return false end,
        GetUnitName = function() return unitName end,
        GetAbsOrigin = function() return Vector(100, 200, 0) end,
    }
    H.FireGameEvent("entity_killed", { entindex_killed = index })
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

-- Ультимейт пула, которого нет среди вариантов
local function notOffered(hero)
    for _, name in ipairs(ULTS) do
        if not contains(OSC_HeroState.Get(hero).sphere_offer.options, name) then
            return name
        end
    end
end

return {
    roshan_drops_sphere = function()
        setup()
        kill(50, "npc_dota_roshan")
        H.eq(#H.drops, 1, "one item dropped")
        H.eq(H.drops[1].item.name, "item_osc_chaos_sphere", "sphere")
        H.eq(H.drops[1].position, Vector(100 + OSC_CONFIG.CHAOS_SPHERE_DROP_OFFSET, 200, 0),
            "next to Roshan")
        H.eq(H.lastEvent("osc_notification").data.token, "#osc_notify_chaos_sphere_dropped",
            "announced")
    end,

    other_unit_drops_nothing = function()
        setup()
        kill(51, "npc_dota_neutral_kobold")
        H.eq(#H.drops, 0, "no sphere from a kobold")
    end,

    disabled_drops_nothing = function()
        setup()
        OSC_CONFIG.CHAOS_SPHERE_ENABLED = false
        kill(50, "npc_dota_roshan")
        H.eq(#H.drops, 0, "flag off")
    end,

    use_item_sends_offer = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        item.GetCaster = function() return hero end

        item_osc_chaos_sphere.OnSpellStart(item)

        local offer = OSC_HeroState.Get(hero).sphere_offer
        H.truthy(offer, "offer stored")
        H.eq(offer.item, item.index, "item entindex")
        H.eq(#offer.options, OSC_CONFIG.CHAOS_SPHERE_ULTIMATE_CHOICES, "three options")
        H.eq(offer.ultimate_allowed, true, "level 6 allowed")
        local event = H.lastEvent("osc_sphere_offer")
        H.eq(event.player.id, 0, "sent to the owner")
        H.eq(event.data.ultimate_allowed, 1, "allowed flag for the client")
        H.eq(event.data.min_level, OSC_CONFIG.CHAOS_SPHERE_MIN_LEVEL, "min level")
        H.eq(#event.data.options, 3, "client options")
        H.truthy(contains(ULTS, event.data.options[1].name), "an ultimate")
        H.eq(event.data.options[1].label, "Label " .. event.data.options[1].name, "label")
        H.truthy(event.data.options[1].rarity, "rarity")
        H.eq(hero.items[0], item, "item not consumed by use")
    end,

    low_level_offer_disallows_ultimate = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS, { level = 5 })
        OSC_ChaosSphere.Offer(hero, giveSphere(hero))
        H.eq(OSC_HeroState.Get(hero).sphere_offer.ultimate_allowed, false, "state")
        H.eq(H.lastEvent("osc_sphere_offer").data.ultimate_allowed, 0, "client")
    end,

    not_main_hero_refused = function()
        setup()
        addHero(0, DOTA_TEAM_GOODGUYS)
        local illusion = H.NewHero({ playerID = 0, copy = "illusion", level = 6 })

        local ok = OSC_ChaosSphere.Offer(illusion, giveSphere(illusion))

        H.eq(ok, false, "refused")
        H.eq(OSC_HeroState.Get(illusion).sphere_offer, nil, "no offer state")
        H.eq(H.lastEvent("osc_sphere_offer"), nil, "no offer event")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_sphere_err_main_hero", "error shown")
    end,

    ultimate_pick_gives_and_consumes = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)
        local chosen = OSC_HeroState.Get(hero).sphere_offer.options[2]

        pick(0, "ultimate", chosen)

        H.eq(OSC_HeroState.Get(hero).ultimate, chosen, "ultimate given")
        H.eq(hero.items[0], nil, "sphere removed from inventory")
        H.eq(item._removed, true, "item removed")
        H.eq(OSC_HeroState.Get(hero).sphere_offer, nil, "offer closed")
    end,

    ultimate_not_offered_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "ultimate", notOffered(hero))

        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "nothing given")
        H.eq(hero.items[0], item, "sphere kept")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: not offered"), "refusal logged")
    end,

    ultimate_low_level_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS, { level = 5 })
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "ultimate", OSC_HeroState.Get(hero).sphere_offer.options[1])

        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "nothing given")
        H.eq(hero.items[0], item, "sphere kept")
        H.truthy(OSC_HeroState.Get(hero).sphere_offer, "offer stays: enemies still possible")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_sphere_err_level", "error shown")
    end,

    enemies_get_new_ability = function()
        setup()
        local owner = addHero(0, DOTA_TEAM_GOODGUYS)
        local ally = addHero(1, DOTA_TEAM_GOODGUYS)
        local enemy = addHero(2, DOTA_TEAM_BADGUYS)
        local anchored = addHero(3, DOTA_TEAM_BADGUYS, { anchored = true })
        local item = giveSphere(owner)
        OSC_ChaosSphere.Offer(owner, item)

        pick(0, "enemies")

        H.truthy(OSC_HeroState.Get(enemy).ability ~= "test_q1", "enemy got a new ability")
        H.eq(OSC_HeroState.Get(anchored).ability, "test_q1", "anchored enemy untouched")
        H.eq(OSC_HeroState.Get(anchored).anchored, true, "anchor not spent")
        H.eq(OSC_HeroState.Get(ally).ability, "test_q1", "ally untouched")
        H.eq(OSC_HeroState.Get(owner).ability, "test_q1", "owner untouched")
        H.eq(item._removed, true, "sphere consumed")
        local feed = H.lastEvent("osc_notification")
        H.eq(feed.data.token, "#osc_notify_chaos_sphere_enemies", "announced")
        H.eq(feed.player, nil, "to everyone")
        H.eq(feed.data.params.player_id, "0", "owner named")
    end,

    cancel_keeps_item = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "cancel")
        H.eq(OSC_HeroState.Get(hero).sphere_offer, nil, "offer closed")
        H.eq(hero.items[0], item, "sphere kept")

        pick(0, "ultimate", ULTS[1])
        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "no pick after cancel")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: no offer"), "refusal logged")
    end,

    pick_without_offer_refused = function()
        setup()
        addHero(0, DOTA_TEAM_GOODGUYS)
        local enemy = addHero(2, DOTA_TEAM_BADGUYS)

        pick(0, "enemies")

        H.eq(OSC_HeroState.Get(enemy).ability, "test_q1", "enemy untouched")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: no offer"), "refusal logged")
    end,

    pick_without_item_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        OSC_ChaosSphere.Offer(hero, giveSphere(hero))
        hero.items[0] = nil -- сферу переложили в тайник, продали или выкинули

        pick(0, "ultimate", OSC_HeroState.Get(hero).sphere_offer.options[1])

        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "nothing given")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_sphere_err_no_item", "error shown")
    end,

    forged_mode_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "everything")

        H.eq(hero.items[0], item, "sphere kept")
        H.truthy(OSC_HeroState.Get(hero).sphere_offer, "offer kept")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: invalid_mode"), "refusal logged")
    end,
}
```

Важно: `OSC_ClientCommands.LogRefusal` пишет в лог не чаще раза в `CLIENT_REFUSAL_LOG_INTERVAL` секунд на пару канал + игрок. В каждом тесте выше проверяется только **первый** отказ, поэтому `H.time` двигать не нужно; если добавляете тест с двумя отказами подряд — между ними `H.time = H.time + 10`.

- [ ] **Step 3: Запустить тесты — убедиться, что падают**

Run: `python tools/tests/run_tests.py`
Expected: все `test_chaos_sphere.*` FAIL с `module 'osc/systems/chaos_sphere' not found`; остальные тесты PASS (новый `H.NewItem` их не ломает); `RESULT: FAIL (14 problems)`.

### Task C3: Система OSC_ChaosSphere, предмет и подключение

**Files:**
- Create: `game/scripts/vscripts/osc/systems/chaos_sphere.lua`
- Create: `game/scripts/vscripts/osc/items/item_chaos_sphere.lua`
- Modify: `game/scripts/vscripts/osc/config/notifications.lua` (после блока `courier_wrong_delivery = { ... },`)
- Modify: `game/scripts/vscripts/osc/core/hero_state.lua` (`FIELDS`, после `pending_choices`)
- Modify: `game/scripts/vscripts/osc/core/game_mode.lua:31` (после `SafeInit("ChaosShop", OSC_ChaosShop)`)
- Modify: `game/scripts/vscripts/addon_game_mode.lua:22` (после `require("osc/systems/chaos_shop")`)
- Modify: `tools/tests/test_reload.lua` (`MODULES`)

**Interfaces:**
- Consumes: `OSC_ClientCommands.Check/OneOf/LogRefusal`, `OSC_Notifications.Notify/PlayerEvent`, `OSC_Heroes.IsValid/IsMainHero/ForEachPlayerHero`, `OSC_Anchor.IsActive`, `OSC_AbilitySelection.PickCandidates/FindEntry/GetRarity?`, `OSC_Abilities.Give/GiveRandom`; моки C2.
- Produces: контракт трека C (таблица выше).

- [ ] **Step 1: chaos_sphere.lua**

```lua
-- Сфера хаоса (флаг CHAOS_SPHERE_ENABLED): предмет item_osc_chaos_sphere
-- падает с Рошана. Владелец применяет её (item_chaos_sphere.lua -> Offer) и
-- в окне HUD (osc_chaos_sphere.js) выбирает одно из двух:
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

-- shortcut: GetRarity появляется со слиянием трека A (редкость); до него все
-- варианты "common". После слияния заменить на прямой вызов GetRarity.
local function Rarity(entry)
    if OSC_AbilitySelection.GetRarity then
        return OSC_AbilitySelection.GetRarity(entry)
    end
    return "common"
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
    if not OSC_Heroes.IsValid(killed) or not killed.GetUnitName
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
    local player = OSC_Heroes.IsValid(hero) and OwnerPlayer(hero) or nil
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
            options[index] = { name = entry.name, label = entry.label or entry.name, rarity = Rarity(entry) }
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
    if not OSC_Heroes.IsValid(item) or not HeroHasItem(hero, item) then
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
```

- [ ] **Step 2: item_chaos_sphere.lua**

```lua
require("osc/systems/chaos_sphere")

item_osc_chaos_sphere = class({})

-- Сама ничего не выдаёт: открывает выбор (OSC_ChaosSphere.Offer). Предмет
-- расходуется, когда игрок выбрал режим; отказ и отмена его не тратят
function item_osc_chaos_sphere:OnSpellStart()
    OSC_ChaosSphere.Offer(self:GetCaster(), self)
end
```

- [ ] **Step 3: Типы уведомлений**

В `osc/config/notifications.lua` после блока `courier_wrong_delivery = { ... },` вставить:

```lua
        -- Сфера хаоса (chaos_sphere.lua): выпала с Рошана; владелец выбрал «Хаос врагам»
        chaos_sphere_dropped = {
            category = "player",
            feed = { token = "#osc_notify_chaos_sphere_dropped", color = "#FFC23A" },
        },
        chaos_sphere_enemies = {
            category = "player",
            feed = { token = "#osc_notify_chaos_sphere_enemies", color = "#FF4D4D" },
        },
```

- [ ] **Step 4: hero_state.lua**

В `FIELDS` после записи `pending_choices` (перед закрывающей `}`) добавить:

```lua

    -- Сфера хаоса (chaos_sphere): открытый выбор после применения сферы
    { name = "sphere_offer",
      doc = "выбор сферы хаоса: { item = entindex, options = { имена }, ultimate_allowed }" },
```

- [ ] **Step 5: Подключение**

`game_mode.lua`: после строки `    SafeInit("ChaosShop", OSC_ChaosShop)` добавить `    SafeInit("ChaosSphere", OSC_ChaosSphere)`.

`addon_game_mode.lua`: после строки `require("osc/systems/chaos_shop")` добавить:

```lua
require("osc/systems/chaos_sphere")
require("osc/items/item_chaos_sphere")
```

`tools/tests/test_reload.lua`: в `MODULES` после строки `{ file = "osc/systems/chaos_shop", global = "OSC_ChaosShop" },` добавить `    { file = "osc/systems/chaos_sphere", global = "OSC_ChaosSphere" },`.

- [ ] **Step 6: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: все `test_chaos_sphere.*` PASS, `test_reload.*` PASS, `test_hero_state.*` PASS, `Localization: OK` (ключи `osc_sphere_err_*` и `osc_notify_chaos_sphere_*` найдены в коде и есть в обоих файлах), `Config reads: OK`, `RESULT: OK`.

- [ ] **Step 7: Commit**

```bash
git add game/scripts/vscripts/osc/systems/chaos_sphere.lua game/scripts/vscripts/osc/items/item_chaos_sphere.lua game/scripts/vscripts/osc/config/notifications.lua game/scripts/vscripts/osc/core/hero_state.lua game/scripts/vscripts/osc/core/game_mode.lua game/scripts/vscripts/addon_game_mode.lua tools/tests/harness.lua tools/tests/test_reload.lua tools/tests/test_chaos_sphere.lua
git commit -m "feat: chaos sphere drops from Roshan with ultimate or enemies choice" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task C4: Окно Сферы хаоса в HUD

**Files:**
- Create: `content/panorama/scripts/custom_game/osc_chaos_sphere.js`
- Modify: `content/panorama/layout/custom_game/osc_hud.xml`
- Modify: `content/panorama/scripts/custom_game/osc_hud.js`
- Modify: `content/panorama/styles/custom_game/osc_hud.css` (перед `/* ---------- Хаос-раунд ---------- */`)

**Interfaces:**
- Consumes: `osc_sphere_offer` (C3); CSS `.ChoiceCard`, `.ChoiceIcon`, `.ChoiceName`, `@keyframes OSCChoiceIn` (уже есть в `osc_hud.css`), классы редкости трека A (после слияния).
- Produces: `OSC.ChaosSphere = { Init, ChooseUltimate, ChooseEnemies, Cancel }`, `#ChaosSpherePanel`.

- [ ] **Step 1: osc_chaos_sphere.js**

```js
"use strict";

var OSC = OSC || {};

// Сфера хаоса: сервер шлёт osc_sphere_offer { options, ultimate_allowed,
// min_level }, когда игрок применил сферу. Окно: два режима; после
// «Легендарный ультимейт» — карточки вариантов (классы выбора из трёх и
// рамки редкости). Выбор уходит osc_sphere_pick { mode, ability }; решает
// сервер, отказы показывает OSC.HudError.
OSC.ChaosSphere = (function () {
  var ultimateAllowed = false;

  // Lua-таблица { "1": {...}, "2": {...} } -> массив по возрастанию ключей
  function ToOptionList(raw) {
    if (!raw) return [];
    return Object.keys(raw)
      .sort(function (a, b) {
        return Number(a) - Number(b);
      })
      .map(function (key) {
        var option = raw[key] || {};
        return {
          name: String(option.name || ""),
          label: String(option.label || ""),
          rarity: String(option.rarity || "common"),
        };
      })
      .filter(function (option) {
        return option.name !== "";
      });
  }

  // Имя способности из локализации Dota; если ключа нет — подпись из пула
  function AbilityDisplayName(option) {
    var token = "#DOTA_Tooltip_Ability_" + option.name;
    var localized = $.Localize(token);
    if (localized && localized !== token) return localized;
    return option.label || option.name;
  }

  function Send(mode, ability) {
    GameEvents.SendCustomGameEventToServer("osc_sphere_pick", {
      mode: mode,
      ability: ability || "",
    });
  }

  function Hide() {
    var panel = $("#ChaosSpherePanel");
    panel.RemoveClass("Visible");
    panel.RemoveClass("Cards");
    $.DispatchEvent("DOTAHideAbilityTooltip", panel);
  }

  function CreateCard(container, option) {
    var card = $.CreatePanel("Button", container, "");
    card.AddClass("ChoiceCard");
    card.SetHasClass("RarityRare", option.rarity === "rare");
    card.SetHasClass("RarityLegendary", option.rarity === "legendary");

    var image = $.CreatePanel("DOTAAbilityImage", card, "");
    image.AddClass("ChoiceIcon");
    image.abilityname = option.name;
    image.hittest = false;

    var nameLabel = $.CreatePanel("Label", card, "");
    nameLabel.AddClass("ChoiceName");
    nameLabel.AddClass("OSCTextSmall");
    nameLabel.AddClass("OSCBold");
    nameLabel.text = AbilityDisplayName(option);
    nameLabel.hittest = false;

    card.SetPanelEvent("onactivate", function () {
      Send("ultimate", option.name);
      Hide();
    });
    card.SetPanelEvent("onmouseover", function () {
      $.DispatchEvent("DOTAShowAbilityTooltip", card, option.name);
    });
    card.SetPanelEvent("onmouseout", function () {
      $.DispatchEvent("DOTAHideAbilityTooltip", card);
    });
  }

  function OnOffer(event) {
    if (!event) return;
    var options = ToOptionList(event.options);
    var levelOk = Number(event.ultimate_allowed) === 1;
    ultimateAllowed = levelOk && options.length > 0;

    var cards = $("#ChaosSphereCards");
    cards.RemoveAndDeleteChildren();
    options.forEach(function (option) {
      CreateCard(cards, option);
    });

    $("#ChaosSphereUltimateButton").enabled = ultimateAllowed;
    var hint = $("#ChaosSphereLevelHint");
    hint.SetDialogVariableInt("level", Number(event.min_level) || 0);
    hint.text = $.Localize("#osc_sphere_level_hint", hint);
    hint.SetHasClass("Hidden", levelOk);

    var panel = $("#ChaosSpherePanel");
    panel.RemoveClass("Cards");
    panel.AddClass("Visible");
  }

  function ChooseUltimate() {
    if (!ultimateAllowed) return;
    $("#ChaosSpherePanel").AddClass("Cards");
  }

  function ChooseEnemies() {
    Send("enemies");
    Hide();
  }

  function Cancel() {
    Send("cancel");
    Hide();
  }

  function Init() {
    GameEvents.Subscribe("osc_sphere_offer", OnOffer);
  }

  return {
    Init: Init,
    ChooseUltimate: ChooseUltimate,
    ChooseEnemies: ChooseEnemies,
    Cancel: Cancel,
  };
})();
```

- [ ] **Step 2: osc_hud.xml**

В `<scripts>` после строки `<include src="file://{resources}/scripts/custom_game/osc_rotation_choice.js" />` добавить:

```xml
        <include src="file://{resources}/scripts/custom_game/osc_chaos_sphere.js" />
```

После закрывающего `        </Panel>` блока `#ChaosShopPanel` и перед строкой `        <!-- Выбор следующей способности: последним, поверх затемнения казино` вставить:

```xml

        <!-- Сфера хаоса (osc_chaos_sphere.js): выбор режима, затем карточки
             ультимейтов (создаются из JS) -->
        <Panel id="ChaosSpherePanel" class="OSCSurface OSCChaos" hittest="true">
            <Label id="ChaosSphereTitle" class="OSCTextTitle OSCGold" text="#osc_sphere_title" />
            <Panel id="ChaosSphereModes">
                <Button id="ChaosSphereUltimateButton" class="OSCButton OSCButtonPrimary"
                    onactivate="OSC.ChaosSphere.ChooseUltimate()">
                    <Label text="#osc_sphere_mode_ultimate" />
                </Button>
                <Button id="ChaosSphereEnemiesButton" class="OSCButton OSCButtonPrimary"
                    onactivate="OSC.ChaosSphere.ChooseEnemies()">
                    <Label text="#osc_sphere_mode_enemies" />
                </Button>
            </Panel>
            <Label id="ChaosSphereLevelHint" class="OSCTextSmall OSCMuted" text="" />
            <Label id="ChaosSphereChoose" class="OSCTextSmall OSCCaps OSCBold OSCChaosText"
                text="#osc_sphere_choose" />
            <Panel id="ChaosSphereCards" />
            <Button id="ChaosSphereCancel" class="OSCButton" onactivate="OSC.ChaosSphere.Cancel()">
                <Label text="#osc_sphere_cancel" />
            </Button>
        </Panel>
```

`#ChoicePanel` остаётся последним (см. комментарий над ним).

- [ ] **Step 3: osc_hud.js**

После строки `  OSC.RotationChoice.Init();` добавить `  OSC.ChaosSphere.Init();`.

- [ ] **Step 4: CSS**

Перед строкой `/* ---------- Хаос-раунд ---------- */` вставить:

```css
/* ---------- Сфера хаоса ---------- */
/* Карточки — классы выбора из трёх (.ChoiceCard и рамки редкости) */
#ChaosSpherePanel {
  horizontal-align: center;
  vertical-align: center;
  padding: 16px;
  flow-children: down;
  visibility: collapse;
}

#ChaosSpherePanel.Visible {
  visibility: visible;
  animation-name: OSCChoiceIn;
  animation-duration: 0.25s;
  animation-timing-function: ease-out;
}

#ChaosSphereTitle {
  horizontal-align: center;
  margin-bottom: 12px;
}

#ChaosSphereModes {
  horizontal-align: center;
  flow-children: right;
}

#ChaosSphereModes Button {
  min-width: 180px;
  min-height: 40px;
  margin: 0px 6px;
}

#ChaosSphereModes Button:disabled {
  opacity: 0.45;
}

#ChaosSphereLevelHint {
  horizontal-align: center;
  margin-top: 6px;
}

#ChaosSphereLevelHint.Hidden,
#ChaosSphereChoose,
#ChaosSphereCards,
#ChaosSpherePanel.Cards #ChaosSphereModes,
#ChaosSpherePanel.Cards #ChaosSphereLevelHint {
  visibility: collapse;
}

#ChaosSpherePanel.Cards #ChaosSphereChoose {
  visibility: visible;
  horizontal-align: center;
  margin-bottom: 6px;
}

#ChaosSpherePanel.Cards #ChaosSphereCards {
  visibility: visible;
  horizontal-align: center;
  flow-children: right;
}

#ChaosSphereCancel {
  horizontal-align: center;
  margin-top: 12px;
}

```

- [ ] **Step 5: Запустить тесты**

Run: `python tools/tests/run_tests.py`
Expected: `JS syntax: OK`, `Localization: OK` (`osc_sphere_*` из XML/JS найдены, `osc_sphere_offer`/`osc_sphere_pick` исключены через `NOT_LOC_KEYS`), `RESULT: OK`.

- [ ] **Step 6: Commit**

```bash
git add content/panorama/scripts/custom_game/osc_chaos_sphere.js content/panorama/layout/custom_game/osc_hud.xml content/panorama/scripts/custom_game/osc_hud.js content/panorama/styles/custom_game/osc_hud.css
git commit -m "feat: chaos sphere choice window in HUD" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Отчёт трека C

Что сделано, список файлов, итог `run_tests.py`. Проверить в игре (`DEVELOPMENT_MODE` локально, не коммитить): убить Рошана — сфера лежит рядом с Аегисом, строка в ленте у всех; подобрать и применить — окно; «Легендарный ультимейт» → три карточки, клик — ультимейт выдан, сфера пропала; «Хаос врагам» — у врагов новая способность, у врага с «Якорем» нет, строка в ленте; «Отмена» — сфера осталась, повторное применение снова открывает окно; герой ниже 6-го уровня — кнопка ультимейта серая, под ней подсказка; иконка `item_ultimate_orb` и подсказка предмета; сферу нельзя продать, передать и уничтожить на земле.

---

## Слияние (координатор)

- [ ] **1. Порядок:** на `stage-4-rarity-sphere`, после зелёных отчётов всех трёх треков:

```bash
git merge --no-ff stage-4-rarity-sphere-a
python tools/tests/run_tests.py
git merge --no-ff stage-4-rarity-sphere-b
python tools/tests/run_tests.py
git merge --no-ff stage-4-rarity-sphere-c
python tools/tests/run_tests.py
```

A первым: после него `ValidatePools` проверяет редкость, и при слиянии B тест `test_tags.every_pool_entry_has_valid_tags` сразу проверит `rarity` новых записей B.

- [ ] **2. Известные точки пересечения** (треки вставляют код в разные места, поэтому ожидается автослияние; если git всё же даст конфликт — оставить обе стороны):

| Файл | A | B | C | Разрешение |
| --- | --- | --- | --- | --- |
| `osc/config/ability_pools.lua` | шапка, `OSC_ABILITY_RARITIES`, `rarity` у старых записей (последние записи пулов не тронуты) | новые записи после `tidehunter_kraken_shell` и `elder_titan_earth_splitter` | — | старые строки — версия A, новые строки — B целиком |
| `osc_hud.xml` | — | include `osc_help.js` после `osc_chaos_shop.js`; блок справки перед `<!-- Хаос-лавка` | include `osc_chaos_sphere.js` после `osc_rotation_choice.js`; окно после `#ChaosShopPanel` | оба блока; `#ChoicePanel` последним |
| `osc_hud.css` | раздел выбора (между `:hover` и `.Picked`) и после `#PopupIcon` | конец файла | перед `/* ---------- Хаос-раунд` | все три вставки |
| `osc_hud.js` | — | `OSC.Help.Init();` после `ChaosShop` | `OSC.ChaosSphere.Init();` после `RotationChoice` | обе строки |
| `osc/config/config.lua` | после `ROTATION_CHOICE_COUNT` | — | после `CHAOS_SHOP_ITEMS` | оба блока; `DEVELOPMENT_MODE = false` |
| `osc/config/notifications.lua` | `legendary_ability` в «Способности» | — | `chaos_sphere_*` в «События игроков» | оба |
| `addon_russian.txt` / `addon_english.txt` | после `osc_notify_ability_changed` | в конец Tokens | после `osc_anchor_err_disabled` | все строки; тест «Localization» сверит наборы ru/en |
| `tools/tests/run_tests.py` | — | — | `osc_sphere_` в `LOC_PREFIXES`, два события в `NOT_LOC_KEYS` | версия C |

Если конфликт в `LOC_PREFIXES`/`NOT_LOC_KEYS` всё же возникнет (кто-то добавил префикс), итог должен содержать: `"osc_sphere_"` в `LOC_PREFIXES` и `NOT_LOC_KEYS = {"osc_hud_error", "osc_shop_buy", "osc_shop_result", "osc_sphere_offer", "osc_sphere_pick"}`.

Конфликты в файлах с кириллицей разрешать только Edit tool.

- [ ] **3. Убрать временную развилку C.** В `osc/systems/chaos_sphere.lua` заменить функцию `Rarity` и комментарий `shortcut:` над ней прямым вызовом: в `Offer` писать `rarity = OSC_AbilitySelection.GetRarity(entry)`, функцию `Rarity` удалить. Добавить в `tools/tests/test_chaos_sphere.lua` тест интеграции:

```lua
    offer_prefers_legendary_ultimates = function()
        setup()
        OSC_ULTIMATE_POOL[1].rarity, OSC_ULTIMATE_POOL[2].rarity = nil, nil -- a, b — обычные
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        for _ = 1, 10 do
            OSC_ChaosSphere.Offer(hero, giveSphere(hero))
            local options = H.lastEvent("osc_sphere_offer").data.options
            H.eq(options[1].rarity, "legendary", "legendary first")
            H.eq(options[2].rarity, "legendary", "both legendary taken")
            H.eq(options[3].rarity, "common", "third filled from the rest")
        end
    end,
```

Run: `python tools/tests/run_tests.py` → `RESULT: OK`. Commit: `refactor: chaos sphere reads rarity directly` (+ строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

- [ ] **4. Полный прогон и проверки:**

```bash
python tools/tests/run_tests.py
grep -n "DEVELOPMENT_MODE" game/scripts/vscripts/osc/config/config.lua
grep -rn "shortcut: GetRarity" game/scripts/vscripts
```

Expected: `RESULT: OK`, `Lua tests: 198 passed, 0 failed` (171 + 11 от A + 1 от B + 14 от C + 1 интеграционный); `DEVELOPMENT_MODE = false`; второй grep пуст.

- [ ] **5. Документация** — отдельный коммит `docs: rarity, chaos sphere and help in project overview`: в `PROJECT_OVERVIEW.md` разделы «Редкость» (поле `rarity`, `ABILITY_RARITY_*`, `opts.rarity`, объявление), «Сфера хаоса» (выпадение, протокол `osc_sphere_offer`/`osc_sphere_pick`, `sphere_offer`), «Справка» (`osc_help.js`, ключи `osc_hud_help_*`), строки таблицы конфига для новых ключей. Версию 1.3.0 не поднимать до приёмки в игре.

- [ ] **6. Проверка в игре** (Workshop Tools с ботами, `DEVELOPMENT_MODE = true` локально, не коммитить): пункты отчётов A, B, C и «Проверить в игре» спека; консоль VScript и лог мода без ошибок; время загрузки до/после расширения пула.

- [ ] **7. Уборка:** `git worktree remove ../one_spell-rarity-a` (так же `-b`, `-c`), удалить ветки `stage-4-rarity-sphere-a/-b/-c`.
