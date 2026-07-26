import type { User } from "@supabase/supabase-js"

import { useNavigate } from "@tanstack/react-router"

import { useQueryClient } from "@tanstack/react-query"

import { supabase } from "#/lib/supabase/client"
import { authUserQueryOptions } from "#/lib/supabase/data/auth"

export function useCompleteSignIn(redirect?: string) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const safeRedirect =
    redirect?.startsWith("/") && !redirect.startsWith("//") ? redirect : "/"

  return async (user: User) => {
    queryClient.setQueryData(authUserQueryOptions.queryKey, user)
    const { data: aalData } =
      await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
    if (aalData?.currentLevel === "aal1" && aalData?.nextLevel === "aal2") {
      navigate({ to: "/auth/mfa", replace: true })
      return
    }
    navigate({ to: safeRedirect, replace: true })
  }
}
