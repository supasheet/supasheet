import { Outlet, createFileRoute } from "@tanstack/react-router"

import { useQuery } from "@tanstack/react-query"

import { ArrowLeftIcon, FolderIcon } from "lucide-react"

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
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
} from "#/components/ui/sidebar"
import { Skeleton } from "#/components/ui/skeleton"
import { storageBucketsQueryOptions } from "#/lib/supabase/data/storage"

export const Route = createFileRoute("/storage")({
  loader: async ({ context }) => {
    context.queryClient.prefetchQuery(storageBucketsQueryOptions)
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { data: buckets = [], isLoading } = useQuery(storageBucketsQueryOptions)

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
            <SidebarMenuButton className="min-w-0 flex-1 px-2">
              <div className="flex aspect-square size-5 items-center justify-center rounded bg-primary text-primary-foreground">
                <FolderIcon className="size-4" />
              </div>
              <span className="truncate font-medium">Storage</span>
            </SidebarMenuButton>
          </div>
        </SidebarHeader>
        <SidebarContent>
          <NavMain schema="storage" items={[]} />
          {isLoading ? (
            <SidebarGroup className="group-data-[collapsible=icon]:hidden">
              <SidebarGroupLabel>
                <Skeleton className="h-3 w-16" />
              </SidebarGroupLabel>
              <SidebarMenu className="flex flex-col gap-1">
                {Array.from({ length: 4 }).map((_, i) => (
                  <SidebarMenuItem key={i}>
                    <SidebarMenuButton>
                      <Skeleton className="size-4 shrink-0 rounded" />
                      <Skeleton className="h-3 flex-1 rounded" />
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            </SidebarGroup>
          ) : (
            <NavResources schema="storage" items={buckets} />
          )}
        </SidebarContent>
        <SidebarFooter>
          <SidebarGroup>
            <SidebarGroupContent>
              <QuickSearch
                schema="storage"
                items={[]}
                resourceItems={buckets.map((b) => ({
                  ...b,
                  url: `/storage/${b.id}`,
                }))}
              />
              <NavSecondary
                items={[
                  { title: "Back to Main", url: "/", icon: <ArrowLeftIcon /> },
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
