//  @ts-check
import { tanstackConfig } from "@tanstack/eslint-config"

export default [
  ...tanstackConfig,
  {
    rules: {
      "import/no-cycle": "off",
      "import/order": "off",
      "sort-imports": "off",
      "@typescript-eslint/array-type": "off",
      "@typescript-eslint/require-await": "off",
      "@typescript-eslint/naming-convention": "off",
      "pnpm/json-enforce-catalog": "off",
      "@typescript-eslint/no-unnecessary-condition": "off",
    },
  },
  {
    ignores: [
      ".claude",
      "eslint.config.js",
      "prettier.config.js",
      "supabase/**",
      "src/lib/database.types.ts",
      "src/components/ui/**",
      "src/components/reui/**",
      "src/routeTree.gen.ts",
      "worker.js",
    ],
  },
]
