import { createClient } from "@supabase/supabase-js"

import type { Database } from "../database.types"

declare global {
  interface Window {
    __CONFIG__?: { supabaseUrl: string; publishableKey: string }
  }
}

const config = typeof window !== "undefined" ? window.__CONFIG__ : undefined

export const supabaseUrl =
  config?.supabaseUrl ?? import.meta.env.VITE_SUPABASE_URL
export const supabasePublishableKey =
  config?.publishableKey ?? import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const supabase = createClient<Database>(
  supabaseUrl,
  supabasePublishableKey
)
