import { createFileRoute } from "@tanstack/react-router"

import { RolesPermissionsCard } from "#/components/account/roles-permissions-card"
import { DefaultHeader } from "#/components/layouts/default-header"
import { PageContainer } from "#/components/layouts/page-container"
import { pageTitle } from "#/lib/page-title"
import {
  userPermissionsQueryOptions,
  whoamiQueryOptions,
} from "#/lib/supabase/data/core"

export const Route = createFileRoute("/account/roles-permissions")({
  head: () => ({ meta: [{ title: pageTitle("Roles & Permissions") }] }),
  loader: ({ context }) => {
    context.queryClient.prefetchQuery(whoamiQueryOptions)
    context.queryClient.prefetchQuery(userPermissionsQueryOptions())
  },
  component: RolesPermissionsPage,
})

function RolesPermissionsPage() {
  return (
    <div>
      <DefaultHeader
        breadcrumbs={[
          { title: "Roles & Permissions", url: "/account/roles-permissions" },
        ]}
      />
      <PageContainer size="narrow">
        <RolesPermissionsCard />
      </PageContainer>
    </div>
  )
}
