import { createFileRoute, notFound } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { Card, CardContent, CardFooter, CardHeader } from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import { UserEditForm } from "#/components/users/user-edit-form"
import { pageTitle } from "#/lib/page-title"
import { adminGetUserQueryOptions } from "#/lib/supabase/data/admin-auth"
import { hasRoleQueryOptions } from "#/lib/supabase/data/core"

export const Route = createFileRoute("/core/users/$userId/edit")({
  head: () => ({ meta: [{ title: pageTitle("Edit User") }] }),
  beforeLoad: async ({ context, params: { userId } }) => {
    if (context.authUser?.id === userId) throw notFound()
    const isXAdmin = await context.queryClient.ensureQueryData(
      hasRoleQueryOptions("x-admin")
    )
    if (!isXAdmin) throw notFound()
  },
  loader: async ({ context, params }) => {
    const user = await context.queryClient.ensureQueryData(
      adminGetUserQueryOptions(params.userId)
    )
    if (!user?.user) throw notFound()
  },
  pendingComponent: () => (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-4">
      <Card>
        <CardHeader className="border-b">
          <Skeleton className="h-6 w-28" />
        </CardHeader>
        <CardContent className="space-y-4 py-4">
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="space-y-1.5">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-10 w-full" />
            </div>
          ))}
        </CardContent>
        <CardFooter className="justify-end">
          <Skeleton className="h-9 w-28" />
        </CardFooter>
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
      <UserEditForm user={data.user} />
    </div>
  )
}
