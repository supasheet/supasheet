import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { evaluateConditionalField } from "#/components/resource/resource-form-utils"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import type { ColumnSchema } from "#/lib/database-meta.types"
import type { ResourceActionSchema } from "#/lib/supabase/data/resource"
import { runResourceActionMutationOptions } from "#/lib/supabase/data/resource"

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

type ConfirmTarget = { action: ResourceActionSchema; value?: string }

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
  actions: ResourceActionSchema[]
  columnsSchema?: ColumnSchema[]
}) {
  const queryClient = useQueryClient()
  const { mutateAsync: runResourceAction } = useMutation(
    runResourceActionMutationOptions()
  )

  const visibleActions = actions.filter(
    (action) =>
      !action.visible?.length ||
      evaluateConditionalField(action.visible, record)
  )

  function getPickerColumn(
    action: ResourceActionSchema
  ): ColumnSchema | undefined {
    if (action.action_type !== "picker") return undefined
    for (const paramName of argParamNames(action.arguments)) {
      const columnName = paramName.startsWith("p_")
        ? paramName.slice(2)
        : paramName
      const col = columnsSchema.find((c) => (c.name ?? c.id) === columnName)
      if (col && col.data_type === "USER-DEFINED") return col
    }
    return undefined
  }

  async function runAction(action: ResourceActionSchema, value?: string) {
    const pickerColumn =
      value !== undefined ? getPickerColumn(action) : undefined
    const paramsRecord = pickerColumn
      ? { ...record, [pickerColumn.name ?? pickerColumn.id]: value }
      : record
    try {
      await runResourceAction({
        schema: action.schema,
        functionName: action.function_name,
        params: resolveActionParams(action.arguments, paramsRecord),
      })
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(action.success_message ?? `${action.name} succeeded`)
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : `Failed to run ${action.name}`
      )
    }
  }

  const confirm = useConfirmAction<ConfirmTarget>(({ action, value }) =>
    runAction(action, value)
  )

  function selectAction(action: ResourceActionSchema, value?: string) {
    if (action.confirm) {
      confirm.request({ action, value })
    } else {
      runAction(action, value)
    }
  }

  return { visibleActions, selectAction, confirm, getPickerColumn }
}
