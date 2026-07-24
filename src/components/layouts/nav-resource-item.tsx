import { Link, useLocation, useNavigate } from "@tanstack/react-router"

import * as LucideIcons from "lucide-react"
import type { LucideIcon } from "lucide-react"
import {
  FileTextIcon,
  ListIcon,
  MoreHorizontalIcon,
  PlusIcon,
  Table2Icon,
} from "lucide-react"

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import {
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "#/components/ui/sidebar"
import { useHasPermission } from "#/hooks/use-permissions"
import type { TableMetadata, ViewMetadata } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"

export type ResourceItem =
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

export function LucideIconComponent({
  iconName,
}: {
  iconName: keyof typeof LucideIcons
}) {
  const Icon = (LucideIcons[iconName] as LucideIcon | undefined) ?? Table2Icon

  return <Icon className="size-4 shrink-0" />
}

export function useResourceMenuAction(item: ResourceItem, schema: string) {
  const canInsert = useHasPermission(`${item.schema}.${item.id}:insert`)
  const showInsert = canInsert && item.type === "table"
  const url = `/${schema}/${item.id}`
  const newUrl = `/${schema}/${item.id}/new`
  const definitionUrl = `/${schema}/${item.id}/definition`

  return { showInsert, url, newUrl, definitionUrl }
}

export function ResourceMenuItem({
  item,
  schema,
}: {
  item: ResourceItem
  schema: string
}) {
  const location = useLocation()
  const navigate = useNavigate()
  const { isMobile } = useSidebar()
  const { showInsert, url, newUrl, definitionUrl } = useResourceMenuAction(
    item,
    schema
  )

  const icon = (
    <LucideIconComponent
      iconName={item.meta?.icon || (item.type === "table" ? "Table2" : "Eye")}
    />
  )

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
