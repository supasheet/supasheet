import { createFileRoute } from "@tanstack/react-router"

import { SecurityMfaCard } from "#/components/account/security-mfa-card"
import { SecurityPasswordCard } from "#/components/account/security-password-card"
import { DefaultHeader } from "#/components/layouts/default-header"
import { PageContainer } from "#/components/layouts/page-container"
import { pageTitle } from "#/lib/page-title"
import { mfaFactorsQueryOptions } from "#/lib/supabase/data/security"

export const Route = createFileRoute("/account/security")({
  head: () => ({ meta: [{ title: pageTitle("Security") }] }),
  loader: ({ context }) => {
    context.queryClient.prefetchQuery(mfaFactorsQueryOptions)
  },
  component: SecurityPage,
})

function SecurityPage() {
  return (
    <div>
      <DefaultHeader
        breadcrumbs={[{ title: "Security", url: "/account/security" }]}
      />
      <PageContainer size="narrow">
        <SecurityPasswordCard />
        <SecurityMfaCard />
      </PageContainer>
    </div>
  )
}
