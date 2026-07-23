import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { evaluateConditionalField } from "#/components/resource/resource-form-utils"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import type { ColumnSchema, RowActionMeta } from "#/lib/database-meta.types"
import type { ResourceActionRow } from "#/lib/supabase/data/resource"
import { runResourceActionMutationOptions } from "#/lib/supabase/data/resource"

export function getActionMeta(action: ResourceActionRow): RowActionMeta {
  return (action.comment ? JSON.parse(action.comment) : {}) as RowActionMeta
}

function argParamNames(argumentsText: string): string[] {
  return argumentsText
    .split(",")
    .map((part) => part.trim().split(" ")[0])
    .filter((name): name is string => !!name)
}

function resolveActionParams(
  argumentsText: string,
  record: Record<string, unknown>
): Record<string, unknown> {
  const recordKeys = new Map(
    Object.keys(record).map((key) => [key.toLowerCase(), key])
  )

  const resolved: Record<string, unknown> = {}
  for (const paramName of argParamNames(argumentsText)) {
    const columnName = paramName.startsWith("p_")
      ? paramName.slice(2)
      : paramName
    const matchedKey = recordKeys.get(columnName.toLowerCase())
    if (matchedKey === undefined) continue
    resolved[paramName] = record[matchedKey]
  }
  return resolved
}

type ConfirmTarget = { action: ResourceActionRow; value?: string }

export function useResourceRowActions({
  schema,
  resource,
  record,
  actions,
  columnsSchema = [],
}: {
  schema: string
  resource: string
  record: Record<string, unknown>
  actions: ResourceActionRow[]
  columnsSchema?: ColumnSchema[]
}) {
  const queryClient = useQueryClient()
  const { mutateAsync: runResourceAction } = useMutation(
    runResourceActionMutationOptions()
  )

  const visibleActions = actions.filter((action) => {
    const visible = getActionMeta(action).visible
    return !visible?.length || evaluateConditionalField(visible, record)
  })

  function getPickerColumn(
    action: ResourceActionRow
  ): ColumnSchema | undefined {
    if (getActionMeta(action).action_type !== "picker") return undefined
    for (const paramName of argParamNames(action.arguments)) {
      const columnName = paramName.startsWith("p_")
        ? paramName.slice(2)
        : paramName
      const col = columnsSchema.find((c) => (c.name ?? c.id) === columnName)
      if (col && col.data_type === "USER-DEFINED") return col
    }
    return undefined
  }

  async function runAction(action: ResourceActionRow, value?: string) {
    const meta = getActionMeta(action)
    const pickerColumn =
      value !== undefined ? getPickerColumn(action) : undefined
    const paramsRecord = pickerColumn
      ? { ...record, [pickerColumn.name ?? pickerColumn.id]: value }
      : record
    try {
      await runResourceAction({
        schema: action.schema,
        functionName: action.name,
        params: resolveActionParams(action.arguments, paramsRecord),
      })
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(meta.success_message ?? `${meta.name} succeeded`)
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : `Failed to run ${meta.name}`
      )
    }
  }

  const confirm = useConfirmAction<ConfirmTarget>(({ action, value }) =>
    runAction(action, value)
  )

  function selectAction(action: ResourceActionRow, value?: string) {
    if (getActionMeta(action).confirm) {
      confirm.request({ action, value })
    } else {
      runAction(action, value)
    }
  }

  return { visibleActions, selectAction, confirm, getPickerColumn }
}
