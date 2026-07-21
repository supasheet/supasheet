import { useNavigate } from "@tanstack/react-router"

import { ChevronDownIcon, HistoryIcon, MessageSquareIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import { useHasPermission } from "#/hooks/use-permissions"
import type { DatabaseSchemas } from "#/lib/database-meta.types"

interface ResourceRecordActionsProps {
  schema: DatabaseSchemas
  resource: never
  resourceId: string
}

export function ResourceRecordActions({
  schema,
  resource,
  resourceId,
}: ResourceRecordActionsProps) {
  const navigate = useNavigate()

  const canViewAudit = useHasPermission("supasheet.audit_logs:select")

  const params = { schema, resource, resourceId }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button size="sm" variant="outline">
            Actions
            <ChevronDownIcon className="ml-1.5 size-3.5" />
          </Button>
        }
      />
      <DropdownMenuContent align="end" className="w-44">
        <DropdownMenuGroup>
          <DropdownMenuItem
            onClick={() =>
              navigate({
                to: "/$schema/resource/$resource/$resourceId/comment",
                params,
              })
            }
          >
            <MessageSquareIcon />
            Comments
          </DropdownMenuItem>
          {canViewAudit && (
            <DropdownMenuItem
              onClick={() =>
                navigate({
                  to: "/$schema/resource/$resource/$resourceId/audit",
                  params,
                })
              }
            >
              <HistoryIcon />
              Audit Log
            </DropdownMenuItem>
          )}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
