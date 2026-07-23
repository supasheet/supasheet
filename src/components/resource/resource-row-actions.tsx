import { ChevronDownIcon, MoreHorizontalIcon } from "lucide-react"

import { ConfirmActionDialog } from "#/components/resource/confirm-action-dialog"
import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import { useResourceRowActions } from "#/hooks/use-resource-row-actions"
import type { ResourceActionSchema } from "#/lib/supabase/data/resource"

interface ResourceRowActionsProps {
  schema: string
  resource: string
  record: Record<string, unknown>
  actions: ResourceActionSchema[]
  variant?: "compact" | "menu"
}

export function ResourceRowActions({
  schema,
  resource,
  record,
  actions,
  variant = "compact",
}: ResourceRowActionsProps) {
  const { visibleActions, selectAction, confirm } = useResourceRowActions({
    schema,
    resource,
    record,
    actions,
  })

  if (visibleActions.length === 0) return null

  const singleAction =
    variant === "menu" && visibleActions.length === 1 ? visibleActions[0] : null

  return (
    <>
      {singleAction ? (
        <Button
          size="sm"
          variant={
            singleAction.variant === "destructive" ? "destructive" : "outline"
          }
          onClick={() => selectAction(singleAction)}
        >
          {singleAction.icon && <DynamicIcon iconName={singleAction.icon} />}
          {singleAction.name}
        </Button>
      ) : (
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              variant === "menu" ? (
                <Button size="sm" variant="outline">
                  Actions
                  <ChevronDownIcon className="ml-1.5 size-3.5" />
                </Button>
              ) : (
                <Button
                  variant="outline"
                  size="icon-xs"
                  className="opacity-0 transition-opacity group-hover:opacity-100"
                />
              )
            }
          >
            {variant === "compact" && <MoreHorizontalIcon />}
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-56">
            {visibleActions.map((action) => (
              <DropdownMenuItem
                key={action.function_name}
                variant={
                  action.variant === "destructive" ? "destructive" : "default"
                }
                onClick={() => selectAction(action)}
              >
                {action.icon && <DynamicIcon iconName={action.icon} />}
                {action.name}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      )}

      <ConfirmActionDialog
        open={confirm.open}
        onOpenChange={(open) => !open && confirm.cancel()}
        onConfirm={confirm.confirm}
        pending={confirm.pending}
        title={confirm.target?.confirm?.title ?? `${confirm.target?.name}?`}
        description={confirm.target?.confirm?.description}
        confirmLabel={confirm.target?.name ?? "Confirm"}
        destructive={confirm.target?.variant === "destructive"}
      />
    </>
  )
}
