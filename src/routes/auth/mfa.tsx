import { createFileRoute, redirect } from "@tanstack/react-router"

import { MfaForm } from "#/components/auth/mfa-form"
import { pageTitle } from "#/lib/page-title"
import { supabase } from "#/lib/supabase/client"
import { mfaFactorsQueryOptions } from "#/lib/supabase/data/security"

export const Route = createFileRoute("/auth/mfa")({
  head: () => ({ meta: [{ title: pageTitle("Two-Factor Authentication") }] }),
  beforeLoad: async ({ context }) => {
    if (!context.authUser) throw redirect({ to: "/auth/sign-in" })
    const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
    // Already at aal2, or no aal2 required — send to app
    if (!data || data.currentLevel === "aal2" || data.nextLevel !== "aal2") {
      throw redirect({ to: "/" })
    }
  },
  loader: ({ context }) => {
    context.queryClient.query(mfaFactorsQueryOptions).catch(() => {})
  },
  component: MfaForm,
})
