import { getRouteApi } from "@tanstack/react-router"

import { DEFAULT_AUTH_CONFIG } from "#/lib/supabase/data/auth"
import type { AuthConfig } from "#/lib/supabase/data/auth"

const routeApi = getRouteApi("/auth")

export function useAuthConfig(): AuthConfig {
  const context = routeApi.useRouteContext()
  return context.authConfig ?? DEFAULT_AUTH_CONFIG
}
