import { ChevronDownIcon, MoreHorizontalIcon } from "lucide-react"

import { ConfirmActionDialog } from "#/components/resource/confirm-action-dialog"
import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import {
  getActionMeta,
  useResourceRowActions,
} from "#/hooks/use-resource-row-actions"
import type {
  ColumnSchema,
  EnumColumnMetadata,
  IconName,
} from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import type { ResourceActionRow } from "#/lib/supabase/data/resource"

interface ResourceRowActionsProps {
  schema: string
  resource: string
  record: Record<string, unknown>
  actions: ResourceActionRow[]
  columnsSchema?: ColumnSchema[]
  variant?: "compact" | "menu"
}

type EnumOption = { value: string; label: string; icon?: IconName }

function getEnumOptions(col: ColumnSchema | undefined): EnumOption[] {
  if (!col) return []

  let enumsMeta: EnumColumnMetadata["enums"] | undefined
  try {
    enumsMeta = col.comment
      ? (JSON.parse(col.comment) as EnumColumnMetadata).enums
      : undefined
  } catch {
    enumsMeta = undefined
  }

  if (enumsMeta) {
    return Object.entries(enumsMeta).map(([value, meta]) => ({
      value,
      label: formatTitle(value),
      icon: meta.icon,
    }))
  }

  return ((col.enums as string[] | null) ?? []).map((value) => ({
    value,
    label: formatTitle(value),
  }))
}

export function ResourceRowActions({
  schema,
  resource,
  record,
  actions,
  columnsSchema = [],
  variant = "compact",
}: ResourceRowActionsProps) {
  const { visibleActions, selectAction, confirm, getPickerColumn } =
    useResourceRowActions({
      schema,
      resource,
      record,
      actions,
      columnsSchema,
    })

  if (visibleActions.length === 0) return null

  const singleAction =
    variant === "menu" &&
    visibleActions.length === 1 &&
    getActionMeta(visibleActions[0]).action_type !== "picker"
      ? visibleActions[0]
      : null
  const singleActionMeta = singleAction ? getActionMeta(singleAction) : null

  const confirmMeta = confirm.target
    ? getActionMeta(confirm.target.action)
    : null

  return (
    <>
      {singleAction && singleActionMeta ? (
        <Button
          size="sm"
          variant={
            singleActionMeta.variant === "destructive"
              ? "destructive"
              : "outline"
          }
          onClick={() => selectAction(singleAction)}
        >
          {singleActionMeta.icon && (
            <DynamicIcon iconName={singleActionMeta.icon} />
          )}
          {singleActionMeta.name}
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
            {visibleActions.map((action) => {
              const meta = getActionMeta(action)

              if (meta.action_type === "picker") {
                const col = getPickerColumn(action)
                const options = getEnumOptions(col)
                const columnName = col?.name ?? col?.id
                const currentValue = columnName ? record[columnName] : null

                return (
                  <DropdownMenuSub key={action.name}>
                    <DropdownMenuSubTrigger>
                      {meta.icon && <DynamicIcon iconName={meta.icon} />}
                      {meta.name}
                    </DropdownMenuSubTrigger>
                    <DropdownMenuSubContent>
                      <DropdownMenuRadioGroup
                        value={currentValue != null ? String(currentValue) : ""}
                        onValueChange={(value) => selectAction(action, value)}
                      >
                        {options.map((option) => (
                          <DropdownMenuRadioItem
                            key={option.value}
                            value={option.value}
                          >
                            {option.icon && (
                              <DynamicIcon iconName={option.icon} />
                            )}
                            {option.label}
                          </DropdownMenuRadioItem>
                        ))}
                      </DropdownMenuRadioGroup>
                    </DropdownMenuSubContent>
                  </DropdownMenuSub>
                )
              }

              return (
                <DropdownMenuItem
                  key={action.name}
                  variant={
                    meta.variant === "destructive" ? "destructive" : "default"
                  }
                  onClick={() => selectAction(action)}
                >
                  {meta.icon && <DynamicIcon iconName={meta.icon} />}
                  {meta.name}
                </DropdownMenuItem>
              )
            })}
          </DropdownMenuContent>
        </DropdownMenu>
      )}

      <ConfirmActionDialog
        open={confirm.open}
        onOpenChange={(open) => !open && confirm.cancel()}
        onConfirm={confirm.confirm}
        pending={confirm.pending}
        title={confirmMeta?.confirm?.title ?? `${confirmMeta?.name}?`}
        description={confirmMeta?.confirm?.description}
        confirmLabel={confirmMeta?.name ?? "Confirm"}
        destructive={confirmMeta?.variant === "destructive"}
      />
    </>
  )
}
