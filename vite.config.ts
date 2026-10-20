import { devtools } from "@tanstack/devtools-vite"
import { tanstackRouter } from "@tanstack/router-plugin/vite"

import tailwindcss from "@tailwindcss/vite"
import viteReact from "@vitejs/plugin-react"
import { defineConfig } from "vite-plus"

const config = defineConfig({
  base: "/",
  resolve: {
    tsconfigPaths: true,
  },
  plugins: [
    devtools(),
    tailwindcss(),
    tanstackRouter({ target: "react", autoCodeSplitting: true }),
    viteReact(),
  ],
  lint: {
    ignorePatterns: [
      ".claude",
      "supabase/**",
      "src/lib/database.types.ts",
      "src/components/ui/**",
      "src/components/reui/**",
      "src/routeTree.gen.ts",
      "worker.js",
    ],
    options: {
      typeAware: true,
      typeCheck: true,
    },
  },
  fmt: {
    endOfLine: "lf",
    semi: false,
    singleQuote: false,
    tabWidth: 2,
    trailingComma: "es5",
    printWidth: 80,
    ignorePatterns: [
      "package-lock.json",
      "pnpm-lock.yaml",
      "yarn.lock",
      "supabase/**/*.sql",
      "src/routeTree.gen.ts",
      "src/lib/database.types.ts",
      "src/components/reui",
      "src/components/ui",
    ],
    sortImports: {
      newlinesBetween: true,
      customGroups: [
        { groupName: "react", elementNamePattern: ["react", "react-dom"] },
        { groupName: "supabase", elementNamePattern: ["@supabase/**"] },
        { groupName: "tanstack", elementNamePattern: ["@tanstack/**"] },
      ],
      groups: [
        "react",
        "supabase",
        "tanstack",
        ["builtin", "external"],
        ["internal", "subpath"],
        ["parent", "sibling", "index"],
        "style",
        "unknown",
      ],
    },
    sortTailwindcss: {
      stylesheet: "src/styles.css",
      functions: ["cn", "cva"],
    },
  },
})

export default config
