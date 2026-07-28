import { useLocation, useNavigate } from "@tanstack/react-router"

import {
  ChevronDownIcon,
  FileTextIcon,
  HistoryIcon,
  MessageSquareIcon,
} from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import { useHasPermission } from "#/hooks/use-permissions"
import type { DatabaseSchemas } from "#/lib/database-meta.types"

interface ResourceRecordMenuProps {
  schema: DatabaseSchemas
  resource: never
  resourceId: string
}

export function ResourceRecordMenu({
  schema,
  resource,
  resourceId,
}: ResourceRecordMenuProps) {
  const navigate = useNavigate()
  const location = useLocation()

  const canViewAudit = useHasPermission({
    schema: "supasheet",
    resource: "audit_logs",
    action: "select",
  })

  const params = { schema, resource, resourceId }

  const views = [
    {
      id: "detail",
      label: "Detail",
      icon: FileTextIcon,
      to: "/$schema/resource/$resource/$resourceId/detail" as const,
    },
    {
      id: "comment",
      label: "Comments",
      icon: MessageSquareIcon,
      to: "/$schema/resource/$resource/$resourceId/comment" as const,
    },
    ...(canViewAudit
      ? [
          {
            id: "audit",
            label: "Audit Log",
            icon: HistoryIcon,
            to: "/$schema/resource/$resource/$resourceId/audit" as const,
          },
        ]
      : []),
  ]

  const segments = location.pathname.split("/")
  const resourceIdIndex = segments.indexOf(resourceId)
  const activeSegment =
    resourceIdIndex >= 0 ? segments[resourceIdIndex + 1] : undefined
  const currentView =
    views.find((view) => view.id === activeSegment) ?? views[0]
  const CurrentIcon = currentView.icon

  function handleViewChange(value: string) {
    const view = views.find((v) => v.id === value)
    if (!view) return
    navigate({ to: view.to, params })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button size="sm" variant="outline" />}>
        <CurrentIcon className="size-3.5" />
        <span className="truncate font-medium">{currentView.label}</span>
        <ChevronDownIcon className="size-3.5 opacity-50" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-44">
        <DropdownMenuGroup>
          <DropdownMenuLabel>Record</DropdownMenuLabel>
        </DropdownMenuGroup>
        <DropdownMenuRadioGroup
          value={currentView.id}
          onValueChange={handleViewChange}
        >
          {views.map((view) => (
            <DropdownMenuRadioItem key={view.id} value={view.id}>
              <view.icon className="size-3.5" />
              {view.label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
