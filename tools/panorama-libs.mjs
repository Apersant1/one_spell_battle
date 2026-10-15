// Кладёт UMD-сборки React и react-panorama из node_modules рядом с собранными
// скриптами: osc_hud.xml подключает их до модулей на React.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const out = root + "content/panorama/scripts/custom_game/libraries/";

// UMD-обёртка React зовётся в strict-режиме (this === undefined) и тогда
// ищет глобальный self, которого в Panorama нет
const SELF_SHIM = "var self = globalThis;\n";

mkdirSync(out, { recursive: true });
for (const [from, to, prefix] of [
  ["node_modules/react/umd/react.production.min.js", "react.js", SELF_SHIM],
  [
    "node_modules/@demon673/react-panorama/dist/umd/react-panorama.production.js",
    "react-panorama.js",
    "",
  ],
]) {
  const source = readFileSync(root + from, "utf8");
  // Panorama запрещает код из строк (EvalError) — такая библиотека не загрузится
  if (/new Function\(|\beval\(/.test(source)) throw new Error(`${from}: eval/new Function`);
  writeFileSync(out + to, prefix + source);
}
