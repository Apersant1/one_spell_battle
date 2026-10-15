// Выпуск версии: npm run release -- <patch|minor|major|X.Y.Z> [--dry-run]
// 1. рабочая копия должна быть чистой;
// 2. тесты, линтер, сборка и компиляция Panorama;
// 3. новая версия в OSC_CONFIG.VERSION (config.lua — единственное место версии);
// 4. коммит «chore: bump version to X.Y.Z» и тег vX.Y.Z, в описании тега —
//    feat/fix-коммиты с прошлой версии.
// Ничего не пушит: в конце подсказывает команду.
// --dry-run — только показать, что будет сделано.
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONFIG = join(REPO, "game", "scripts", "vscripts", "osc", "config", "config.lua");
const VERSION_RE = /VERSION = "(\d+)\.(\d+)\.(\d+)"/;

function fail(message) {
  console.error(`\n${message}`);
  process.exit(1);
}

function git(...args) {
  // stderr не показываем: «нет тегов» — обычная ситуация до первого выпуска
  return execFileSync("git", args, {
    cwd: REPO,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function step(title, exe, args) {
  console.log(`\n== ${title}: ${exe} ${args.join(" ")}`);
  // shell: npm.cmd и python на Windows запускаются через оболочку
  const result = spawnSync(exe, args, { cwd: REPO, stdio: "inherit", shell: true });
  if (result.status !== 0) fail(`${title}: ошибка (код ${result.status}), выпуск отменён`);
}

export function NextVersion(current, kind) {
  var [major, minor, patch] = current;
  if (kind === "major") return [major + 1, 0, 0];
  if (kind === "minor") return [major, minor + 1, 0];
  if (kind === "patch") return [major, minor, patch + 1];
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(kind || "");
  if (!match) return null;
  const next = match.slice(1).map(Number);
  // явная версия должна быть больше текущей
  for (var i = 0; i < 3; i++) {
    if (next[i] !== current[i]) return next[i] > current[i] ? next : null;
  }
  return null;
}

// Прошлая версия: последний тег, а до первого тега — последний коммит повышения версии
function PreviousRelease() {
  try {
    return git("describe", "--tags", "--abbrev=0");
  } catch {
    return git("log", "-1", "--format=%h", "--grep=^chore: bump version to") || null;
  }
}

function Changes(since) {
  const range = since ? `${since}..HEAD` : "HEAD";
  return git("log", range, "--no-merges", "--format=%s")
    .split("\n")
    .filter((subject) => /^(feat|fix)(\(.+\))?:/.test(subject));
}

function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const kind = args.find((arg) => !arg.startsWith("--"));

  const source = readFileSync(CONFIG, "utf8");
  const found = VERSION_RE.exec(source);
  if (!found) fail(`Не найдена строка VERSION = "X.Y.Z" в ${CONFIG}`);
  const current = found.slice(1).map(Number);
  const next = NextVersion(current, kind);
  if (!next) {
    fail(
      "Использование: npm run release -- <patch|minor|major|X.Y.Z> [--dry-run]\n" +
        `Текущая версия ${current.join(".")}; явная версия должна быть больше неё.`,
    );
  }
  const version = next.join(".");
  const tag = `v${version}`;

  if (git("status", "--porcelain"))
    fail("Есть незакоммиченные изменения: закоммитьте или уберите их.");
  if (git("tag", "--list", tag)) fail(`Тег ${tag} уже есть.`);

  const since = PreviousRelease();
  const changes = Changes(since);
  console.log(`Версия: ${current.join(".")} -> ${version}`);
  console.log(`Изменения с ${since || "начала истории"} (${changes.length}):`);
  changes.forEach((subject) => console.log(`  - ${subject}`));
  if (dryRun) {
    console.log(`\n--dry-run: ничего не изменено. Без него будут проверки, коммит и тег ${tag}.`);
    return;
  }

  step("Тесты", "python", ["tools/tests/run_tests.py"]);
  step("Линтер", "npm", ["run", "lint"]);
  step("Сборка и компиляция Panorama", "npm", ["run", "compile"]);

  writeFileSync(CONFIG, source.replace(VERSION_RE, `VERSION = "${version}"`));
  git("add", CONFIG);
  git("commit", "-q", "-m", `chore: bump version to ${version}`);
  const notes = [`One Spell Chaos ${version}`, "", ...changes.map((subject) => `- ${subject}`)];
  git("tag", "-a", tag, "-m", notes.join("\n"));

  console.log(`\nГотово: коммит и тег ${tag}. Отправить: git push --follow-tags`);
}

// Импорт ради NextVersion (самопроверка) не запускает выпуск
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
