import { queryOptions } from "@tanstack/react-query"

import { supabase } from "#/lib/supabase/client"

export interface AppConfig {
  name: string
  description: string
}

export const DEFAULT_APP_CONFIG: AppConfig = {
  name: "Supasheet",
  description: "Turn your Postgres schema into any business app.",
}

function asString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value : fallback
}

export const appConfigQueryOptions = () =>
  queryOptions({
    queryKey: ["supasheet", "app-config"],
    queryFn: async (): Promise<AppConfig> => {
      const { data, error } = await supabase
        .schema("supasheet")
        .from("configs")
        .select("key, value")
        .eq("is_public", true)
      if (error || !data) return DEFAULT_APP_CONFIG

      const byKey = new Map(data.map((row) => [row.key, row.value]))
      return {
        name: asString(byKey.get("app.name"), DEFAULT_APP_CONFIG.name),
        description: asString(
          byKey.get("app.description"),
          DEFAULT_APP_CONFIG.description
        ),
      }
    },
    staleTime: 1000 * 60 * 5,
  })
