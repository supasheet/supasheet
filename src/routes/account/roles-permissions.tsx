import { createFileRoute } from "@tanstack/react-router"

import { RolesPermissionsCard } from "#/components/account/roles-permissions-card"
import { DefaultHeader } from "#/components/layouts/default-header"
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
      <div className="mx-auto w-full max-w-2xl space-y-4 p-6">
        <RolesPermissionsCard />
      </div>
    </div>
  )
}
