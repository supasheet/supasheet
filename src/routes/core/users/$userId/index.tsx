import { createFileRoute, notFound } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { Card, CardContent, CardHeader } from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import { UserOverview } from "#/components/users/user-overview"
import { pageTitle } from "#/lib/page-title"
import { adminGetUserQueryOptions } from "#/lib/supabase/data/admin-auth"

export const Route = createFileRoute("/core/users/$userId/")({
  head: () => ({ meta: [{ title: pageTitle("Overview | Users") }] }),
  loader: async ({ context, params }) => {
    const data = await context.queryClient.query({
      ...adminGetUserQueryOptions(params.userId),
      staleTime: "static",
    })
    if (!data?.user) throw notFound()
  },
  pendingComponent: () => (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-4">
      <Card>
        <CardHeader className="border-b">
          <Skeleton className="h-6 w-28" />
        </CardHeader>
        <CardContent className="space-y-2 py-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <div
              key={i}
              className="grid grid-cols-[8rem_1fr] items-center gap-1"
            >
              <Skeleton className="h-4 w-14" />
              <Skeleton className="h-4 w-full" />
            </div>
          ))}
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
      <UserOverview user={data.user} />
    </div>
  )
}
