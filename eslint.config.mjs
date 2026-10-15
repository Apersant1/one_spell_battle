import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["content/", "game/", "node_modules/", "tools/", "graphify-out/"] },
  {
    files: ["src/panorama/**/*.ts"],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    rules: {
      // Модули Panorama — глобальные скрипты с общим namespace OSC (без import/export)
      "@typescript-eslint/no-namespace": "off",
      // Стиль кода — var и function-выражения, как до перехода на TS
      "no-var": "off",
      "prefer-const": "off",
      // Колбэки Panorama получают аргументы, которые не всегда нужны
      // OSC — общий namespace, его читают другие файлы и XML
      "@typescript-eslint/no-unused-vars": ["error", { args: "none", varsIgnorePattern: "^OSC$" }],
      eqeqeq: "error",
    },
  },
);
