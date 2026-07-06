import {
  Outlet,
  createFileRoute,
  notFound,
  useLocation,
  useNavigate,
} from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { DefaultHeader } from "#/components/layouts/default-header"
import { Card, CardContent, CardHeader } from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import { Tabs, TabsList, TabsTrigger } from "#/components/ui/tabs"
import { useHasPermission } from "#/hooks/use-permissions"
import { useAuthUser } from "#/hooks/use-user"
import { pageTitle } from "#/lib/page-title"
import { adminGetUserQueryOptions } from "#/lib/supabase/data/admin-auth"

export const Route = createFileRoute("/core/users/$userId")({
  beforeLoad: ({ context }) => {
    if (
      !context.permissions?.some(
        (p) => p.permission === "supasheet.users:select_all"
      )
    )
      throw notFound()
  },
  loader: async ({ context, params: { userId } }) => {
    const data = await context.queryClient.ensureQueryData(
      adminGetUserQueryOptions(userId)
    )
    if (!data?.user) throw notFound()
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`${params.userId} | Users`) }],
  }),
  pendingComponent: () => (
    <>
      <DefaultHeader
        breadcrumbs={[{ title: "Users", url: "/core/users" }, { title: "…" }]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col">
          <div className="mx-auto px-4 pt-4">
            <div className="flex gap-2">
              <Skeleton className="h-9 w-[5.5rem] rounded-md" />
              <Skeleton className="h-9 w-12 rounded-md" />
              <Skeleton className="h-9 w-[4.5rem] rounded-md" />
              <Skeleton className="h-9 w-28 rounded-md" />
            </div>
          </div>
          <div className="mx-auto flex w-full max-w-2xl flex-col gap-4 px-4 py-4">
            <Card>
              <CardHeader className="border-b">
                <Skeleton className="h-6 w-36" />
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
        </div>
      </div>
    </>
  ),
  component: RouteComponent,
})

function RouteComponent() {
  const { userId } = Route.useParams()
  const navigate = useNavigate()
  const { data } = useSuspenseQuery(adminGetUserQueryOptions(userId))

  const authUser = useAuthUser()
  const isSelf = authUser?.id === userId

  const canUpdate = useHasPermission("supasheet.users:update")
  const canBan = useHasPermission("supasheet.users:ban")
  const canGenerateLink = useHasPermission("supasheet.users:generate_link")
  const canDelete = useHasPermission("supasheet.users:delete")

  const { pathname } = useLocation()
  const activeTab = pathname.endsWith("/edit")
    ? "edit"
    : pathname.endsWith("/security")
      ? "security"
      : pathname.endsWith("/danger")
        ? "danger"
        : "overview"

  function handleTabChange(value: string | null) {
    const params = { userId }
    if (value === "edit") navigate({ to: "/core/users/$userId/edit", params })
    else if (value === "security")
      navigate({ to: "/core/users/$userId/security", params })
    else if (value === "danger")
      navigate({ to: "/core/users/$userId/danger", params })
    else navigate({ to: "/core/users/$userId", params })
  }

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Users", url: "/core/users" },
          { title: data.user.email ?? userId },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col">
          <div className="mx-auto px-4 pt-4">
            <Tabs value={activeTab} onValueChange={handleTabChange}>
              <TabsList variant="line">
                <TabsTrigger value="overview">Overview</TabsTrigger>
                <TabsTrigger value="edit" disabled={isSelf || !canUpdate}>
                  Edit
                </TabsTrigger>
                <TabsTrigger
                  value="security"
                  disabled={isSelf || (!canBan && !canGenerateLink)}
                >
                  Security
                </TabsTrigger>
                <TabsTrigger value="danger" disabled={isSelf || !canDelete}>
                  Danger Zone
                </TabsTrigger>
              </TabsList>
            </Tabs>
          </div>
          <Outlet />
        </div>
      </div>
    </>
  )
}
