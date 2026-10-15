// Подготовка, компиляция ресурсов и запуск Workshop Tools.
//   node tools/dota.mjs setup     всё для свежего клона: npm install, ссылки
//                                 аддона в dota_addons, сборка, компиляция Panorama
//   node tools/dota.mjs link      только ссылки аддона в dota_addons
//   node tools/dota.mjs compile [аргументы resourcecompiler, например -f]
//                                 разметка Panorama (с её скриптами, стилями, картинками)
//   node tools/dota.mjs launch
// Модели, материалы и частицы отдельно не компилируются: в -tools Dota
// собирает их сама, когда игра к ним обращается.
// Папку Dota ищет по Steam (реестр + libraryfolders.vdf); переопределяется
// переменной DOTA_PATH (папка "dota 2 beta").
// launch пишет консоль в game/dota/console.log (-condebug).
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, symlinkSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ADDON = "one_spell";
const MAP = "dota";
const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function steamPath() {
  const out = execFileSync("reg", ["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"], {
    encoding: "utf8",
  });
  const match = out.match(/SteamPath\s+REG_SZ\s+(.+)/);
  if (!match) throw new Error("Steam не найден в реестре");
  return match[1].trim();
}

function findDota() {
  if (process.env.DOTA_PATH) return process.env.DOTA_PATH;
  const steam = steamPath();
  const vdf = readFileSync(join(steam, "steamapps", "libraryfolders.vdf"), "utf8");
  const libraries = [
    steam,
    ...[...vdf.matchAll(/"path"\s+"([^"]+)"/g)].map((m) => m[1].replace(/\\\\/g, "\\")),
  ];
  for (const library of libraries) {
    const dota = join(library, "steamapps", "common", "dota 2 beta");
    if (existsSync(join(dota, "game", "bin", "win64", "dota2.exe"))) return dota;
  }
  throw new Error("Dota 2 не найдена в библиотеках Steam; задайте DOTA_PATH");
}

function fail(message) {
  console.error(`\n${message}`);
  process.exit(1);
}

// Синхронно, с выводом в консоль; ненулевой код — выход с ошибкой
function runSync(exe, args, options = {}) {
  console.log(`> ${exe} ${args.join(" ")}`);
  const result = spawnSync(exe, args, { stdio: "inherit", ...options });
  if (result.status !== 0) fail(`Команда завершилась с кодом ${result.status}`);
}

const dota = findDota();
const bin = join(dota, "game", "bin", "win64");
const resourceCompiler = join(bin, "resourcecompiler.exe");
const addonContent = join(dota, "content", "dota_addons", ADDON);

// Dota видит аддон через ссылки (junction, прав администратора не нужно):
// <dota>/game/dota_addons/one_spell -> game/, <dota>/content/dota_addons/one_spell -> content/.
// Чужую папку или ссылку не трогаем — только сообщаем
function link() {
  if (!existsSync(resourceCompiler)) {
    fail(
      "Нет Dota 2 Workshop Tools: в Steam откройте свойства Dota 2 → DLC и " +
        "включите «Dota 2 Workshop Tools», затем повторите.",
    );
  }
  for (const part of ["game", "content"]) {
    const target = join(REPO, part);
    const path = join(dota, part, "dota_addons", ADDON);
    let stat = null;
    try {
      stat = lstatSync(path);
    } catch {
      // нет — создадим
    }
    if (stat === null) {
      mkdirSync(dirname(path), { recursive: true });
      symlinkSync(target, path, "junction");
      console.log(`Ссылка: ${path} -> ${target}`);
    } else if (stat.isSymbolicLink() && realpathSync(path) === realpathSync(target)) {
      console.log(`Уже подключено: ${path}`);
    } else {
      fail(
        `${path} уже существует и ведёт не в этот репозиторий.\n` +
          "Переименуйте или удалите её сами (там может быть ваша работа) и повторите.",
      );
    }
  }
}

function requireLinked() {
  if (!existsSync(addonContent)) {
    fail(`Нет ${addonContent}: сначала npm run setup (или node tools/dota.mjs link)`);
  }
}

// Разметка тянет за собой свои скрипты, стили и картинки. Без -f
// компилируется только изменённое; -f нужен, если Dota «застряла» на старом
// vxml_c после неудачной компиляции
function compileLayouts(extra) {
  requireLinked();
  const input = join(addonContent, "panorama", "layout", "*.xml");
  runSync(resourceCompiler, ["-i", input, "-r", "-nop4", ...extra]);
}

const npm = process.platform === "win32" ? "npm.cmd" : "npm";
const [command, ...extra] = process.argv.slice(2);

if (command === "setup") {
  if (!existsSync(join(REPO, "node_modules"))) {
    // shell: .cmd на Windows запускается только через оболочку
    runSync(npm, ["install"], { cwd: REPO, shell: true });
  }
  link();
  runSync(npm, ["run", "build"], { cwd: REPO, shell: true });
  compileLayouts(extra);
  console.log("\nГотово. Запуск игры: npm run launch");
} else if (command === "link") {
  link();
} else if (command === "compile") {
  compileLayouts(extra);
} else if (command === "launch") {
  requireLinked();
  const args = [
    "-tools",
    "-addon",
    ADDON,
    "-novid",
    "-condebug",
    "+dota_launch_custom_game",
    ADDON,
    MAP,
  ];
  console.log(`> ${join(bin, "dota2.exe")} ${args.join(" ")}`);
  spawn(join(bin, "dota2.exe"), args, { detached: true, stdio: "ignore" }).unref();
} else {
  console.error("Использование: node tools/dota.mjs setup | link | compile [-f] | launch");
  process.exit(2);
}
