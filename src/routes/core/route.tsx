import { Outlet, createFileRoute } from "@tanstack/react-router"

import { DatabaseIcon, FolderIcon } from "lucide-react"

import { ModuleSwitcher } from "#/components/layouts/module-switcher"
import { NavMain } from "#/components/layouts/nav-main"
import { NavResources } from "#/components/layouts/nav-resources"
import { NavSecondary } from "#/components/layouts/nav-secondary"
import { NavUser } from "#/components/layouts/nav-user"
import { QuickSearch } from "#/components/layouts/quick-search"
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
import type { TableMetadata } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { userPermissionsQueryOptions } from "#/lib/supabase/data/core"
import { schemasQueryOptions } from "#/lib/supabase/data/resource"

const CORE_RESOURCES = [
  {
    name: "users",
    id: "users",
    schema: "supasheet",
    type: "table" as const,
    meta: { icon: "UserIcon" } as TableMetadata,
  },
  {
    name: "user_roles",
    id: "user_roles",
    schema: "supasheet",
    type: "table" as const,
    meta: { icon: "UserCheckIcon" } as TableMetadata,
  },
  {
    name: "role_permissions",
    id: "role_permissions",
    schema: "supasheet",
    type: "table" as const,
    meta: { icon: "ShieldCheckIcon" } as TableMetadata,
  },
  {
    name: "audit_logs",
    id: "audit_logs",
    schema: "supasheet",
    type: "table" as const,
    meta: { icon: "ScrollTextIcon" } as TableMetadata,
  },
]

export const Route = createFileRoute("/core")({
  beforeLoad: async ({ context }) => {
    const permissions = context.authUser
      ? await context.queryClient.ensureQueryData(
          userPermissionsQueryOptions("supasheet")
        )
      : null
    return { permissions }
  },
  loader: async ({ context }) => {
    const schemas =
      await context.queryClient.ensureQueryData(schemasQueryOptions)
    return { schemas }
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { schemas } = Route.useLoaderData()
  const resources = CORE_RESOURCES
  const modules = schemas.map((s) => ({
    name: formatTitle(s.schema),
    icon: <DatabaseIcon />,
    url: `/${s.schema}`,
  }))

  return (
    <SidebarProvider
      style={
        {
          "--sidebar-width": "calc(var(--spacing) * 72)",
          "--header-height": "calc(var(--spacing) * 12)",
        } as React.CSSProperties
      }
    >
      <Sidebar collapsible="offcanvas" variant="inset">
        <SidebarHeader>
          <div className="flex items-center gap-1">
            <div className="min-w-0 flex-1">
              <ModuleSwitcher modules={modules} />
            </div>
          </div>
        </SidebarHeader>
        <SidebarContent>
          <NavMain schema="core" items={[]} />
          <NavResources schema="core" items={resources} />
        </SidebarContent>
        <SidebarFooter>
          <SidebarGroup>
            <SidebarGroupContent>
              <QuickSearch
                schema="core"
                items={[]}
                resourceItems={resources.map((r) => ({
                  ...r,
                  url: `/core/${r.id}`,
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
      <SidebarInset>
        <Outlet />
      </SidebarInset>
    </SidebarProvider>
  )
}
