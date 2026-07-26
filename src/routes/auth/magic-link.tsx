import { createFileRoute, redirect } from "@tanstack/react-router"
import type { SearchSchemaInput } from "@tanstack/react-router"

import { MagicLinkForm } from "#/components/auth/magic-link-form"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/auth/magic-link")({
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
  head: () => ({ meta: [{ title: pageTitle("Sign In With Magic Link") }] }),
  component: MagicLinkForm,
})
