# Офлайн-тесты

Проверяют то, что можно проверить без запуска Dota 2:

- синтаксис всех Lua-скриптов (компиляция LuaJIT, как в игре);
- типы и синтаксис Panorama TS (`tsc --noEmit`, нужен `npm install`);
- локализацию: ключи из кода есть в `addon_russian.txt` и `addon_english.txt`, наборы ключей совпадают;
- чтение конфига: в `osc/` и `addon_game_mode.lua` нет прямых обращений к `OSC_CONFIG`, только `OSC_Config.Get`;
- логику модулей `osc/` на моках Dota API (`harness.lua`), каждый тест — в свежем рантайме.

Запуск:

```text
pip install lupa
python tools/tests/run_tests.py
```

Новый тест — функция в таблице, которую возвращает `tools/tests/test_*.lua`.
Моки и проверки (`H.NewHero`, `H.DefineAbility`, `H.AddPlayer`, `H.eq`, ...)
описаны в `harness.lua`. Тесты не заменяют проверку в Workshop Tools:
поведение движка (частицы, модификаторы, способности Dota) моки не воспроизводят.
