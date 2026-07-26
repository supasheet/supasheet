import { createFileRoute, redirect } from "@tanstack/react-router"
import type { SearchSchemaInput } from "@tanstack/react-router"

import { EmailOtpForm } from "#/components/auth/email-otp-form"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/auth/email-otp")({
  validateSearch: (search: { redirect?: string } & SearchSchemaInput) => ({
    redirect: typeof search.redirect === "string" ? search.redirect : undefined,
  }),
  beforeLoad: ({ context, search }) => {
    if (!context.authConfig.emailEnabled)
      throw redirect({
        to: "/auth/sign-in",
        search: { redirect: search.redirect },
      })
  },
  head: () => ({ meta: [{ title: pageTitle("Sign In With Email Code") }] }),
  component: EmailOtpForm,
})
