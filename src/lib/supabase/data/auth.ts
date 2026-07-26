import { queryOptions } from "@tanstack/react-query"

import {
  supabase,
  supabasePublishableKey,
  supabaseUrl,
} from "#/lib/supabase/client"

export const authUserQueryOptions = queryOptions({
  queryKey: ["auth", "user"],
  queryFn: async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    return user ?? null
  },
  staleTime: 1000 * 60 * 5,
})

export interface AuthConfig {
  signupEnabled: boolean
  emailEnabled: boolean
  phoneEnabled: boolean
  providers: string[]
}

export const DEFAULT_AUTH_CONFIG: AuthConfig = {
  signupEnabled: true,
  emailEnabled: true,
  phoneEnabled: false,
  providers: [],
}

interface GoTrueSettings {
  disable_signup: boolean
  external: Record<string, boolean>
}

export const authConfigQueryOptions = () =>
  queryOptions({
    queryKey: ["supasheet", "auth-config"],
    queryFn: async (): Promise<AuthConfig> => {
      const response = await fetch(`${supabaseUrl}/auth/v1/settings`, {
        headers: { apikey: supabasePublishableKey },
      })
      if (!response.ok) return DEFAULT_AUTH_CONFIG

      const settings: GoTrueSettings = await response.json()
      const emailEnabled = settings.external.email === true
      const phoneEnabled = settings.external.phone === true

      const providers = Object.entries(settings.external)
        .filter(
          ([key, enabled]) =>
            enabled &&
            key !== "email" &&
            key !== "phone" &&
            key !== "anonymous_users"
        )
        .map(([key]) => key)

      return {
        signupEnabled: !settings.disable_signup,
        emailEnabled,
        phoneEnabled,
        providers,
      }
    },
    staleTime: 1000 * 60 * 5,
  })
