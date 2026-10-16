# Шаблон-репозиторий для модов Dota 2

## Цель

Отдельный публичный репозиторий `Apersant1/dota_addon_template` (флаг Template
на GitHub), из которого новый мод стартует так:

```text
git clone <шаблон> my_mod
cd my_mod
npm run setup
npm run launch
```

и сразу работает пустой мод с архитектурой One Spell: раскладка `game/` +
`src/panorama/` + `content/`, слои Lua `config → core → systems`, конфиг только
через `Mod_Config.Get`, контракт клиент–сервер в одном `.d.ts`, офлайн-тесты,
npm-скрипты. Имя аддона — имя папки клона (`tools/dota.mjs`, уже сделано в
one_spell).

Шаблон — голый скелет: ядро, один пример на каждый механизм, тесты, tools.
Готовых экранов (выбор команд, голосование, итоги, помощь) нет.

## Решения

- **Префикс один навсегда: `mod`.** Папка `vscripts/mod/`, глобальные
  `Mod_Config`, `Mod_Logger`, ..., файлы `mod_hud.xml`, net table `mod_state`,
  события `mod_*`, ключи локализации `mod_*`. У каждого аддона свой Lua VM и
  свой Panorama, конфликтов между модами нет — скрипта переименования нет.
- **Источник — копия one_spell с вырезанием**, one_spell не меняется.
- **Чистая история:** `git init` в `dota_mods/dota_addon_template`.
- **Карт нет.** Аддон берёт стандартную `dota` из игры (у one_spell в
  `game/maps` нет `dota.vpk`, и это работает); `content/maps/dota.vmap`
  (63 МБ) нужен только для Hammer.
- **Реестр хаос-событий не переносится**: он срощен с планировщиком
  хаос-раундов, обобщать его — новый код без потребителя. Паттерн
  «дескриптор + реестр» описан в README несколькими строками.

## Состав

```
game/
  addoninfo.txt                 карта dota, 2 команды, 1–10 игроков
  resource/addon_english.txt    минимум ключей (пример HUD)
  resource/addon_russian.txt
  scripts/custom_net_tables.txt mod_state
  scripts/npc/*.txt             пустые KV-заготовки (abilities, items, units, heroes, override)
  scripts/vscripts/addon_game_mode.lua   require по порядку + Precache
  scripts/vscripts/mod/config/config.lua VERSION + пример настройки
  scripts/vscripts/mod/core/    logger, util, runtime_config, game_mode,
                                game_events, client_commands, commands
  scripts/vscripts/mod/systems/example.lua
src/panorama/
  tsconfig.json
  shared/mod_core.ts, mod_types.d.ts, mod_components.tsx
  hud/mod_hud.tsx
content/panorama/layout/custom_game/custom_ui_manifest.xml, mod_hud.xml
content/panorama/styles/custom_game/mod_hud.css
tools/dota.mjs, panorama-libs.mjs, release.mjs, requirements.txt
tools/tests/harness.lua, run_tests.py, README.md, test_smoke.lua, test_example.lua
package.json, eslint.config.mjs, .prettierrc.json, .vscode/, .gitignore, README.md
```

Не входят: игровые системы, `heroes`, `hero_state`, `gold`, `anchor`,
`notifications`, `hud_assets.py`, карты, `docs/`, тестовые модели и частицы
из `content/`. Модули ядра, которые ссылаются на игровые системы
(`game_mode`, `commands`, `game_events`), чистятся от этих ссылок; если
оставшемуся ядру нужен `heroes`/`hero_state`, он переносится, иначе нет.

## Пример: путь клиент–сервер

1. `systems/example.lua` при старте игры пишет `mod_state.example`
   (`{ clicks = 0 }`) и слушает клиентскую команду `mod_example_click`.
2. По команде сервер увеличивает `clicks` и переписывает `mod_state.example`.
3. `hud/mod_hud.tsx` показывает `clicks` и кнопку, которая шлёт
   `mod_example_click`.
4. Событие и ключ объявлены в `mod_types.d.ts`; тест контракта сверяет их с Lua.
5. Подпись кнопки — ключ локализации в обоих языковых файлах.

## Тесты

`run_tests.py`: `osc` → `mod`, убраны игровые префиксы и игровые
динамические ключи локализации. Остаются проверки: синтаксис Lua (LuaJIT),
`tsc --noEmit`, локализация (ключи из кода есть в обоих языках, наборы
совпадают), контракт клиент–сервер, разметка подключает нужные скрипты,
release-скрипт, конфиг только через `Mod_Config.Get`, пути
`Mod_Config.Get("...")` есть в конфиге. `harness.lua` переносится целиком
(с `osc` → `mod`). Тесты логики: `test_smoke.lua` (все модули грузятся,
игра стартует на моках) и `test_example.lua` (клик увеличивает счётчик и
пишет net table).

## Готово, когда

- в свежем клоне `npm run setup` проходит, `python tools/tests/run_tests.py` зелёный,
  `npm run lint` чистый;
- `npm run launch` открывает игру, HUD-пример виден, кнопка увеличивает
  счётчик (проверяет пользователь — игра у агента не видна);
- в репозитории нет личных данных и путей пользователя (grep перед пушем);
- репозиторий опубликован публичным, с флагом Template.
