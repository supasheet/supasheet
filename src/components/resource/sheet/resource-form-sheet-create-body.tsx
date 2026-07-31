import { useSuspenseQuery } from "@tanstack/react-query"

import {
  columnsSchemaQueryOptions,
  tableSchemaQueryOptions,
} from "#/lib/supabase/data/meta"

import { ResourceFormSheetContent } from "./resource-form-sheet-content"

export function ResourceFormSheetCreateBody({
  schema,
  resource,
  defaults,
  quick,
  onClose,
}: {
  schema: string
  resource: string
  defaults?: Record<string, string>
  quick?: boolean
  onClose: () => void
}) {
  const { data: tableSchema } = useSuspenseQuery(
    tableSchemaQueryOptions(schema as never, resource as never)
  )
  const { data: columnsSchema } = useSuspenseQuery(
    columnsSchemaQueryOptions(schema as never, resource as never)
  )

  if (!tableSchema || !columnsSchema?.length) {
    return (
      <div className="flex flex-1 items-center justify-center p-4 text-sm text-muted-foreground">
        Schema unavailable.
      </div>
    )
  }

  return (
    <ResourceFormSheetContent
      mode="create"
      tableSchema={tableSchema}
      columnsSchema={columnsSchema}
      record={null}
      defaults={defaults}
      quick={quick}
      onClose={onClose}
    />
  )
}
