import { Link, useLocation, useNavigate } from "@tanstack/react-router"

import {
  ChevronRightIcon,
  FileTextIcon,
  ListIcon,
  MoreHorizontalIcon,
  PlusIcon,
} from "lucide-react"

import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "#/components/ui/collapsible"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import {
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
  useSidebar,
} from "#/components/ui/sidebar"
import { formatTitle } from "#/lib/format"

import type { ResourceItem } from "./nav-resource-item"
import { LucideIconComponent, useResourceMenuAction } from "./nav-resource-item"

function ResourceMenuSubItem({
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
    <SidebarMenuSubItem key={item.name} className="group/menu-sub-item">
      <SidebarMenuSubButton
        render={<Link to={url as never} />}
        isActive={location.pathname.startsWith(`/${schema}/${item.id}/`)}
      >
        {icon}
        <span>{item.meta?.name ?? formatTitle(item.name)}</span>
      </SidebarMenuSubButton>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <button
              aria-label="More"
              className="absolute top-1 right-1 flex aspect-square w-5 items-center justify-center rounded-md p-0 text-sidebar-foreground opacity-0 outline-hidden ring-sidebar-ring transition-transform group-focus-within/menu-sub-item:opacity-100 group-hover/menu-sub-item:opacity-100 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground focus-visible:ring-2 [&>svg]:size-4 [&>svg]:shrink-0"
            >
              <MoreHorizontalIcon />
            </button>
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
    </SidebarMenuSubItem>
  )
}

export function ResourceGroupMenuItem({
  group,
  items,
  schema,
}: {
  group: string
  items: ResourceItem[]
  schema: string
}) {
  const location = useLocation()
  const isGroupActive = items.some((item) =>
    location.pathname.startsWith(`/${schema}/${item.id}/`)
  )
  const groupIcon = items[0]?.meta?.icon

  return (
    <Collapsible key={group} defaultOpen={isGroupActive}>
      <SidebarMenuItem>
        <CollapsibleTrigger
          render={
            <SidebarMenuButton tooltip={group} className="group/collapsible">
              {groupIcon && <LucideIconComponent iconName={groupIcon} />}
              <span>{group}</span>
              <ChevronRightIcon className="ml-auto transition-transform duration-200 group-data-[panel-open]/collapsible:rotate-90" />
            </SidebarMenuButton>
          }
        />
        <CollapsibleContent>
          <SidebarMenuSub>
            {items.map((item) => (
              <ResourceMenuSubItem key={item.id} item={item} schema={schema} />
            ))}
          </SidebarMenuSub>
        </CollapsibleContent>
      </SidebarMenuItem>
    </Collapsible>
  )
}
