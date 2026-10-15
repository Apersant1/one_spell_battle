# One Spell Chaos

Кастомная игра Dota 2: у героев одна обычная способность и ультимейт, и они
периодически меняются на случайные. Плюс хаос-раунды, казино Огра, Хаос-лавка
и командные курьеры. Подробное описание механик и устройства кода —
[PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md).

## Что нужно

- Windows, Steam и Dota 2 с DLC **Dota 2 Workshop Tools** (Steam → Dota 2 →
  Свойства → DLC).
- [Node.js](https://nodejs.org/) 20 или новее.
- Python 3 — только для тестов и пересборки картинок HUD.
- VS Code — по желанию: при открытии он предложит нужные расширения.

## Первый запуск

```text
git clone <адрес репозитория>
cd one_spell
npm run setup
npm run launch
```

`npm run setup` делает всё сам:

1. ставит зависимости (`npm install`);
2. находит Dota через Steam и подключает аддон: ссылки
   `dota 2 beta/game/dota_addons/one_spell` → `game/` и
   `dota 2 beta/content/dota_addons/one_spell` → `content/` (это junction,
   права администратора не нужны);
3. собирает интерфейс из TypeScript и компилирует Panorama.

Если Dota стоит не в библиотеке Steam, укажите папку `dota 2 beta` в
переменной `DOTA_PATH`. Если в `dota_addons` уже есть своя папка `one_spell`,
`setup` её не тронет и попросит убрать вручную.

`npm run launch` открывает Workshop Tools и сразу запускает матч. Модели,
материалы и частицы Dota в этом режиме компилирует сама при первом обращении.

## Каждый день

| Команда | Что делает |
| --- | --- |
| `npm run dev` | пересобирает интерфейс при сохранении (в VS Code — задача сборки по умолчанию, Ctrl+Shift+B) |
| `npm run compile` | собирает интерфейс и компилирует Panorama; `npm run compile -- -f` — принудительно, если Dota «застряла» на старой версии |
| `npm run launch` | запускает Workshop Tools с игрой; консоль пишется в `game/dota/console.log` |
| `npm run lint` / `npm run format` | ESLint и Prettier для `src/panorama` |
| `python tools/tests/run_tests.py` | офлайн-тесты: Lua, типы, локализация, контракт клиент–сервер ([подробнее](tools/tests/README.md)) |
| `python tools/hud_assets.py` | пересобрать подложки и рамки HUD из исходных картинок |

Python-пакеты для тестов и картинок: `pip install -r tools/requirements.txt`.

Новый `<include>` в разметке Panorama подхватывается только после полного
перезапуска Dota — горячая перезагрузка его не видит.

## Где что лежит

- `game/scripts/vscripts/` — серверная логика на Lua, конфиг режима —
  `osc/config/config.lua`;
- `src/panorama/` — интерфейс на TypeScript и React, собирается в
  `content/panorama/scripts/` (в git не хранится);
- `content/panorama/layout/`, `content/panorama/styles/` — разметка и стили;
- `game/resource/addon_*.txt` — тексты на русском и английском.
