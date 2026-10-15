"""Офлайн-проверки One Spell Chaos.

1. Синтаксис всех .lua в game/scripts/vscripts (компиляция LuaJIT).
2. Типы и синтаксис Panorama TS в src/panorama (tsc --noEmit).
3. Локализация: ключи из кода есть в обоих addon_*.txt, наборы ключей совпадают.
3a. Контракт клиент–сервер: события и ключи osc_state из src/panorama/shared/osc_types.d.ts
    совпадают с тем, что шлёт и слушает Lua.
4. Тесты tools/tests/test_*.lua с моками Dota API (каждый тест в свежем рантайме).

Запуск: pip install lupa && python tools/tests/run_tests.py
"""

import io
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import lupa.luajit21 as lupa_runtime
except ImportError:  # pragma: no cover - запасной вариант без LuaJIT
    import lupa as lupa_runtime

ROOT = Path(__file__).resolve().parents[2]
VSCRIPTS = ROOT / "game" / "scripts" / "vscripts"
PANORAMA = ROOT / "content" / "panorama"
PANORAMA_SRC = ROOT / "src" / "panorama"
RESOURCE = ROOT / "game" / "resource"
TESTS = Path(__file__).resolve().parent

LOC_PREFIXES = (
    "osc_casino_err_",
    "osc_casino_result_",
    "osc_casino_items_",
    "osc_anchor_err_",
    "osc_shop_",
    "osc_sphere_",
    "osc_hud_",
    "osc_notify_",
    "osc_ts_",
)


def read_text(path):
    return io.open(path, encoding="utf-8-sig").read()


def read_module(name):
    """Поиск модуля для require: сначала vscripts, потом tools/tests."""
    for base in (VSCRIPTS, TESTS):
        path = base / (name.replace(".", "/") + ".lua")
        if path.is_file():
            return read_text(path)
    return None


def new_runtime():
    # Lua сам не откроет путь с кириллицей на Windows, поэтому файлы
    # читает Python, а Lua получает исходник через свой загрузчик модулей.
    runtime = lupa_runtime.LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().py_read_module = read_module
    runtime.execute(
        """
        table.insert(package.loaders, 2, function(name)
            local source = py_read_module(name)
            if not source then return nil end
            local chunk, err = loadstring(source, "@" .. name)
            if not chunk then error(err) end
            return chunk
        end)
        """
    )
    runtime.execute(read_text(TESTS / "harness.lua"))
    return runtime


def check_lua_syntax():
    runtime = lupa_runtime.LuaRuntime()
    compile_source = runtime.eval("function(src, name) local f, err = loadstring(src, name) return err end")
    errors = []
    for path in sorted(VSCRIPTS.rglob("*.lua")):
        err = compile_source(read_text(path), "@" + str(path.relative_to(ROOT)))
        if err:
            errors.append(err)
    return errors


def check_ts_types():
    tsc = ROOT / "node_modules" / ".bin" / ("tsc.cmd" if os.name == "nt" else "tsc")
    if not tsc.is_file():
        return ["node_modules not found (npm install): Panorama TS not checked"]
    # shell=True: на Windows .cmd запускается только через cmd.exe
    result = subprocess.run(
        f'"{tsc}" --noEmit -p "{PANORAMA_SRC / "tsconfig.json"}"',
        capture_output=True, text=True, shell=True,
    )
    return result.stdout.strip().splitlines() if result.returncode != 0 else []


def declared_contract():
    """События и ключи osc_state из src/panorama/shared/osc_types.d.ts: (события, ключи, префиксы ключей)."""
    text = read_text(PANORAMA_SRC / "shared" / "osc_types.d.ts")
    events = re.search(r"^interface CustomGameEventDeclarations \{(.*?)^\}", text, re.S | re.M).group(1)
    state = re.search(r"^  osc_state: \{(.*?)^  \};", text, re.S | re.M).group(1)
    return (
        set(re.findall(r"^  (osc_[a-z0-9_]+)\??:", events, re.M)),
        set(re.findall(r"^    ([a-z0-9_]+)\??:", state, re.M)),
        set(re.findall(r"^    \[key: `([a-z0-9_]+)\$\{number\}`\]", state, re.M)),
    )


def check_contract():
    events, keys, prefixes = declared_contract()
    lua = "\n".join(read_text(p) for p in VSCRIPTS.rglob("*.lua"))
    ts = "\n".join(read_text(p) for p in [*PANORAMA_SRC.rglob("*.ts"), *PANORAMA_SRC.rglob("*.tsx")])
    lua_strings = set(re.findall(r'"([a-z0-9_]+)"', lua))
    errors = []
    for name in sorted(set(re.findall(r'GameEvents\.Subscribe\(\s*"(osc_[a-z0-9_]+)"', ts)) - events):
        errors.append(f"panorama subscribes to {name}, not declared in osc_types.d.ts")
    for name in sorted(set(re.findall(r'RegisterListener\(\s*"([a-z0-9_]+)"', lua)) - events):
        errors.append(f"Lua listens for {name}, not declared in osc_types.d.ts")
    # Имя может прийти и через переменную (FEED_EVENT, settings.event) — ищем любой литерал
    for name in sorted(events - lua_strings):
        errors.append(f"event {name} declared in osc_types.d.ts but never used in Lua")
    for key, concat in re.findall(r'SetTableValue\(\s*"osc_state"\s*,\s*"([a-z0-9_]+)"(\s*\.\.)?', lua):
        if key not in (prefixes if concat else keys):
            errors.append(f"Lua writes osc_state/{key}{'<id>' if concat else ''}, not declared in osc_types.d.ts")
    for key in sorted((keys | prefixes) - lua_strings):
        errors.append(f"osc_state/{key} declared in osc_types.d.ts but never written by Lua")
    return errors


def check_layout_includes():
    """Скрипты Panorama — глобальные, tsc не видит, подключён ли в разметке файл,
    который определяет OSC.<имя> (или член OSC.<ns> из соседнего файла)."""
    sources = [*PANORAMA_SRC.rglob("*.ts"), *PANORAMA_SRC.rglob("*.tsx")]
    defines = {}  # файл -> {"OSC.Util", "OSC.Help", "OSC.Help.L", ...}
    for path in sources:
        text = read_text(path)
        names = set()
        for ns, body in re.findall(r"^namespace (OSC(?:\.\w+)?) \{\n(.*?)^\}", text, re.S | re.M):
            if ns != "OSC":
                names.add(ns)
            names |= {f"{ns}.{n}" for n in re.findall(r"^  export (?:function|const|var|type) (\w+)", body, re.M)}
        defines[path] = names
    errors = []
    for layout in sorted((PANORAMA / "layout" / "custom_game").glob("*.xml")):
        included = re.findall(r"scripts/custom_game/([\w/-]+)\.js", read_text(layout))
        files = [p for p in sources if p.relative_to(PANORAMA_SRC).with_suffix("").as_posix() in included]
        available = set().union(*(defines[p] for p in files)) if files else set()
        for path in files:
            text = read_text(path)
            rel = path.relative_to(PANORAMA_SRC).as_posix()
            used = {"OSC." + n for n in re.findall(r"\bOSC\.(\w+)", text)}
            for ns in re.findall(r"^namespace (OSC\.\w+) \{", text, re.M):
                # члены своего пространства имён из соседних файлов — без префикса
                used |= {n for p in sources if p != path for n in defines[p]
                         if n.startswith(ns + ".") and re.search(rf"\b{n.split('.')[-1]}\b", text)}
            for name in sorted(used - available):
                if any(name in defines[p] for p in sources):
                    errors.append(f"{layout.name}: {rel} uses {name}, its file is not included")
            if path.suffix == ".tsx" and not {"libraries/react", "libraries/react-panorama"} <= set(included):
                errors.append(f"{layout.name}: {rel} needs libraries/react.js and react-panorama.js")
    return errors


def localization_keys(path):
    return set(re.findall(r'^\s*"([^"]+)"\s+"', read_text(path), re.M))


def dynamic_localization_keys():
    """Ключи, которые код собирает из id в конфиге: голосование и титулы итогов."""
    runtime = lupa_runtime.LuaRuntime()
    runtime.execute(read_text(VSCRIPTS / "osc" / "config" / "config.lua"))
    config = runtime.globals().OSC_CONFIG
    keys = set()
    for question in (config.VOTE_QUESTIONS or {}).values():
        qid = question.id
        keys.add(f"osc_hud_vote_q_{qid}")
        for option in question.options.values():
            keys.add(f"osc_hud_vote_opt_{qid}_{option.value}")
            # Числа лента подставляет как есть (OSC_Notifications.VoteResult)
            if not str(option.value).lstrip("-").replace(".", "", 1).isdigit():
                keys.add(f"osc_notify_vote_{qid}_{option.value}")
    for title in (config.SUMMARY_TITLES or {}).values():
        keys.add(f"osc_hud_title_{title}")
        keys.add(f"osc_hud_title_{title}_desc")
    return keys


def check_localization():
    ru = localization_keys(RESOURCE / "addon_russian.txt")
    en = localization_keys(RESOURCE / "addon_english.txt")
    errors = [f"only in addon_russian.txt: {k}" for k in sorted(ru - en)]
    errors += [f"only in addon_english.txt: {k}" for k in sorted(en - ru)]

    sources = list(VSCRIPTS.rglob("*.lua")) + list(PANORAMA_SRC.rglob("*.ts")) + list(PANORAMA_SRC.rglob("*.tsx")) + list(PANORAMA.rglob("*.xml"))
    used = set()
    not_loc_keys = declared_contract()[0]  # имена событий с теми же префиксами
    for path in sources:
        for key in re.findall(r'["#](osc_[a-z0-9_]+)', read_text(path)):
            # "osc_notify_vote_" и т. п. — префикс ключа, собираемого в коде
            if key.startswith(LOC_PREFIXES) and key not in not_loc_keys and not key.endswith("_"):
                used.add(key)
    used |= dynamic_localization_keys()
    for key in sorted(used):
        for name, keys in (("addon_russian.txt", ru), ("addon_english.txt", en)):
            if key not in keys:
                errors.append(f"used in code but missing in {name}: {key}")
    return errors


def check_config_reads():
    """Конфиг читается только через OSC_Config.Get (core/runtime_config.lua)."""
    errors = []
    sources = list((VSCRIPTS / "osc").rglob("*.lua")) + [VSCRIPTS / "addon_game_mode.lua"]
    for path in sources:
        rel = path.relative_to(VSCRIPTS).as_posix()
        if rel.startswith("osc/config/") or rel == "osc/core/runtime_config.lua":
            continue
        for number, line in enumerate(read_text(path).splitlines(), 1):
            if "OSC_CONFIG" in line and not line.strip().startswith("--"):
                errors.append(f"{rel}:{number}: read config through OSC_Config.Get")
    return errors


def run_lua_tests():
    failures, passed = [], 0
    for path in sorted(TESTS.glob("test_*.lua")):
        source = read_text(path)
        names = sorted(new_runtime().execute(source).keys())
        for name in names:
            runtime = new_runtime()
            suite = runtime.execute(source)
            result = runtime.globals().pcall(suite[name])
            ok, err = result if isinstance(result, tuple) else (result, None)
            label = f"{path.stem}.{name}"
            if ok:
                passed += 1
                print(f"  PASS {label}")
            else:
                failures.append(f"{label}: {err}")
                print(f"  FAIL {label}: {err}")
    return passed, failures


def main():
    problems = 0
    for title, check in (
        ("Lua syntax", check_lua_syntax),
        ("Panorama types", check_ts_types),
        ("Localization", check_localization),
        ("Client-server contract", check_contract),
        ("Layout includes", check_layout_includes),
        ("Config reads", check_config_reads),
    ):
        errors = check()
        print(f"{title}: {'OK' if not errors else 'FAIL'}")
        for error in errors:
            print(f"  {error}")
        problems += len(errors)

    print("Lua tests:")
    passed, failures = run_lua_tests()
    problems += len(failures)
    print(f"Lua tests: {passed} passed, {len(failures)} failed")

    print("RESULT:", "OK" if problems == 0 else f"FAIL ({problems} problems)")
    return 0 if problems == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
