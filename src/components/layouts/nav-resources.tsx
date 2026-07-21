import { Link, useLocation, useNavigate } from "@tanstack/react-router"

import * as LucideIcons from "lucide-react"
import type { LucideIcon } from "lucide-react"
import {
  FileTextIcon,
  ListIcon,
  MoreHorizontalIcon,
  PlusIcon,
} from "lucide-react"

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "#/components/ui/sidebar"
import { Skeleton } from "#/components/ui/skeleton"
import { useHasPermission } from "#/hooks/use-permissions"
import type { TableMetadata, ViewMetadata } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"

function LucideIconComponent({
  iconName,
}: {
  iconName: keyof typeof LucideIcons
}) {
  const Icon = LucideIcons[iconName] as LucideIcon

  return <Icon className="size-4 shrink-0" />
}

type ResourceItem =
  | {
      name: string
      id: string
      schema: string
      type: "table"
      meta: TableMetadata
    }
  | {
      name: string
      id: string
      schema: string
      type: "view"
      meta: ViewMetadata
    }

function ResourceMenuItem({
  item,
  schema,
}: {
  item: ResourceItem
  schema: string
}) {
  const location = useLocation()
  const navigate = useNavigate()
  const { isMobile } = useSidebar()

  const canInsert = useHasPermission(`${item.schema}.${item.id}:insert`)
  const showInsert = canInsert && item.type === "table"

  const icon = (
    <LucideIconComponent
      iconName={item.meta?.icon || (item.type === "table" ? "Table2" : "Eye")}
    />
  )
  const url = `/${schema}/${item.id}`
  const newUrl = `/${schema}/${item.id}/new`
  const definitionUrl = `/${schema}/${item.id}/definition`

  return (
    <SidebarMenuItem key={item.name}>
      <SidebarMenuButton
        tooltip={item.meta?.name ?? formatTitle(item.name)}
        render={<Link to={url as never} />}
        isActive={location.pathname.startsWith(`/${schema}/${item.id}/`)}
      >
        {icon}
        <span>{item.meta?.name ?? formatTitle(item.name)}</span>
      </SidebarMenuButton>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <SidebarMenuAction showOnHover aria-label="More">
              <MoreHorizontalIcon />
            </SidebarMenuAction>
          }
        />
        <DropdownMenuContent
          className="w-48"
          side={isMobile ? "bottom" : "right"}
          align={isMobile ? "end" : "start"}
        >
          {showInsert && (
            <>
              <DropdownMenuItem
                onClick={() => navigate({ to: newUrl as never })}
              >
                <PlusIcon className="text-muted-foreground" />
                <span>New record</span>
              </DropdownMenuItem>
              <DropdownMenuSeparator />
            </>
          )}
          <DropdownMenuItem
            onClick={() => navigate({ to: definitionUrl as never })}
          >
            <FileTextIcon className="text-muted-foreground" />
            <span>Definition</span>
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => navigate({ to: url as never })}>
            <ListIcon className="text-muted-foreground" />
            <span>View records</span>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </SidebarMenuItem>
  )
}

export function NavResources({
  items,
  schema,
  isLoading,
}: {
  schema: string
  isLoading?: boolean
  items: ResourceItem[]
}) {
  const hasGroups = items.some((item) => item.meta?.group)

  const grouped: Record<string, ResourceItem[]> = {}
  if (hasGroups) {
    for (const item of items) {
      const key = item.meta?.group ?? ""
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
