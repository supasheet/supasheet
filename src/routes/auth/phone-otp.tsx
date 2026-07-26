import { createFileRoute, redirect } from "@tanstack/react-router"
import type { SearchSchemaInput } from "@tanstack/react-router"

import { PhoneOtpForm } from "#/components/auth/phone-otp-form"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/auth/phone-otp")({
  validateSearch: (search: { redirect?: string } & SearchSchemaInput) => ({
    redirect: typeof search.redirect === "string" ? search.redirect : undefined,
  }),
  beforeLoad: ({ context, search }) => {
    if (!context.authConfig.phoneEnabled)
      throw redirect({
        to: "/auth/sign-in",
        search: { redirect: search.redirect },
      })
  },
  head: () => ({ meta: [{ title: pageTitle("Sign In With Phone Code") }] }),
  component: PhoneOtpForm,
})
