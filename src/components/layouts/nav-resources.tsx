import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "#/components/ui/sidebar"
import { Skeleton } from "#/components/ui/skeleton"

import type { ResourceItem } from "./nav-resource-item"
import { ResourceMenuItem } from "./nav-resource-item"

export function NavResources({
  items,
  schema,
  isLoading,
}: {
  schema: string
  isLoading?: boolean
  items: ResourceItem[]
}) {
  const hasGroups = items.some((item) => item.meta?.collapsible_group)

  const grouped: Record<string, ResourceItem[]> = {}
  if (hasGroups) {
    for (const item of items) {
      const key = item.meta?.collapsible_group ?? ""
      grouped[key] = grouped[key] ?? []
      grouped[key].push(item)
    }
  }

  const skeletons = Array.from({ length: 4 }).map((_, i) => (
    <SidebarMenuItem key={i}>
      <SidebarMenuButton disabled>
        <Skeleton className="size-4 rounded" />
        <Skeleton className="h-3 w-24" />
      </SidebarMenuButton>
    </SidebarMenuItem>
  ))

  if (isLoading) {
    return (
      <SidebarGroup className="group-data-[collapsible=icon]:hidden">
        <SidebarGroupLabel>Resources</SidebarGroupLabel>
        <SidebarMenu className="flex flex-col gap-1">{skeletons}</SidebarMenu>
      </SidebarGroup>
    )
  }

  if (!hasGroups) {
    return (
      <SidebarGroup className="group-data-[collapsible=icon]:hidden">
        <SidebarGroupLabel>Resources</SidebarGroupLabel>
        <SidebarMenu className="flex flex-col gap-1">
          {items.map((item) => (
            <ResourceMenuItem key={item.id} item={item} schema={schema} />
          ))}
        </SidebarMenu>
      </SidebarGroup>
    )
  }

  const ungrouped = grouped[""] ?? []
  const namedGroups = Object.entries(grouped).filter(([key]) => key !== "")

  return (
    <>
      {ungrouped.length > 0 && (
        <SidebarGroup className="group-data-[collapsible=icon]:hidden">
          <SidebarGroupLabel>Resources</SidebarGroupLabel>
          <SidebarMenu className="flex flex-col gap-1">
            {ungrouped.map((item) => (
              <ResourceMenuItem key={item.id} item={item} schema={schema} />
            ))}
          </SidebarMenu>
        </SidebarGroup>
      )}
      {namedGroups.map(([group, groupItems]) => (
        <SidebarGroup
          key={group}
          className="group-data-[collapsible=icon]:hidden"
        >
          <SidebarGroupLabel>{group}</SidebarGroupLabel>
          <SidebarMenu className="flex flex-col gap-1">
            {groupItems.map((item) => (
              <ResourceMenuItem key={item.id} item={item} schema={schema} />
            ))}
          </SidebarMenu>
        </SidebarGroup>
      ))}
    </>
  )
}
