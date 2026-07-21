import { createFileRoute, notFound } from "@tanstack/react-router"

import { DefaultHeader } from "#/components/layouts/default-header"
import { Card, CardContent, CardFooter, CardHeader } from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import { UserCreateForm } from "#/components/users/user-create-form"
import { pageTitle } from "#/lib/page-title"
import { hasRoleQueryOptions } from "#/lib/supabase/data/core"

export const Route = createFileRoute("/core/users/new")({
  head: () => ({ meta: [{ title: pageTitle("New User") }] }),
  beforeLoad: async ({ context }) => {
    const isXAdmin = await context.queryClient.ensureQueryData(
      hasRoleQueryOptions("x-admin")
    )
    if (!isXAdmin) throw notFound()
  },
  pendingComponent: PendingComponent,
  component: RouteComponent,
})

function PendingComponent() {
  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Users", url: "/core/users" },
          { title: "New user" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="mx-auto flex w-full max-w-lg flex-col gap-4 px-4 py-4">
            <Card>
              <CardHeader className="border-b">
                <Skeleton className="h-5 w-20" />
              </CardHeader>
              <CardContent className="space-y-4 py-4">
                <div className="space-y-1.5">
                  <Skeleton className="h-4 w-12" />
                  <Skeleton className="h-9 w-full" />
                </div>
                <div className="space-y-1.5">
                  <Skeleton className="h-4 w-20" />
                  <Skeleton className="h-9 w-full" />
                </div>
              </CardContent>
              <CardFooter className="justify-end gap-2">
                <Skeleton className="h-9 w-20" />
                <Skeleton className="h-9 w-16" />
              </CardFooter>
            </Card>
          </div>
        </div>
      </div>
    </>
  )
}

function RouteComponent() {
  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Users", url: "/core/users" },
          { title: "New user" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="mx-auto flex w-full max-w-lg flex-col gap-4 px-4 py-4">
            <UserCreateForm />
          </div>
        </div>
      </div>
    </>
  )
}
