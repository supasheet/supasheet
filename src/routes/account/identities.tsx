import { createFileRoute } from "@tanstack/react-router"

import { IdentityEmailCard } from "#/components/account/identity-email-card"
import { IdentityProvidersCard } from "#/components/account/identity-providers-card"
import { DefaultHeader } from "#/components/layouts/default-header"
import { PageContainer } from "#/components/layouts/page-container"
import { pageTitle } from "#/lib/page-title"
import { identitiesQueryOptions } from "#/lib/supabase/data/identities"

export const Route = createFileRoute("/account/identities")({
  head: () => ({ meta: [{ title: pageTitle("Identities") }] }),
  loader: ({ context }) => {
    context.queryClient.prefetchQuery(identitiesQueryOptions)
  },
  component: IdentitiesPage,
})

function IdentitiesPage() {
  return (
    <div>
      <DefaultHeader
        breadcrumbs={[{ title: "Identities", url: "/account/identities" }]}
      />
      <PageContainer size="narrow">
        <IdentityEmailCard />
        <IdentityProvidersCard />
      </PageContainer>
    </div>
  )
}
