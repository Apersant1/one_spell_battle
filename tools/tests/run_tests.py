"""Офлайн-проверки One Spell Chaos.

1. Синтаксис всех .lua в game/scripts/vscripts (компиляция LuaJIT).
2. Синтаксис всех .js в content/panorama (node --check).
3. Локализация: ключи из кода есть в обоих addon_*.txt, наборы ключей совпадают.
   Цены предметов в npc_items_custom.txt совпадают с OSC_CONFIG.
4. Тесты tools/tests/test_*.lua с моками Dota API (каждый тест в свежем рантайме).

Запуск: pip install lupa && python tools/tests/run_tests.py
"""

import io
import re
import shutil
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
RESOURCE = ROOT / "game" / "resource"
TESTS = Path(__file__).resolve().parent
ITEMS_KV = ROOT / "game" / "scripts" / "npc" / "npc_items_custom.txt"

# KV не может брать цену из Lua-конфига, поэтому держим их согласованными
ITEM_COSTS = {
    "item_osc_anchor": "ANCHOR_COST",
}

LOC_PREFIXES = (
    "osc_casino_err_",
    "osc_casino_result_",
    "osc_casino_items_",
    "osc_anchor_err_",
    "osc_hud_",
    "osc_notify_",
    "osc_ts_",
)
# Имена событий с теми же префиксами — не ключи локализации
NOT_LOC_KEYS = {"osc_hud_error"}


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


def check_js_syntax():
    node = shutil.which("node")
    if not node:
        return ["node not found: JS syntax not checked"]
    errors = []
    for path in sorted(PANORAMA.rglob("*.js")):
        result = subprocess.run([node, "--check", str(path)], capture_output=True, text=True)
        if result.returncode != 0:
            errors.append(f"{path.relative_to(ROOT)}: {result.stderr.strip()}")
    return errors


def localization_keys(path):
    return set(re.findall(r'^\s*"([^"]+)"\s+"', read_text(path), re.M))


def check_localization():
    ru = localization_keys(RESOURCE / "addon_russian.txt")
    en = localization_keys(RESOURCE / "addon_english.txt")
    errors = [f"only in addon_russian.txt: {k}" for k in sorted(ru - en)]
    errors += [f"only in addon_english.txt: {k}" for k in sorted(en - ru)]

    sources = list(VSCRIPTS.rglob("*.lua")) + list(PANORAMA.rglob("*.js")) + list(PANORAMA.rglob("*.xml"))
    used = set()
    for path in sources:
        for key in re.findall(r'["#](osc_[a-z0-9_]+)', read_text(path)):
            if key.startswith(LOC_PREFIXES) and key not in NOT_LOC_KEYS:
                used.add(key)
    for key in sorted(used):
        for name, keys in (("addon_russian.txt", ru), ("addon_english.txt", en)):
            if key not in keys:
                errors.append(f"used in code but missing in {name}: {key}")
    return errors


def kv_item_cost(text, item):
    match = re.search(r'"' + re.escape(item) + r'"\s*\{(.*?)\}', text, re.S)
    if not match:
        return None
    cost = re.search(r'"ItemCost"\s+"(\d+)"', match.group(1))
    return int(cost.group(1)) if cost else None


def check_item_costs():
    runtime = lupa_runtime.LuaRuntime()
    runtime.execute(read_text(VSCRIPTS / "osc" / "config" / "config.lua"))
    config = runtime.globals().OSC_CONFIG
    text = read_text(ITEMS_KV)
    errors = []
    for item, key in ITEM_COSTS.items():
        kv_cost = kv_item_cost(text, item)
        config_cost = config[key]
        if kv_cost is None:
            errors.append(f"{item}: no ItemCost in npc_items_custom.txt")
        elif kv_cost != config_cost:
            errors.append(f"{item}: ItemCost {kv_cost} != OSC_CONFIG.{key} {config_cost}")
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
        ("JS syntax", check_js_syntax),
        ("Localization", check_localization),
        ("Item costs", check_item_costs),
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
