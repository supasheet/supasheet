import { createClient } from "@supabase/supabase-js"

import type { Database } from "../database.types"

declare global {
  interface Window {
    __CONFIG__?: { supabaseUrl: string; publishableKey: string }
  }
}

const config = typeof window !== "undefined" ? window.__CONFIG__ : undefined

export const supabase = createClient<Database>(
  config?.supabaseUrl ?? import.meta.env.VITE_SUPABASE_URL,
  config?.publishableKey ?? import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
)
