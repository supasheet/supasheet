import { createFileRoute, notFound } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { Card, CardContent, CardHeader } from "#/components/ui/card"
import { Separator } from "#/components/ui/separator"
import { Skeleton } from "#/components/ui/skeleton"
import { UserSecurity } from "#/components/users/user-security"
import { pageTitle } from "#/lib/page-title"
import { adminGetUserQueryOptions } from "#/lib/supabase/data/admin-auth"
import {
  hasRoleQueryOptions,
  rolesQueryOptions,
} from "#/lib/supabase/data/core"

export const Route = createFileRoute("/core/users/$userId/security")({
  head: () => ({ meta: [{ title: pageTitle("User Security") }] }),
  beforeLoad: async ({ context, params: { userId } }) => {
    if (context.authUser?.id === userId) throw notFound()
    const isXAdmin = await context.queryClient.ensureQueryData(
      hasRoleQueryOptions("x-admin")
    )
    if (!isXAdmin) throw notFound()
  },
  loader: async ({ context, params }) => {
    const data = await context.queryClient.ensureQueryData(
      adminGetUserQueryOptions(params.userId)
    )
    if (!data?.user) throw notFound()

    context.queryClient.ensureQueryData(rolesQueryOptions)
  },
  pendingComponent: () => (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-4">
      <Card>
        <CardHeader className="border-b">
          <Skeleton className="h-6 w-24" />
        </CardHeader>
        <CardContent className="space-y-4 py-4">
          <div className="flex items-center justify-between gap-4">
            <div className="min-w-0 flex-1 space-y-2">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-3 w-full max-w-xs" />
            </div>
            <div className="flex shrink-0 gap-2">
              <Skeleton className="h-9 w-28 rounded-md" />
              <Skeleton className="h-9 w-12 rounded-md" />
            </div>
          </div>
          <Separator />
          <div className="flex items-center justify-between gap-4">
            <div className="min-w-0 flex-1 space-y-2">
              <Skeleton className="h-4 w-36" />
              <Skeleton className="h-3 w-full max-w-sm" />
            </div>
            <Skeleton className="h-9 w-20 shrink-0 rounded-md" />
          </div>
          <div className="flex items-center justify-between gap-4">
            <div className="min-w-0 flex-1 space-y-2">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-3 w-full max-w-sm" />
            </div>
            <Skeleton className="h-9 w-20 shrink-0 rounded-md" />
          </div>
        </CardContent>
      </Card>
    </div>
  ),
  component: RouteComponent,
})

function RouteComponent() {
  const { userId } = Route.useParams()
  const { data } = useSuspenseQuery(adminGetUserQueryOptions(userId))

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-4">
      <UserSecurity user={data.user} />
    </div>
  )
}
