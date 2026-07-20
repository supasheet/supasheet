import {
  Link,
  Outlet,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { useQuery } from "@tanstack/react-query"

import {
  AlertCircleIcon,
  ChartBarIcon,
  DatabaseIcon,
  FileChartColumnIcon,
  FileXIcon,
  FolderIcon,
  LayoutDashboardIcon,
  LayoutTemplateIcon,
} from "lucide-react"
import { z } from "zod"

import { ModuleSwitcher } from "#/components/layouts/module-switcher"
import { NavMain } from "#/components/layouts/nav-main"
import { NavResources } from "#/components/layouts/nav-resources"
import { NavSecondary } from "#/components/layouts/nav-secondary"
import { NavUser } from "#/components/layouts/nav-user"
import { QuickSearch } from "#/components/layouts/quick-search"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarInset,
  SidebarProvider,
} from "#/components/ui/sidebar"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { userPermissionsQueryOptions } from "#/lib/supabase/data/core"
import {
  navItemsQueryOptions,
  resourcesQueryOptions,
  schemasQueryOptions,
} from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/$schema")({
  params: z.object({
    schema: z.string<DatabaseSchemas>(),
  }),
  beforeLoad: async ({ context, params }) => {
    const permissions = context.authUser
      ? await context.queryClient.ensureQueryData(
          userPermissionsQueryOptions(params.schema)
        )
      : null
    if (context.authUser && !permissions?.length) throw notFound()
    return { permissions }
  },
  loader: async ({ context, params }) => {
    context.queryClient.prefetchQuery(schemasQueryOptions)
    context.queryClient.prefetchQuery(resourcesQueryOptions(params.schema))
    context.queryClient.prefetchQuery(navItemsQueryOptions(params.schema))
  },
  component: RouteComponent,
  errorComponent: ({ error }: ErrorComponentProps) => {
    const router = useRouter()
    return (
      <div className="flex flex-1 items-center justify-center p-8">
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <AlertCircleIcon />
            </EmptyMedia>
            <EmptyTitle>Something went wrong</EmptyTitle>
            <EmptyDescription>
              {error?.message ?? "An unexpected error occurred."}
            </EmptyDescription>
          </EmptyHeader>
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => router.navigate({ to: "/" })}
            >
              Go Home
            </Button>
          </div>
        </Empty>
      </div>
    )
  },
  notFoundComponent: () => (
    <div className="flex flex-1 items-center justify-center p-8">
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <FileXIcon />
          </EmptyMedia>
          <EmptyTitle>Page not found</EmptyTitle>
          <EmptyDescription>
            This page doesn't exist. <Link to="/">Go home</Link>
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    </div>
  ),
})

const NAV_TYPE_ORDER = ["dashboard_widget", "chart", "report", "template"]

const NAV_TYPE_CONFIG: Record<
  string,
  { title: string; url: string; icon: React.ReactNode }
> = {
  dashboard_widget: {
    title: "Dashboard",
    url: "/dashboard",
    icon: <LayoutDashboardIcon />,
  },
  chart: { title: "Chart", url: "/chart", icon: <ChartBarIcon /> },
  report: { title: "Report", url: "/report", icon: <FileChartColumnIcon /> },
  template: {
    title: "Template",
    url: "/template",
    icon: <LayoutTemplateIcon />,
  },
}

function RouteComponent() {
  const params = Route.useParams()
  const { authUser } = Route.useRouteContext()
  const { data: schemas = [], isLoading: schemasLoading } = useQuery({
    ...schemasQueryOptions,
    enabled: !!authUser,
  })
  const modules = schemas.map((s) => ({
    name: formatTitle(s.schema),
    icon: <DatabaseIcon />,
    url: `/${s.schema}`,
  }))
  const { data: resources = [], isLoading: resourcesLoading } = useQuery({
    ...resourcesQueryOptions(params.schema),
    enabled: !!authUser,
  })
  const { data: navItemGroups = [] } = useQuery({
    ...navItemsQueryOptions(params.schema),
    enabled: !!authUser,
  })
  const activeTypes = new Set(
    navItemGroups.filter((g) => g.count > 0).map((g) => g.type)
  )
  const navMain = NAV_TYPE_ORDER.filter((type) => activeTypes.has(type)).map(
    (type) => ({
      title: NAV_TYPE_CONFIG[type].title,
      url: NAV_TYPE_CONFIG[type].url,
      icon: NAV_TYPE_CONFIG[type].icon,
    })
  )
  return (
    <SidebarProvider
      style={
        {
          "--sidebar-width": "calc(var(--spacing) * 72)",
          "--header-height": "calc(var(--spacing) * 12)",
        } as React.CSSProperties
      }
      className="h-svh overflow-hidden"
    >
      {authUser && (
        <Sidebar collapsible="offcanvas" variant="inset">
          <SidebarHeader>
            <div className="flex items-center gap-1">
              <div className="min-w-0 flex-1">
                <ModuleSwitcher modules={modules} isLoading={schemasLoading} />
              </div>
            </div>
          </SidebarHeader>
          <SidebarContent>
            <NavMain schema={params.schema} items={navMain} />
            <NavResources
              schema={params.schema + "/resource"}
              items={resources}
              isLoading={resourcesLoading}
            />
          </SidebarContent>
          <SidebarFooter>
            <SidebarGroup>
              <SidebarGroupContent>
                <QuickSearch
                  schema={params.schema}
                  items={navMain}
                  resourceItems={resources.map((r) => ({
                    ...r,
                    url: `/${params.schema}/resource/${r.id}`,
                  }))}
                />
                <NavSecondary
                  items={[
                    { title: "Storage", url: "/storage", icon: <FolderIcon /> },
                  ]}
                />
              </SidebarGroupContent>
            </SidebarGroup>
            <NavUser />
          </SidebarFooter>
        </Sidebar>
      )}
      <SidebarInset className="overflow-hidden">
        <div className="flex flex-1 flex-col overflow-auto">
          <Outlet />
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
