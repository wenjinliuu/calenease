import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  globalIgnores([
    ".next/**",
    ".netlify/**",
    "out/**",
    "ios/**",
    // 腾讯云上的节假日 HTTP 函数，是独立的 Node CommonJS 包，不属于网页端。
    "cloudbase/**",
    "next-env.d.ts",
  ]),
]);
