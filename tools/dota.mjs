// Компиляция ресурсов Panorama и запуск Workshop Tools.
//   node tools/dota.mjs compile [аргументы resourcecompiler, например -f]
//   node tools/dota.mjs launch
// Папку Dota ищет по Steam (реестр + libraryfolders.vdf); переопределяется
// переменной DOTA_PATH (папка "dota 2 beta"). Аддон должен быть подключён в
// dota_addons ссылкой на content/ и game/ этого репозитория.
// launch пишет консоль в game/dota/console.log (-condebug).
import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const ADDON = "one_spell";
const MAP = "dota";

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

function run(exe, args, options = {}) {
  console.log(`> ${exe} ${args.join(" ")}`);
  return spawn(exe, args, { stdio: "inherit", ...options });
}

const dota = findDota();
const bin = join(dota, "game", "bin", "win64");
const addonContent = join(dota, "content", "dota_addons", ADDON);
if (!existsSync(addonContent)) {
  throw new Error(`Нет ${addonContent}: подключите content/ ссылкой в dota_addons`);
}

const [command, ...extra] = process.argv.slice(2);
if (command === "compile") {
  // Разметка тянет за собой свои скрипты, стили и картинки. Без -f
  // компилируется только изменённое; -f нужен, если Dota «застряла» на старом
  // vxml_c после неудачной компиляции
  const input = join(addonContent, "panorama", "layout", "*.xml");
  run(join(bin, "resourcecompiler.exe"), ["-i", input, "-r", "-nop4", ...extra]).on(
    "exit",
    (code) => process.exit(code ?? 1),
  );
} else if (command === "launch") {
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
  run(join(bin, "dota2.exe"), args, { detached: true, stdio: "ignore" }).unref();
} else {
  console.error("Использование: node tools/dota.mjs compile [-f] | launch");
  process.exit(2);
}
