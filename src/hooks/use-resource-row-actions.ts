import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { evaluateConditionalField } from "#/components/resource/resource-form-utils"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import type { ResourceActionSchema } from "#/lib/supabase/data/resource"
import { runResourceActionMutationOptions } from "#/lib/supabase/data/resource"

function resolveActionParams(
  argumentsText: string,
  record: Record<string, unknown>
): Record<string, unknown> {
  const recordKeys = new Map(
    Object.keys(record).map((key) => [key.toLowerCase(), key])
  )

  const resolved: Record<string, unknown> = {}
  for (const part of argumentsText.split(",")) {
    const paramName = part.trim().split(" ")[0]
    if (!paramName) continue

    const columnName = paramName.startsWith("p_")
      ? paramName.slice(2)
      : paramName
    const matchedKey = recordKeys.get(columnName.toLowerCase())
    if (matchedKey === undefined) continue
    resolved[paramName] = record[matchedKey]
  }
  return resolved
}

export function useResourceRowActions({
  schema,
  resource,
  record,
  actions,
}: {
  schema: string
  resource: string
  record: Record<string, unknown>
  actions: ResourceActionSchema[]
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

  async function runAction(action: ResourceActionSchema) {
    try {
      await runResourceAction({
        schema: action.schema,
        functionName: action.function_name,
        params: resolveActionParams(action.arguments, record),
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

  const confirm = useConfirmAction<ResourceActionSchema>(runAction)

  function selectAction(action: ResourceActionSchema) {
    if (action.confirm) {
      confirm.request(action)
    } else {
      runAction(action)
    }
  }

  return { visibleActions, selectAction, confirm }
}
