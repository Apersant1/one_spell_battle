// Кладёт UMD-сборки React и react-panorama из node_modules рядом с собранными
// скриптами: osc_hud.xml подключает их до модулей на React.
import { copyFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const out = root + "content/panorama/scripts/custom_game/libraries/";
mkdirSync(out, { recursive: true });
for (const [from, to] of [
  ["node_modules/react/umd/react.production.min.js", "react.js"],
  ["node_modules/react-panorama/dist/umd/react-panorama.production.js", "react-panorama.js"],
]) {
  copyFileSync(root + from, out + to);
}
