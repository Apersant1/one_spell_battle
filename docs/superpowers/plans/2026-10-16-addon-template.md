# Шаблон-репозиторий для модов Dota 2 — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Собрать публичный репозиторий-шаблон `Apersant1/dota_addon_template` — голый скелет мода Dota 2 с архитектурой one_spell, из которого новый мод стартует `git clone` → `npm run setup` → `npm run launch`.

**Architecture:** Копия инструментов и ядра one_spell с заменой префикса `osc` на `mod` и вырезанием игровых систем. Сервер — Lua (`game/scripts/vscripts/mod/{config,core,systems}`), клиент — Panorama на TS/React (`src/panorama` → собирается в `content/panorama/scripts`), контракт между ними — `src/panorama/shared/mod_types.d.ts`, его сверяет `tools/tests/run_tests.py`. Один пример (счётчик кликов) проходит весь путь клиент → сервер → net table → HUD.

**Tech Stack:** Dota 2 VScript (Lua 5.1/LuaJIT), Panorama, TypeScript 5.9, React 17 + @demon673/react-panorama, Node ≥ 20, Python 3 + lupa (офлайн-тесты).

**Spec:** `docs/superpowers/specs/2026-10-16-addon-template-design.md` (в репозитории one_spell)

## Global Constraints

- Шаблон: `C:\Users\baras\OneDrive\Рабочий стол\dota_mods\dota_addon_template`, `git init -b master`, история с нуля.
- Префикс один навсегда: папка `vscripts/mod/`, Lua-глобальные `Mod_*`, таблица конфига `MOD_CONFIG`, класс режима `ModGameMode`, TS-namespace `Mod`, CSS-классы `Mod*`, net table `mod_state`, события и ключи локализации `mod_*`.
- Не переносятся: игровые системы, `heroes` остаётся (его требуют `game_events` и `client_commands`), `hero_state`, `gold`, `anchor`, `notifications`, `hud_assets.py`, карты, `docs/`, модели/частицы/картинки из `content/`.
- Зависимости npm — те же версии, что в one_spell (`package-lock.json` копируется).
- Комментарии в коде — по-русски, в стиле исходников one_spell.
- Конфиг читается только через `Mod_Config.Get("ПУТЬ")`.
- Каждый коммит заканчивается строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Ничего не пушить до Task 7; публикация — только после явного «да» пользователя.

Во всех шагах bash:

```bash
SRC="/c/Users/baras/OneDrive/Рабочий стол/dota_mods/one_spell"
DST="/c/Users/baras/OneDrive/Рабочий стол/dota_mods/dota_addon_template"
```

## Review Focus

1. Клон в папку с недопустимым именем (`My-Mod`) — `tools/dota.mjs` должен отказать понятным сообщением, а не создать кривую ссылку (уже есть в one_spell; проверяется руками в Task 6).
2. Остатки `osc`/`OSC` в перенесённых файлах — мод будет ссылаться на несуществующие модули; Task 2 и Task 6 проверяют `git grep -i osc` пустым.
3. Свежий клон без `node_modules` — `npm run setup` ставит зависимости и собирает, `run_tests.py` проходит (Task 6).
4. HUD загрузился позже, чем сервер записал значение (переподключение) — `Mod.Net.Watch` сразу отдаёт текущее значение, счётчик не показывает 0 (руками в Task 6).
5. `script_reload` — счётчик не сбрасывается и работает новый код обработчика (тест в Task 4); подделанный клиент в цикле не заспамит лог (тест в Task 2).

---

### Task 1: Каркас репозитория и инструменты

**Files:**
- Create: `$DST/package.json`, `$DST/tools/requirements.txt`, `$DST/game/scripts/npc/*.txt`, `$DST/game/scripts/custom_net_tables.txt`
- Copy: `.prettierrc.json`, `.vscode/{extensions,settings,tasks}.json`, `eslint.config.mjs`, `.gitignore`, `package-lock.json`, `tools/dota.mjs`, `tools/panorama-libs.mjs`, `tools/release.mjs`, `game/addoninfo.txt`
- Modify (после копирования): `eslint.config.mjs`, `.gitignore`, `tools/panorama-libs.mjs`, `tools/release.mjs`

**Interfaces:**
- Produces: `tools/release.mjs` экспортирует `NextVersion(current: number[], kind: string): number[] | null` (его проверяет `run_tests.py` в Task 2); `release.mjs` ищет версию в `game/scripts/vscripts/mod/config/config.lua` по `VERSION = "X.Y.Z"`.

- [ ] **Step 1: Создать папку, git и скопировать файлы как есть**

```bash
mkdir -p "$DST" && cd "$DST" && git init -b master
mkdir -p .vscode tools game/scripts/npc
cp "$SRC/.prettierrc.json" "$SRC/eslint.config.mjs" "$SRC/.gitignore" "$SRC/package-lock.json" .
cp "$SRC"/.vscode/{extensions,settings,tasks}.json .vscode/
cp "$SRC"/tools/{dota.mjs,panorama-libs.mjs,release.mjs} tools/
cp "$SRC/game/addoninfo.txt" game/
```

- [ ] **Step 2: Написать `package.json`**

```json
{
  "name": "dota-addon-template",
  "private": true,
  "scripts": {
    "setup": "node tools/dota.mjs setup",
    "build": "tsc --project src/panorama/tsconfig.json && node tools/panorama-libs.mjs",
    "dev": "node tools/panorama-libs.mjs && tsc --project src/panorama/tsconfig.json --watch",
    "lint": "eslint . && prettier --check \"src/panorama/**/*.{ts,tsx}\"",
    "format": "prettier --write \"src/panorama/**/*.{ts,tsx}\" && eslint --fix .",
    "compile": "npm run build && node tools/dota.mjs compile",
    "launch": "node tools/dota.mjs launch",
    "release": "node tools/release.mjs"
  },
  "devDependencies": {
    "@eslint/js": "^10.0.1",
    "@moddota/panorama-types": "^1.39.2",
    "@types/react": "^17.0.93",
    "eslint": "^10.12.0",
    "prettier": "^3.9.10",
    "typescript": "~5.9.3",
    "typescript-eslint": "^8.71.2"
  },
  "dependencies": {
    "@demon673/react-panorama": "^0.3.4",
    "react": "^17.0.2"
  },
  "engines": {
    "node": ">=20"
  }
}
```

- [ ] **Step 3: `tools/requirements.txt`**

```text
# Тесты (tools/tests/run_tests.py)
lupa
```

- [ ] **Step 4: KV-заготовки и net table**

`game/scripts/npc/npc_abilities_custom.txt`, `npc_items_custom.txt`, `npc_abilities_override.txt` — одинаково:

```text
"DOTAAbilities"
{
}
```

`game/scripts/npc/npc_units_custom.txt`:

```text
"DOTAUnits"
{
	"Version"	"1"
}
```

`game/scripts/npc/npc_heroes_custom.txt`:

```text
"DOTAHeroes"
{
}
```

`game/scripts/custom_net_tables.txt`:

```text
<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:generic:version{7412167c-06e9-4698-aff2-e63eb59037e7} -->
{
	custom_net_tables =
	[
		"mod_state"
	]
}
```

- [ ] **Step 5: Правки скопированных файлов**

`eslint.config.mjs`: в `ignores` убрать `"graphify-out/"`; комментарий `общим namespace OSC` → `общим namespace Mod`; строку `// OSC — общий namespace, его читают другие файлы и XML` → `// Mod — общий namespace, его читают другие файлы и XML`; `varsIgnorePattern: "^OSC$"` → `varsIgnorePattern: "^Mod$"`.

`.gitignore`: удалить строку `graphify-out/`.

`tools/panorama-libs.mjs`: в комментарии `osc_hud.xml` → `mod_hud.xml`.

`tools/release.mjs`:
- `import { dirname, join, resolve } from "node:path";` → `import { basename, dirname, join, resolve } from "node:path";`
- комментарий `OSC_CONFIG.VERSION` → `MOD_CONFIG.VERSION`
- `const CONFIG = join(REPO, "game", "scripts", "vscripts", "osc", "config", "config.lua");` → `"mod"` вместо `"osc"`
- `const notes = [\`One Spell Chaos ${version}\`, ...` → `const notes = [\`${basename(REPO)} ${version}\`, ...`

- [ ] **Step 6: Установить зависимости и проверить инструменты**

```bash
cd "$DST" && npm install
node tools/dota.mjs; echo "exit=$?"
node --input-type=module -e "import('./tools/release.mjs').then(m => console.log(JSON.stringify(m.NextVersion([0,1,0],'patch'))))"
git grep -n -i osc
```

Expected: `npm install` без ошибок; `dota.mjs` печатает «Использование: ...» и `exit=2` (Dota найдена, команда не задана); `[0,1,1]`; `git grep` ничего не выводит (файлы ещё не в индексе — выполнить после `git add -A`, см. Step 7).

- [ ] **Step 7: Commit**

```bash
cd "$DST" && git add -A && git grep -n -i osc; git commit -q -F - <<'EOF'
chore: project skeleton and tools

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

Expected: `git grep` пустой до коммита.

---

### Task 2: Ядро Lua и офлайн-тесты

**Files:**
- Create: `game/scripts/vscripts/addon_game_mode.lua`, `addon_init.lua`, `mod/config/config.lua`, `mod/core/{logger,game_mode,commands}.lua`, `game/resource/addon_{english,russian}.txt`, `src/panorama/tsconfig.json` (копия), `src/panorama/shared/mod_types.d.ts`
- Copy + rename: `mod/core/{util,runtime_config,heroes,game_events,client_commands}.lua`, `tools/tests/{harness.lua,run_tests.py}`
- Test: `tools/tests/test_{smoke,runtime_config,game_events,client_commands,commands}.lua`

**Interfaces:**
- Consumes: `tools/release.mjs` из Task 1 (проверка `NextVersion` в `run_tests.py`).
- Produces (для Task 3–4):
  - `Mod_Config.Get(path: string) -> any`, `Mod_Config.SetOverride(path, value)`, `Mod_Config.ClearOverride(path)`, `Mod_Config.Overrides() -> table`
  - `Mod_Logger.Log(message)`, `Mod_Logger.Error(message)` — префикс `[Mod]`
  - `Mod_GameEvents.Subscribe(eventName, id, handler)`, `Mod_GameEvents.Emit(eventName, ...)`, `Mod_GameEvents.Init()`; события `hero_spawned(unit, source)`, `game_state_changed { state, previous }`, `game_started()`
  - `Mod_ClientCommands.Check(sourceIndex, event, spec) -> ok, cmd, reason`, `Mod_ClientCommands.LogRefusal(channel, senderKey, message)`, `.Integer(opts)`, `.PlayerID()`, `.OneOf(list)`
  - `Mod_Heroes.IsHeroUnit(unit)`, `.GetPlayerHero(playerID)`, `.IsMainHero(unit)`, `.ForEachPlayerHero(cb)` и остальные функции one_spell
  - `ModGameMode:Init()` — пишет `mod_state/version { version }`, вызывает `SafeInit` модулей
  - `MOD_CONFIG.EXAMPLE.STEP = 1` (используется в Task 4)
  - `mod_types.d.ts`: `CustomNetTableDeclarations.mod_state.version`, пустой `CustomGameEventDeclarations`

- [ ] **Step 1: Перенести стенд тестов**

```bash
cd "$DST" && mkdir -p tools/tests src/panorama/shared
cp "$SRC/tools/tests/harness.lua" tools/tests/
cp "$SRC/src/panorama/tsconfig.json" src/panorama/
sed -e 's/OSC_CONFIG/MOD_CONFIG/g; s/osc_/mod_/g; s/"osc"/"mod"/g; s/osc\//mod\//g; s/OSC/Mod/g' \
  "$SRC/tools/tests/run_tests.py" > tools/tests/run_tests.py
```

Затем руками в `tools/tests/run_tests.py`:
- первая строка docstring `"""Офлайн-проверки One Spell Chaos.` → `"""Офлайн-проверки мода.`
- `LOC_PREFIXES = ( ... )` заменить на:

```python
# Ключи локализации, которые проверяются по коду (остальные mod_* — имена
# событий, net table и т. п.). Новый префикс — сюда.
LOC_PREFIXES = ("mod_hud_",)
```

- удалить функцию `dynamic_localization_keys` целиком и строку `used |= dynamic_localization_keys()` в `check_localization`;
- в `check_localization` комментарий `# "mod_notify_vote_" и т. п. — префикс ключа, собираемого в коде` → `# "mod_hud_x_" — префикс ключа, собираемого в коде`;
- в docstring `check_config_paths` пример `Mod_Config.Get("COURIERS." .. key)` → `Mod_Config.Get("EXAMPLE." .. key)`.

Проверка: `grep -n -i -E "osc|one spell|courier|vote|casino|chaos" tools/tests/run_tests.py` — пусто.

- [ ] **Step 2: Написать тесты ядра (до кода)**

`tools/tests/test_runtime_config.lua`:

```lua
-- Чтение конфига через Mod_Config.Get с рантайм-переопределениями

local function setup()
    require("mod/config/config")
    require("mod/core/logger")
    require("mod/core/runtime_config")
end

return {
    get_reads_base_and_nested_paths = function()
        setup()
        H.eq(Mod_Config.Get("VERSION"), MOD_CONFIG.VERSION, "top level")
        H.eq(Mod_Config.Get("EXAMPLE.STEP"), MOD_CONFIG.EXAMPLE.STEP, "nested path")
        H.eq(Mod_Config.Get("NO_SUCH_KEY"), nil, "unknown key")
        H.eq(Mod_Config.Get("VERSION.DEEPER"), nil, "path through a string")
    end,

    override_does_not_touch_config = function()
        setup()
        Mod_Config.SetOverride("EXAMPLE.STEP", 5)
        H.eq(Mod_Config.Get("EXAMPLE.STEP"), 5, "override read")
        H.eq(MOD_CONFIG.EXAMPLE.STEP, 1, "MOD_CONFIG untouched")
        Mod_Config.ClearOverride("EXAMPLE.STEP")
        H.eq(Mod_Config.Get("EXAMPLE.STEP"), 1, "override cleared")
    end,

    override_rejects_typos_and_wrong_types = function()
        setup()
        local ok = pcall(Mod_Config.SetOverride, "EXAMPLE.STPE", 5)
        H.eq(ok, false, "unknown path rejected")
        ok = pcall(Mod_Config.SetOverride, "EXAMPLE.STEP", "5")
        H.eq(ok, false, "string for a number rejected")
        H.eq(next(Mod_Config.Overrides()), nil, "nothing stored")
    end,

    overrides_survive_reload = function()
        setup()
        Mod_Config.SetOverride("EXAMPLE.STEP", 3)
        for _, name in ipairs({ "mod/config/config", "mod/core/runtime_config" }) do
            package.loaded[name] = nil
            require(name)
        end
        H.eq(Mod_Config.Get("EXAMPLE.STEP"), 3, "override kept after reload")
    end,
}
```

`tools/tests/test_game_events.lua`:

```lua
-- Шина событий: именованные подписки, изоляция ошибок, события движка

local function setup()
    require("mod/config/config")
    require("mod/core/logger")
    require("mod/core/game_events")
end

return {
    resubscribe_with_same_id_replaces_handler = function()
        setup()
        local calls = {}
        Mod_GameEvents.Subscribe("game_started", "test", function() table.insert(calls, "old") end)
        Mod_GameEvents.Subscribe("game_started", "test", function() table.insert(calls, "new") end)
        Mod_GameEvents.Emit("game_started")
        H.eq(#calls, 1, "one handler")
        H.eq(calls[1], "new", "handler replaced")
    end,

    unknown_event_is_an_error = function()
        setup()
        local ok = pcall(Mod_GameEvents.Emit, "no_such_event")
        H.eq(ok, false, "emit rejected")
        ok = pcall(Mod_GameEvents.Subscribe, "no_such_event", "test", function() end)
        H.eq(ok, false, "subscribe rejected")
    end,

    failing_handler_does_not_stop_others = function()
        setup()
        local reached = false
        Mod_GameEvents.Subscribe("game_started", "broken", function() error("boom") end)
        Mod_GameEvents.Subscribe("game_started", "ok", function() reached = true end)
        Mod_GameEvents.Emit("game_started")
        H.eq(reached, true, "second handler called")
        H.truthy(H.logged("handler 'broken' failed"), "error logged")
    end,

    game_started_fires_once_on_in_progress = function()
        setup()
        local count = 0
        Mod_GameEvents.Subscribe("game_started", "test", function() count = count + 1 end)
        Mod_GameEvents.Init()
        H.state = DOTA_GAMERULES_STATE_PRE_GAME
        H.FireGameEvent("game_rules_state_change", {})
        H.eq(count, 0, "not yet")
        H.state = DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
        H.FireGameEvent("game_rules_state_change", {})
        H.FireGameEvent("game_rules_state_change", {})
        H.eq(count, 1, "exactly once")
    end,

    hero_spawned_only_for_heroes = function()
        setup()
        local spawned = {}
        Mod_GameEvents.Subscribe("hero_spawned", "test", function(unit, source)
            table.insert(spawned, { unit = unit, source = source })
        end)
        Mod_GameEvents.Init()
        local hero = H.NewHero({})
        H.entities[5] = hero
        H.entities[6] = { IsNull = function() return false end }
        H.FireGameEvent("npc_spawned", { entindex = 6 })
        H.eq(#spawned, 0, "non-hero ignored")
        H.FireGameEvent("npc_spawned", { entindex = 5 })
        H.eq(#spawned, 1, "hero passed")
        H.eq(spawned[1].unit, hero, "unit")
        H.eq(spawned[1].source, "npc_spawned", "source")
    end,
}
```

`tools/tests/test_client_commands.lua`:

```lua
-- Проверка команд клиента: отправитель, герой, аргументы, лог отказов

local function setup()
    require("mod/config/config")
    require("mod/core/logger")
    require("mod/core/client_commands")
end

return {
    integer_rejects_non_integers_and_bounds = function()
        setup()
        local check = Mod_ClientCommands.Integer({ min = 0, max = 10 })
        H.eq((check("5")), true, "numeric string")
        H.eq((check(5.5)), false, "fraction")
        H.eq((check(0 / 0)), false, "NaN")
        H.eq((check(11)), false, "above max")
        H.eq((check(-1)), false, "below min")
        H.eq((check(nil)), false, "nil")
    end,

    check_fills_command_and_reports_reason = function()
        setup()
        local hero = H.NewHero({ playerID = 0 })
        H.AddPlayer(0, hero)
        H.AddPlayer(1, nil)
        local spec = {
            hero = true,
            args = { { name = "amount", check = Mod_ClientCommands.Integer({ min = 1 }) } },
        }

        local ok, cmd = Mod_ClientCommands.Check(1, { PlayerID = 0, amount = "3" }, spec)
        H.eq(ok, true, "valid")
        H.eq(cmd.hero, hero, "hero")
        H.eq(cmd.args.amount, 3, "normalized argument")

        local _, _, reason = Mod_ClientCommands.Check(1, { PlayerID = 9 }, spec)
        H.eq(reason, "invalid_player", "unknown player")

        _, cmd, reason = Mod_ClientCommands.Check(2, { PlayerID = 1 }, spec)
        H.eq(reason, "no_hero", "player without hero")
        H.eq(cmd.player_id, 1, "player kept for the reply")

        _, _, reason = Mod_ClientCommands.Check(1, { PlayerID = 0, amount = "0" }, spec)
        H.eq(reason, "invalid_amount", "bad argument")
    end,

    refusals_are_rate_limited = function()
        setup()
        Mod_ClientCommands.LogRefusal("mod_test", 0, "first")
        Mod_ClientCommands.LogRefusal("mod_test", 0, "second")
        H.time = 10
        Mod_ClientCommands.LogRefusal("mod_test", 0, "third")
        H.truthy(H.logged("refused: first"), "first logged")
        H.eq(H.logged("refused: second"), false, "second suppressed")
        H.truthy(H.logged("refused: third (+1 more refused)"), "suppressed count reported")
    end,
}
```

`tools/tests/test_commands.lua`:

```lua
-- Чат-команды разработчика

local function setup(developmentMode)
    require("mod/config/config")
    require("mod/core/logger")
    require("mod/core/commands")
    Mod_Config.SetOverride("DEVELOPMENT_MODE", developmentMode)
    Mod_Commands.Init()
    local function Fort(team)
        return {
            killed = false,
            GetTeamNumber = function() return team end,
            ForceKill = function(self) self.killed = true end,
        }
    end
    local enemy, own = Fort(DOTA_TEAM_BADGUYS), Fort(DOTA_TEAM_GOODGUYS)
    H.byClass.npc_dota_fort = { enemy, own }
    H.AddPlayer(0, nil, { team = DOTA_TEAM_GOODGUYS })
    return enemy, own
end

return {
    win_kills_only_enemy_fort = function()
        local enemy, own = setup(true)
        H.FireGameEvent("player_chat", { text = " -WIN ", playerid = 0 })
        H.eq(enemy.killed, true, "enemy fort")
        H.eq(own.killed, false, "own fort")
    end,

    commands_ignored_outside_development_mode = function()
        local enemy = setup(false)
        H.FireGameEvent("player_chat", { text = "-win", playerid = 0 })
        H.eq(enemy.killed, false, "fort alive")
        H.truthy(H.logged("Ignored development chat command: -win"), "logged")
    end,

    unknown_player_is_refused = function()
        local enemy = setup(true)
        H.FireGameEvent("player_chat", { text = "-win", playerid = 7 })
        H.eq(enemy.killed, false, "fort alive")
        H.truthy(H.logged("-win ignored: invalid player"), "logged")
    end,

    ordinary_chat_is_ignored = function()
        local enemy = setup(true)
        H.FireGameEvent("player_chat", { text = "gg", playerid = 0 })
        H.eq(enemy.killed, false, "fort alive")
    end,
}
```

`tools/tests/test_smoke.lua`:

```lua
-- Точка входа целиком: все модули грузятся, Activate проходит без ошибок
return {
    activate_loads_everything = function()
        require("addon_game_mode")
        Activate()
        H.eq(H.netTables.version.version, MOD_CONFIG.VERSION, "version published")
        H.truthy(H.logged("Mod loaded"), "game mode initialized")
        H.eq(H.logged("ERROR"), false, "no init errors")
    end,
}
```

- [ ] **Step 3: Запустить тесты — должны упасть**

```bash
cd "$DST" && pip install -r tools/requirements.txt && python tools/tests/run_tests.py
```

Expected: FAIL — `module 'mod/config/config' not found` в тестах, `declared_contract` падает на отсутствующем `mod_types.d.ts` (это тоже провал, а не зелёный прогон).

- [ ] **Step 4: Конфиг, логгер, точка входа**

`game/scripts/vscripts/mod/config/config.lua`:

```lua
-- Все настройки мода. Читаются только через Mod_Config.Get("ПУТЬ")
-- (mod/core/runtime_config.lua); напрямую MOD_CONFIG никто не трогает —
-- это проверяет tools/tests/run_tests.py.
MOD_CONFIG = {
    -- Единственное место версии: её меняет npm run release, HUD её показывает
    VERSION = "0.1.0",
    -- Чат-команды разработчика (mod/core/commands.lua); в публичной игре — false
    DEVELOPMENT_MODE = false,
    -- Отказ на команду клиента пишется в лог не чаще раза в столько секунд
    CLIENT_REFUSAL_LOG_INTERVAL = 5,
    -- Пример (mod/systems/example.lua): на сколько растёт счётчик за клик
    EXAMPLE = {
        STEP = 1,
    },
}
```

`game/scripts/vscripts/mod/core/logger.lua`:

```lua
Mod_Logger = Mod_Logger or {}

function Mod_Logger.Log(message)
    print("[Mod] " .. tostring(message))
end

function Mod_Logger.Error(message)
    print("[Mod] ERROR: " .. tostring(message))
end
```

`game/scripts/vscripts/addon_init.lua`:

```lua
-- Грузится движком и на сервере, и на клиенте: здесь LinkLuaModifier для
-- модификаторов из mod/modifiers/, иначе клиент о них не узнает.
require("mod/config/config")

-- LinkLuaModifier("modifier_mod_example", "mod/modifiers/modifier_mod_example", LUA_MODIFIER_MOTION_NONE)
```

`game/scripts/vscripts/addon_game_mode.lua`:

```lua
-- Точка входа сервера. Порядок require — порядок загрузки: конфиг, ядро,
-- системы, последним game_mode (он вызывает Init систем).
require("mod/config/config")
require("mod/core/logger")
require("mod/core/util")
require("mod/core/runtime_config")
require("mod/core/heroes")
require("mod/core/game_events")
require("mod/core/client_commands")
require("mod/core/commands")
require("mod/core/game_mode")

function Precache(context)
    -- Ресурсы, которых может не быть в матче (частицы, звуки, чужие герои):
    -- PrecacheResource("particle", "particles/...", context)
    -- PrecacheUnitByNameSync("npc_dota_hero_axe", context)
end

function Activate()
    GameRules.Mod = ModGameMode()
    GameRules.Mod:Init()
end
```

- [ ] **Step 5: Перенести модули ядра с заменой префикса**

```bash
cd "$DST/game/scripts/vscripts" && mkdir -p mod/core
for f in util runtime_config heroes game_events client_commands; do
  sed -e 's/OSC_CONFIG/MOD_CONFIG/g; s/OSC_/Mod_/g; s/\[OSC\]/[Mod]/g; s/osc\//mod\//g; s/osc_/mod_/g' \
    "$SRC/game/scripts/vscripts/osc/core/$f.lua" > "mod/core/$f.lua"
done
```

Затем руками убрать упоминания систем one_spell:

`mod/core/runtime_config.lua` — заменить комментарий в начале файла (до `require`) на:

```lua
-- Единая точка чтения конфига с рантайм-переопределениями.
--
--   Mod_Config.Get("VERSION")
--   Mod_Config.Get("EXAMPLE.STEP")
--
-- Значение берётся из переопределения для этого пути, иначе из MOD_CONFIG
-- (mod/config/config.lua). Исходный MOD_CONFIG никогда не меняется.
-- Переопределения (например, итоги голосования в лобби) задаются через
-- SetOverride и хранятся в таблице модуля — переживают script_reload, а
-- config.lua при перезагрузке, наоборот, читается заново.
--
-- Правила для модулей:
--   * читать значения в момент использования, а не копировать их в
--     локальные переменные при загрузке файла;
--   * читать листья по полному пути: переопределение действует только на
--     точный путь, и таблица, полученная через Get("EXAMPLE"), его не
--     увидит. Таблицы целиком читаются только для статических списков.
```

`mod/core/heroes.lua` — заменить комментарий в начале файла (до `Mod_Heroes = ...`) на:

```lua
-- Единое определение «какой герой нам нужен». Все системы проверяют героев
-- только через эти функции, чтобы правила не расходились.
--
-- Виды героев в матче:
--   основной герой — выбранный герой игрока: сам юнит, который возвращает
--     PlayerResource:GetSelectedHeroEntity(его игрок). Солдаты Monkey King
--     (Wukong's Command) тоже IsRealHero, но выбранным героем не являются.
--   копия — иллюзия, Tempest Double или клон Meepo.
--   боевое тело — всё, у чего своё здоровье, мана и перезарядки: основной
--     герой, клоны Meepo и Tempest Double. Иллюзии сюда не входят.
-- Солдаты Monkey King — ни основной герой, ни копия, ни боевое тело.
```

В нём же комментарий над `GetCopyOwner` оставить как есть (он про Wall of Replica, это общее знание Dota).

`mod/core/game_events.lua` — заменить комментарий в начале файла (до `require`) на:

```lua
-- Шина событий матча. Через неё системы узнают друг о друге: одна система
-- публикует (Emit), другие подписываются (Subscribe), напрямую никто никого
-- не вызывает. События движка и события мода идут через один модуль.
--
-- Только этот модуль слушает npc_spawned, dota_on_hero_finish_spawn и
-- game_rules_state_change; системы подписываются здесь, а не у движка.
--
-- События:
--   hero_spawned(unit, source) — герой (основной или копия) появился или
--     возродился. source — имя события движка. Первое появление приходит
--     дважды (npc_spawned и dota_on_hero_finish_spawn) — второй шанс, если
--     на npc_spawned юнит ещё не распознан. Обработчики обязаны быть
--     идемпотентными. Кто нужен — фильтруют через Mod_Heroes.
--   game_state_changed { state, previous } — сменилась стадия игры
--     (DOTA_GAMERULES_STATE_*); приходит до game_started.
--   game_started() — игра перешла в GAME_IN_PROGRESS; приходит один раз.
--
-- Новое событие мода: имя в KNOWN_EVENTS и строка описания выше (один
-- аргумент — таблица, её можно расширять полями).
--
-- Подписка именованная: повторный Subscribe с тем же id заменяет обработчик,
-- поэтому повторная инициализация и script_reload не дублируют подписки.
-- Ошибка одного обработчика пишется в лог и не мешает остальным.
```

и `KNOWN_EVENTS` на:

```lua
local KNOWN_EVENTS = {
    hero_spawned = true,
    game_state_changed = true,
    game_started = true,
}
```

`mod/core/client_commands.lua` — в примере в шапке строку
`--           { name = "machine_entindex", check = Mod_ClientCommands.Integer({ min = 0 }) },`
заменить на
`--           { name = "amount", check = Mod_ClientCommands.Integer({ min = 1 }) },`.

Проверка: `grep -rn -i "osc\|casino\|chaos\|rotation\|anchor\|courier\|hero_lifecycle" mod/` — пусто.

- [ ] **Step 6: Чат-команды и режим игры**

`game/scripts/vscripts/mod/core/commands.lua`:

```lua
-- Чат-команды разработчика. Работают только при DEVELOPMENT_MODE = true.
--   -win — убить вражеский трон (быстрая проверка конца игры)
-- Новая команда — ещё одна запись в COMMANDS: полный текст сообщения
-- (без учёта регистра и пробелов по краям) -> function(playerID).
require("mod/core/runtime_config")

Mod_Commands = Mod_Commands or {}

local COMMANDS = {
    ["-win"] = function(playerID)
        local team = PlayerResource:GetTeam(playerID)
        for _, fort in ipairs(Entities:FindAllByClassname("npc_dota_fort")) do
            if fort:GetTeamNumber() ~= team then fort:ForceKill(false) end
        end
    end,
}

function Mod_Commands.OnPlayerChat(event)
    local text = string.lower(string.match(event.text or "", "^%s*(.-)%s*$"))
    local command = COMMANDS[text]
    if not command then return end

    if not Mod_Config.Get("DEVELOPMENT_MODE") then
        Mod_Logger.Log("Ignored development chat command: " .. text)
        return
    end

    local playerID = event.playerid
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        Mod_Logger.Error(text .. " ignored: invalid player")
        return
    end

    command(playerID)
    Mod_Logger.Log(text .. " executed by player " .. tostring(playerID))
end

-- Обработчик через таблицу модуля: после script_reload работает новый код
function Mod_Commands.Init()
    if Mod_Commands.listening then return end
    Mod_Commands.listening = true
    ListenToGameEvent("player_chat", function(event)
        Mod_Commands.OnPlayerChat(event)
    end, nil)
end
```

`game/scripts/vscripts/mod/core/game_mode.lua`:

```lua
require("mod/core/runtime_config")

if ModGameMode == nil then
    ModGameMode = class({})
end

-- Init модуля в pcall: упавшая система пишется в лог и не ломает остальные
local function SafeInit(name, module)
    if module == nil then
        Mod_Logger.Error(name .. " init skipped: module not loaded (check require)")
        return
    end
    local ok, err = pcall(function() module:Init() end)
    if not ok then Mod_Logger.Error(name .. " init failed: " .. tostring(err)) end
end

function ModGameMode:Init()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(15)
    GameRules:LockCustomGameSetupTeamAssignment(false)

    CustomNetTables:SetTableValue("mod_state", "version", {
        version = Mod_Config.Get("VERSION"),
    })

    -- Единая точка событий движка — первой: системы ниже подписываются на неё в Init
    SafeInit("GameEvents", Mod_GameEvents)
    SafeInit("Commands", Mod_Commands)

    Mod_Logger.Log("Mod loaded")
end
```

- [ ] **Step 7: Контракт и локализация (минимум для проверок)**

`src/panorama/shared/mod_types.d.ts`:

```ts
// Контракт с сервером (game/scripts/vscripts/mod): что лежит в net table
// mod_state и что ходит кастомными событиями. Поля описаны так, как их шлёт
// Lua; panorama-types сам превращает массивы в { [i]: ... }, а boolean — в
// 0 | 1 (NetworkedData). tools/tests/run_tests.py сверяет имена с Lua.

interface CustomNetTableDeclarations {
  mod_state: {
    version: { version: string };
  };
}

interface CustomGameEventDeclarations {
  // сервер -> клиент
  // клиент -> сервер
}
```

`game/resource/addon_english.txt`:

```text
"lang"
{
	"Language"		"English"
	"Tokens"
	{
		"addon_game_name"		"Dota Addon Template"
	}
}
```

`game/resource/addon_russian.txt`:

```text
"lang"
{
	"Language"		"Russian"
	"Tokens"
	{
		"addon_game_name"		"Шаблон мода Dota"
	}
}
```

- [ ] **Step 8: Запустить тесты — зелёные**

```bash
cd "$DST" && python tools/tests/run_tests.py
```

Expected: все разделы `OK`, `Lua tests: 17 passed, 0 failed`, `RESULT: OK`. `npm run lint` в этой задаче не запускается: пустой `CustomGameEventDeclarations` нарушает `no-empty-object-type` до Task 4.

- [ ] **Step 9: Commit**

```bash
cd "$DST" && git add -A && git grep -n -i osc; git commit -q -F - <<'EOF'
feat: Lua core, config and offline tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Оболочка Panorama (HUD с версией)

**Files:**
- Create: `src/panorama/shared/mod_core.ts`, `src/panorama/shared/mod_components.tsx`, `src/panorama/hud/mod_version.ts`, `src/panorama/hud/mod_hud.ts`, `content/panorama/layout/custom_game/custom_ui_manifest.xml`, `content/panorama/layout/custom_game/mod_hud.xml`, `content/panorama/styles/custom_game/mod_hud.css`
- Copy + rename: `content/panorama/styles/custom_game/mod_theme.css`

**Interfaces:**
- Consumes: `mod_state/version` из Task 2.
- Produces (для Task 4): `Mod.Net.Watch(key, fn)`, `Mod.Util.{FormatTime, PlaySound, IsPostGame, Loop, LuaArray, LocalizeOr, Classes, Unschedule}`, `Mod.Localized(token, vars)`, `Mod.TextTooltip`, `Mod.AbilityTooltip`, `Mod.usePolled`, `Mod.useRerender`; CSS-классы темы `ModSurface`, `ModTextSmall`, `ModTextBody`, `ModTextTitle`, `ModButton`, `ModMuted`, ...; корень `.ModRoot` в `mod_hud.xml`, точка входа `mod_hud.ts`.

- [ ] **Step 1: Ядро клиента `src/panorama/shared/mod_core.ts`**

```ts
namespace Mod {
  export const Util = {
    FormatTime: function (seconds: number) {
      seconds = Math.max(0, Math.ceil(seconds));
      var m = Math.floor(seconds / 60);
      var s = seconds % 60;
      return m + ":" + (s < 10 ? "0" : "") + s;
    },

    // Пустая строка = без звука. Имена подберите в Asset Browser.
    PlaySound: function (name: string) {
      if (name) Game.EmitSound(name);
    },

    IsPostGame: function () {
      return Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_POST_GAME;
    },

    // Вызывает fn сразу и затем каждые interval секунд, пока fn не вернёт false.
    Loop: function (interval: number, fn: () => boolean | void) {
      (function tick() {
        if (fn() === false) return;
        $.Schedule(interval, tick);
      })();
    },

    // Lua-массив приходит объектом { "1": ..., "2": ... } -> массив по порядку ключей
    LuaArray: function <T>(table: { [key: number]: T } | null | undefined): T[] {
      if (!table) return [];
      return Object.keys(table)
        .sort(function (a, b) {
          return Number(a) - Number(b);
        })
        .map(function (key) {
          return table[Number(key)];
        });
    },

    // Текст ключа локализации (token с "#"); если ключа нет — fallback.
    // panel — откуда брать dialog variables ({d:...}, {s:...})
    LocalizeOr: function (token: string, fallback: string, panel?: PanelBase) {
      var text = panel ? $.Localize(token, panel) : $.Localize(token);
      return text && text !== token ? text : fallback;
    },

    // Строка CSS-классов из частей; ложные части пропускаются:
    // Classes("Card", picked && "Picked") -> "Card" | "Card Picked"
    Classes: function (...parts: (string | false | null | undefined)[]) {
      return parts.filter(Boolean).join(" ");
    },

    // Отменяет отложенный вызов, если он есть; возвращает null для сброса
    // переменной: handle = Mod.Util.Unschedule(handle)
    Unschedule: function (handle: ScheduleID | null): null {
      if (handle !== null) $.CancelScheduled(handle);
      return null;
    },
  };

  type ModState = CustomNetTableDeclarations["mod_state"];

  export const Net = {
    // fn(значение) сразу (переподключение, поздняя загрузка HUD) и при каждом
    // изменении ключа mod_state. key-функция — для ключей, зависящих от игрока
    // или команды: они читаются заново на каждое изменение.
    Watch: function <K extends keyof ModState>(
      key: K | (() => K),
      fn: (value: NetworkedData<ModState[K]> | null) => void,
    ) {
      function current() {
        return typeof key === "function" ? key() : key;
      }
      CustomNetTables.SubscribeNetTableListener("mod_state", function (tableName, changed, value) {
        if (changed === current()) fn(value as NetworkedData<ModState[K]>);
      });
      fn(CustomNetTables.GetTableValue("mod_state", current()));
    },
  };
}
```

- [ ] **Step 2: React-хелперы `src/panorama/shared/mod_components.tsx`**

```tsx
namespace Mod {
  // Общие React-хелперы и компоненты. Файл подключается после библиотек React и
  // до модулей, которые их используют.

  // Текст Label из resource/addon_<язык>.txt: значение для text={...}.
  // vars подставляются в {d:...} (числа) и {s:...} (строки) как dialog variables
  // самой метки — $.Localize без панели их вырезает
  export function Localized(token: string, vars?: Record<string, unknown>) {
    return function (panel: LabelPanel) {
      for (var key in vars || {}) {
        var value = vars![key];
        if (typeof value === "number") {
          panel.SetDialogVariableInt(key, value);
        } else {
          panel.SetDialogVariable(key, String(value));
        }
      }
      return $.Localize("#" + token, panel);
    };
  }

  // Подсказка Dota с текстом при наведении: {...Mod.TextTooltip(() => текст)}.
  // Текст читается в момент наведения; пустой — без подсказки
  export function TextTooltip(getText: () => string) {
    return {
      onmouseover: function (panel: Panel) {
        var text = getText();
        if (text) $.DispatchEvent("DOTAShowTextTooltip", panel, text);
      },
      onmouseout: function (panel: Panel) {
        $.DispatchEvent("DOTAHideTextTooltip", panel);
      },
    };
  }

  // Подсказка способности или предмета Dota при наведении: {...Mod.AbilityTooltip(имя)}
  export function AbilityTooltip(name: string) {
    return {
      onmouseover: function (panel: Panel) {
        $.DispatchEvent("DOTAShowAbilityTooltip", panel, name);
      },
      onmouseout: function (panel: Panel) {
        $.DispatchEvent("DOTAHideAbilityTooltip", panel);
      },
    };
  }

  // Значение read(), перечитываемое раз в interval секунд, пока active.
  // done(значение) === true останавливает опрос насовсем
  export function usePolled<T>(
    read: () => T,
    interval: number,
    active?: boolean,
    done?: (value: T) => boolean,
  ) {
    var [value, setValue] = React.useState(read);
    React.useEffect(
      function () {
        if (active === false) return;
        var stopped = false;
        Mod.Util.Loop(interval, function () {
          if (stopped) return false;
          var next = read();
          setValue(next);
          if (done && done(next)) return false;
        });
        return function () {
          stopped = true;
        };
      },
      [active],
    );
    return value;
  }

  // Для окон, чьё состояние — переменные модуля: функция перерисовки компонента
  export function useRerender() {
    var [, bump] = React.useReducer(function (n: number) {
      return n + 1;
    }, 0);
    return bump as () => void;
  }
}
```

- [ ] **Step 3: Модуль версии и точка входа HUD**

`src/panorama/hud/mod_version.ts`:

```ts
namespace Mod {
  export const Version = (function () {
    function Init() {
      Mod.Net.Watch("version", function (value) {
        if (value) ($("#VersionLabel") as LabelPanel).text = "v" + value.version;
      });
    }

    return { Init: Init };
  })();
}
```

`src/panorama/hud/mod_hud.ts`:

```ts
// Точка входа HUD: подключается в mod_hud.xml последней, когда все модули
// уже объявлены, и вызывает их Init()
(function () {
  Mod.Version.Init();
})();
```

- [ ] **Step 4: Разметка и стили**

`content/panorama/layout/custom_game/custom_ui_manifest.xml`:

```xml
<root>
    <Panel>
        <CustomUIElement type="Hud" layoutfile="file://{resources}/layout/custom_game/mod_hud.xml" />
    </Panel>
</root>
```

`content/panorama/layout/custom_game/mod_hud.xml`:

```xml
<root>
    <styles>
        <include src="s2r://panorama/styles/dotastyles.vcss_c" />
        <include src="file://{resources}/styles/custom_game/mod_theme.css" />
        <include src="file://{resources}/styles/custom_game/mod_hud.css" />
    </styles>
    <scripts>
        <!-- Порядок: ядро, React и общие компоненты, модули (только объявляют себя),
             последней — точка входа mod_hud.js, она вызывает их Init() -->
        <include src="file://{resources}/scripts/custom_game/shared/mod_core.js" />
        <include src="file://{resources}/scripts/custom_game/libraries/react.js" />
        <include src="file://{resources}/scripts/custom_game/libraries/react-panorama.js" />
        <include src="file://{resources}/scripts/custom_game/shared/mod_components.js" />
        <include src="file://{resources}/scripts/custom_game/hud/mod_version.js" />
        <include src="file://{resources}/scripts/custom_game/hud/mod_hud.js" />
    </scripts>

    <Panel class="ModRoot" hittest="false">
        <Label id="VersionLabel" class="ModTextSmall ModMuted" hittest="false" />
    </Panel>
</root>
```

```bash
cd "$DST" && mkdir -p content/panorama/styles/custom_game
sed 's/OSC/Mod/g' "$SRC/content/panorama/styles/custom_game/osc_theme.css" > content/panorama/styles/custom_game/mod_theme.css
```

В `mod_theme.css` удалить блоки `.ModChaos { ... }` и `.ModChaosText { ... }` (тема хаоса one_spell). Проверка: `grep -n -i chaos content/panorama/styles/custom_game/mod_theme.css` — пусто.

`content/panorama/styles/custom_game/mod_hud.css`:

```css
.ModRoot {
  width: 100%;
  height: 100%;
}

#VersionLabel {
  horizontal-align: right;
  vertical-align: bottom;
  margin: 0px 0px 104px 0px;
  opacity: 0.5;
}
```

- [ ] **Step 5: Сборка и проверки**

```bash
cd "$DST" && npm run build && npx prettier --check "src/panorama/**/*.{ts,tsx}" && python tools/tests/run_tests.py
ls content/panorama/scripts/custom_game/shared content/panorama/scripts/custom_game/hud content/panorama/scripts/custom_game/libraries
```

Expected: `tsc` без ошибок; prettier — `All matched files use Prettier code style!`; `RESULT: OK` (раздел `Layout includes: OK`); собраны `mod_core.js`, `mod_components.js`, `mod_version.js`, `mod_hud.js`, `react.js`, `react-panorama.js`. Если prettier ругается — `npx prettier --write "src/panorama/**/*.{ts,tsx}"` и повторить.

- [ ] **Step 6: Commit**

```bash
cd "$DST" && git add -A && git grep -n -i osc; git commit -q -F - <<'EOF'
feat: Panorama HUD shell with version label

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Пример клиент–сервер (счётчик кликов)

**Files:**
- Create: `game/scripts/vscripts/mod/systems/example.lua`, `src/panorama/hud/mod_example.tsx`
- Modify: `addon_game_mode.lua` (require), `mod/core/game_mode.lua` (SafeInit), `src/panorama/shared/mod_types.d.ts`, `src/panorama/hud/mod_hud.ts`, `content/panorama/layout/custom_game/mod_hud.xml`, `content/panorama/styles/custom_game/mod_hud.css`, `game/resource/addon_{english,russian}.txt`, `tools/tests/test_smoke.lua`
- Test: `tools/tests/test_example.lua`

**Interfaces:**
- Consumes: `Mod_ClientCommands.Check`, `Mod_ClientCommands.LogRefusal`, `Mod_Config.Get("EXAMPLE.STEP")` (Task 2); `Mod.Net.Watch`, `Mod.Localized`, классы `ModSurface`, `ModTextBody`, `ModButton` (Task 3).
- Produces: `Mod_Example = { clicks }`, `Mod_Example.Init()`, `Mod_Example.Publish()`, `Mod_Example.OnClick(sourceIndex, event)`; net table `mod_state/example { clicks: number }`; событие клиент → сервер `mod_example_click {}`; `Mod.ExampleHud.Init()`.

- [ ] **Step 1: Написать тест примера**

`tools/tests/test_example.lua`:

```lua
-- Пример клиент–сервер: клик -> проверка отправителя -> счётчик -> net table

local function setup()
    require("mod/config/config")
    require("mod/core/logger")
    require("mod/systems/example")
    H.AddPlayer(0, nil)
    Mod_Example.Init()
end

return {
    init_publishes_zero = function()
        setup()
        H.eq(H.netTables.example.clicks, 0, "initial value")
    end,

    click_adds_step_and_publishes = function()
        setup()
        H.listeners.mod_example_click(1, { PlayerID = 0 })
        H.listeners.mod_example_click(1, { PlayerID = 0 })
        H.eq(H.netTables.example.clicks, 2, "two clicks")
    end,

    step_comes_from_config_on_use = function()
        setup()
        Mod_Config.SetOverride("EXAMPLE.STEP", 5)
        H.listeners.mod_example_click(1, { PlayerID = 0 })
        H.eq(H.netTables.example.clicks, 5, "overridden step")
    end,

    click_from_unknown_player_is_refused = function()
        setup()
        H.listeners.mod_example_click(9, { PlayerID = 9 })
        H.eq(H.netTables.example.clicks, 0, "unchanged")
        H.truthy(H.logged("mod_example_click of player 9 refused: invalid_player"), "refusal logged")
    end,

    clicks_survive_script_reload = function()
        setup()
        H.listeners.mod_example_click(1, { PlayerID = 0 })
        package.loaded["mod/systems/example"] = nil
        require("mod/systems/example")
        H.listeners.mod_example_click(1, { PlayerID = 0 })
        H.eq(H.netTables.example.clicks, 2, "count kept, new code used")
    end,
}
```

В `tools/tests/test_smoke.lua` после строки `H.truthy(H.logged("Mod loaded"), ...)` добавить:

```lua
        H.eq(H.netTables.example.clicks, 0, "example published")
        H.truthy(H.listeners.mod_example_click, "example listens for clicks")
```

- [ ] **Step 2: Тесты падают**

Run: `cd "$DST" && python tools/tests/run_tests.py`
Expected: FAIL — `module 'mod/systems/example' not found`, `test_smoke` — `example published`.

- [ ] **Step 3: Система-пример**

`game/scripts/vscripts/mod/systems/example.lua`:

```lua
-- Пример системы: счётчик кликов, общий для всех игроков. Весь путь
-- клиент–сервер:
--   HUD (hud/mod_example.tsx) шлёт mod_example_click (mod_types.d.ts);
--   сервер проверяет отправителя (Mod_ClientCommands.Check), прибавляет
--   EXAMPLE.STEP (Mod_Config.Get) и пишет mod_state/example { clicks };
--   HUD показывает значение. Считает только сервер, клиент лишь просит.
-- Новая система: свой файл в mod/systems/, require в addon_game_mode.lua,
-- SafeInit в mod/core/game_mode.lua.

require("mod/core/runtime_config")
require("mod/core/client_commands")

-- Состояние в таблице модуля: script_reload его не сбрасывает
Mod_Example = Mod_Example or { clicks = 0 }

function Mod_Example.Publish()
    CustomNetTables:SetTableValue("mod_state", "example", { clicks = Mod_Example.clicks })
end

function Mod_Example.OnClick(sourceIndex, event)
    local ok, cmd, reason = Mod_ClientCommands.Check(sourceIndex, event)
    if not ok then
        Mod_ClientCommands.LogRefusal("mod_example_click", cmd.player_id or sourceIndex, reason)
        return
    end
    Mod_Example.clicks = Mod_Example.clicks + Mod_Config.Get("EXAMPLE.STEP")
    Mod_Example.Publish()
end

function Mod_Example.Init()
    Mod_Example.Publish()
    -- Через таблицу модуля: после script_reload работает новый OnClick
    CustomGameEventManager:RegisterListener("mod_example_click", function(sourceIndex, event)
        Mod_Example.OnClick(sourceIndex, event)
    end)
end
```

`addon_game_mode.lua`: перед `require("mod/core/game_mode")` добавить `require("mod/systems/example")`.

`mod/core/game_mode.lua`: после `SafeInit("Commands", Mod_Commands)` добавить `SafeInit("Example", Mod_Example)`.

- [ ] **Step 4: Контракт**

`src/panorama/shared/mod_types.d.ts` — заменить объявления после шапки на:

```ts
// mod/systems/example.lua
interface ModExampleState {
  clicks: number;
}

interface CustomNetTableDeclarations {
  mod_state: {
    version: { version: string };
    example: ModExampleState;
  };
}

interface CustomGameEventDeclarations {
  // клиент -> сервер
  mod_example_click: Record<string, never>;
}
```

- [ ] **Step 5: Экран-пример `src/panorama/hud/mod_example.tsx`**

```tsx
namespace Mod {
  // Пример экрана на React: значение из mod_state/example и кнопка, которая
  // шлёт mod_example_click. Считает сервер (mod/systems/example.lua),
  // клиент только показывает.
  export const ExampleHud = (function () {
    function ExamplePanel() {
      var [clicks, setClicks] = React.useState(0);
      React.useEffect(function () {
        Mod.Net.Watch("example", function (value) {
          setClicks(value ? Number(value.clicks) : 0);
        });
      }, []);

      return (
        <Panel className="ExamplePanel ModSurface">
          <Label
            className="ModTextBody"
            text={Mod.Localized("mod_hud_example_clicks", { clicks: clicks })}
          />
          <Button
            className="ModButton"
            onactivate={function () {
              GameEvents.SendCustomGameEventToServer("mod_example_click", {});
            }}
          >
            <Label text={$.Localize("#mod_hud_example_button")} />
          </Button>
        </Panel>
      );
    }

    function Init() {
      ReactPanorama.render(<ExamplePanel />, $("#ExampleRoot"));
    }

    return { Init: Init };
  })();
}
```

`src/panorama/hud/mod_hud.ts`: после `Mod.Version.Init();` добавить `Mod.ExampleHud.Init();`.

`content/panorama/layout/custom_game/mod_hud.xml`:
- перед `<include ... hud/mod_hud.js" />` добавить `<include src="file://{resources}/scripts/custom_game/hud/mod_example.js" />`;
- после `<Label id="VersionLabel" ... />` добавить:

```xml
        <!-- Пример (mod_example.tsx, React) -->
        <Panel id="ExampleRoot" hittest="false" />
```

`content/panorama/styles/custom_game/mod_hud.css` — дописать:

```css
#ExampleRoot {
  horizontal-align: center;
  vertical-align: top;
  margin-top: 120px;
}

.ExamplePanel {
  flow-children: down;
  padding: 12px;
}

.ExamplePanel .ModButton {
  margin-top: 8px;
}
```

Локализация — в `Tokens` после `addon_game_name`:

`addon_english.txt`:

```text
		"mod_hud_example_clicks"		"Clicks: {d:clicks}"
		"mod_hud_example_button"		"Click"
```

`addon_russian.txt`:

```text
		"mod_hud_example_clicks"		"Нажатий: {d:clicks}"
		"mod_hud_example_button"		"Нажать"
```

- [ ] **Step 6: Всё зелёное**

```bash
cd "$DST" && npm run build && npm run lint && python tools/tests/run_tests.py
```

Expected: сборка без ошибок; `npm run lint` чистый (ESLint и Prettier); `RESULT: OK`, `Lua tests: 22 passed, 0 failed`. Если Prettier ругается только на форматирование — `npm run format` и повторить.

- [ ] **Step 7: Commit**

```bash
cd "$DST" && git add -A && git grep -n -i osc; git commit -q -F - <<'EOF'
feat: client-server example with a click counter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Документация

**Files:**
- Create: `README.md`, `tools/tests/README.md`

- [ ] **Step 1: `README.md`**

````markdown
# Шаблон мода Dota 2

Пустой мод с готовой архитектурой: сервер на Lua, интерфейс на TypeScript +
React (Panorama), офлайн-тесты, сборка и запуск одной командой.

## Новый мод

```text
git clone https://github.com/Apersant1/dota_addon_template my_mod
cd my_mod
npm run setup
npm run launch
```

Имя папки — имя аддона в Dota: только `a-z`, `0-9` и `_`. На GitHub вместо
`git clone` — кнопка **Use this template**, затем клон нового репозитория
в папку с нужным именем.

После старта: название в `game/resource/addon_*.txt` (`addon_game_name`),
`git remote set-url origin <ваш репозиторий>`, и пример
(`mod/systems/example.lua`, `hud/mod_example.tsx`) можно переименовать в
первую свою систему или удалить.

## Что нужно

- Windows, Steam и Dota 2 с DLC **Dota 2 Workshop Tools** (Steam → Dota 2 →
  Свойства → DLC).
- [Node.js](https://nodejs.org/) 20 или новее.
- Python 3 — для тестов.

`npm run setup` ставит зависимости, находит Dota через Steam и подключает
аддон ссылками (junction, без прав администратора):
`dota 2 beta/game/dota_addons/<папка>` → `game/`,
`dota 2 beta/content/dota_addons/<папка>` → `content/`; затем собирает
интерфейс и компилирует Panorama. Dota не в библиотеке Steam — укажите
папку `dota 2 beta` в `DOTA_PATH`.

## Каждый день

| Команда | Что делает |
| --- | --- |
| `npm run dev` | пересобирает интерфейс при сохранении (VS Code: Ctrl+Shift+B) |
| `npm run compile` | сборка и компиляция Panorama; `-- -f` — принудительно |
| `npm run launch` | Workshop Tools с игрой; консоль — `game/dota/console.log` |
| `npm run lint` / `npm run format` | ESLint и Prettier для `src/panorama` |
| `python tools/tests/run_tests.py` | офлайн-тесты ([подробнее](tools/tests/README.md)) |
| `npm run release -- minor` | версия в `config.lua`, коммит и тег после всех проверок |

## Устройство

```
game/scripts/vscripts/
  addon_game_mode.lua   точка входа: require по порядку, Precache, Activate
  addon_init.lua        LinkLuaModifier (грузится и на клиенте)
  mod/config/           MOD_CONFIG — все настройки
  mod/core/             ядро: конфиг, лог, шина событий, проверка команд клиента
  mod/systems/          системы мода, каждая — свой файл
src/panorama/           интерфейс (TS/React) -> content/panorama/scripts
  shared/mod_types.d.ts контракт клиент–сервер
content/panorama/       разметка и стили
tools/                  setup/compile/launch, выпуск версии, тесты
```

Правила:

- **Слои.** `config` ← `core` ← `systems`. Ядро не знает о системах, системы
  не вызывают друг друга напрямую — общаются через `Mod_GameEvents`
  (`Subscribe`/`Emit`).
- **Конфиг только через `Mod_Config.Get("ПУТЬ")`**, в момент использования.
  Прямое чтение `MOD_CONFIG` и несуществующий путь ловят тесты.
- **Всё от клиента проверяется**: обработчик события начинается с
  `Mod_ClientCommands.Check`.
- **Состояние — в таблице модуля** (`Mod_X = Mod_X or {...}`), обработчики
  движка зовут функции через таблицу: `script_reload` не теряет состояние и
  подхватывает новый код.
- **Контракт в одном месте**: каждое событие и ключ `mod_state` объявлены в
  `mod_types.d.ts`; тесты сверяют его с Lua.

## Как добавить

- **Систему**: `mod/systems/<имя>.lua` с `Mod_<Имя>.Init()`, `require` в
  `addon_game_mode.lua` до `game_mode`, `SafeInit` в `mod/core/game_mode.lua`.
- **Настройку**: поле в `mod/config/config.lua`, чтение `Mod_Config.Get`.
- **Событие клиент → сервер**: имя `mod_*` в `CustomGameEventDeclarations`,
  `CustomGameEventManager:RegisterListener` в системе,
  `GameEvents.SendCustomGameEventToServer` в Panorama.
- **Данные сервер → клиент**: ключ в `mod_state` в `mod_types.d.ts`,
  `CustomNetTables:SetTableValue("mod_state", ...)` в Lua, `Mod.Net.Watch` в
  Panorama.
- **Экран HUD**: `src/panorama/hud/<имя>.tsx` с `namespace Mod { export const
  X = ... Init ... }`, `<include>` в `mod_hud.xml` до `mod_hud.js`, контейнер
  `<Panel id=...>`, `Mod.X.Init()` в `mod_hud.ts`. Новый `<include>` Dota
  подхватывает только после перезапуска игры.
- **Текст**: ключ `mod_hud_*` в обоих `addon_*.txt`. Другой префикс — добавьте
  его в `LOC_PREFIXES` в `tools/tests/run_tests.py`.
- **Чат-команду разработчика**: запись в `COMMANDS` в `mod/core/commands.lua`
  (работает при `DEVELOPMENT_MODE = true`).
- **Набор однотипных вещей** (события, режимы, предметы): дескрипторы-таблицы
  `{ id, weight, OnStart, ... }` в отдельных файлах, которые регистрируются в
  общем реестре; реестр проверяет дескриптор, а планировщик знает только
  реестр. Новая вещь — новый файл, ядро не меняется.

## Ограничения Panorama

- Нет `eval` и `new Function`: библиотеки, которые их используют, не
  загрузятся (`tools/panorama-libs.mjs` проверяет React).
- Нет `@font-face`; `box-shadow` только прямоугольный.
- Разметку компилирует `npm run compile`; если Dota «застряла» на старой
  версии — `npm run compile -- -f`.
````

- [ ] **Step 2: `tools/tests/README.md`**

````markdown
# Офлайн-тесты

Проверяют то, что можно проверить без запуска Dota 2:

- синтаксис всех Lua-скриптов (компиляция LuaJIT, как в игре);
- типы и синтаксис Panorama TS (`tsc --noEmit`, нужен `npm install`);
- локализацию: ключи `mod_hud_*` из кода есть в `addon_russian.txt` и `addon_english.txt`, наборы ключей совпадают;
- контракт клиент–сервер: события и ключи `mod_state` из `src/panorama/shared/mod_types.d.ts` совпадают с тем, что Lua шлёт (`SetTableValue`, строковые литералы) и слушает (`RegisterListener`), а Panorama подписывается только на объявленные события; поля внутри событий не сверяются;
- разметку: каждый скрипт Panorama подключён вместе с файлами, которые он использует;
- выбор следующей версии в `tools/release.mjs`;
- чтение конфига: в `mod/` и `addon_game_mode.lua` нет прямых обращений к `MOD_CONFIG`, только `Mod_Config.Get`, и каждый путь есть в конфиге;
- логику модулей `mod/` на моках Dota API (`harness.lua`), каждый тест — в свежем рантайме.

Запуск:

```text
pip install -r tools/requirements.txt
python tools/tests/run_tests.py
```

Новый тест — функция в таблице, которую возвращает `tools/tests/test_*.lua`.
Моки и проверки (`H.NewHero`, `H.AddPlayer`, `H.FireGameEvent`, `H.listeners`,
`H.netTables`, `H.eq`, `H.logged`, ...) описаны в `harness.lua`. Тесты не
заменяют проверку в Workshop Tools: поведение движка моки не воспроизводят.
````

- [ ] **Step 3: Commit**

```bash
cd "$DST" && git add -A && git commit -q -F - <<'EOF'
docs: README and test guide

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: Проверка в свежем клоне и чистота

**Files:** нет изменений (только проверки; найденное — исправить в шаблоне отдельным коммитом).

- [ ] **Step 1: Личные данные и остатки one_spell**

```bash
cd "$DST" && git grep -n -i -E "baras|onedrive|рабочий|miracles|c:\\\\users|osc|one.spell|casino|chaos" ; echo "grep exit=$?"
git log --format="%an <%ae>" | sort -u
```

Expected: `grep exit=1` (ничего не найдено). Автор коммитов — показать пользователю: имя и email станут публичными вместе с репозиторием.

- [ ] **Step 2: Свежий клон с другим именем**

```bash
cd "/c/Users/baras/OneDrive/Рабочий стол/dota_mods" && git clone -q dota_addon_template template_check
cd template_check && npm run setup && python tools/tests/run_tests.py && npm run lint
```

Expected: `setup` создаёт ссылки `dota_addons/template_check`, сборка и компиляция Panorama без ошибок; `RESULT: OK`; lint чистый.

- [ ] **Step 3: Недопустимое имя папки**

```bash
cd "/c/Users/baras/OneDrive/Рабочий стол/dota_mods" && git clone -q dota_addon_template Bad-Name && node Bad-Name/tools/dota.mjs link; echo "exit=$?"; rm -rf Bad-Name
```

Expected: `Папка репозитория "Bad-Name" не годится как имя аддона: нужны a-z, 0-9 и _`, `exit=1`.

- [ ] **Step 4: Запуск в игре (делает пользователь)**

Пользователь: `cd template_check && npm run launch`. Проверить: внизу справа `v0.1.0`; сверху по центру панель «Нажатий: 0» и кнопка «Нажать»; клик увеличивает счётчик; после `script_reload` в консоли счётчик сохраняется. Дождаться ответа пользователя.

- [ ] **Step 5: Убрать проверочный клон (с подтверждения пользователя)**

Удалить ссылки `dota 2 beta/game/dota_addons/template_check` и `dota 2 beta/content/dota_addons/template_check` (это junction — удалять саму ссылку, не содержимое: `cmd //c rmdir "<путь>"`), затем папку `dota_mods/template_check`. Ссылки `dota_addon_template`, созданные при работе в шаблоне, — так же, если пользователь не хочет их оставить.

---

### Task 7: Публикация на GitHub

`gh` на машине не установлен, поэтому репозиторий создаёт пользователь.

- [ ] **Step 1: Подтверждение**

Показать пользователю итог Task 6 (grep, автор коммитов) и спросить «публикуем?». Без явного «да» не пушить.

- [ ] **Step 2: Пользователь создаёт репозиторий**

github.com/new → владелец `Apersant1`, имя `dota_addon_template`, **Public**, без README/.gitignore/лицензии.

- [ ] **Step 3: Push**

```bash
cd "$DST" && git remote add origin https://github.com/Apersant1/dota_addon_template.git && git push -u origin master
```

Expected: `master -> master`.

- [ ] **Step 4: Флаг Template (пользователь)**

Settings репозитория → General → галочка **Template repository**. Проверить: на странице репозитория появилась кнопка **Use this template**.
