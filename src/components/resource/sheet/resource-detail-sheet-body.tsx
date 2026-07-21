import { useSuspenseQuery } from "@tanstack/react-query"

import { Editor } from "#/components/editor/editor-md"
import { AllCells } from "#/components/resource/cells/all-cells"
import { ResourceAvatarDisplay } from "#/components/resource/detail/resource-avatar-display"
import { ResourceFileDisplay } from "#/components/resource/detail/resource-file-display"
import { Label } from "#/components/ui/label"
import { Separator } from "#/components/ui/separator"
import { useHasPermission } from "#/hooks/use-permissions"
import { getColumnMetadata } from "#/lib/columns"
import type { ResourceSchema } from "#/lib/database-meta.types"
import { getMetaFields } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import {
  columnsSchemaQueryOptions,
  singleResourceDataQueryOptions,
  tableSchemaQueryOptions,
} from "#/lib/supabase/data/resource"
import type { FileObject } from "#/types/fields"

import { ResourceFormSheetContent } from "./resource-form-sheet-content"

export function ResourceDetailSheetBody({
  schema,
  resource,
  pk,
  onClose,
}: {
  schema: string
  resource: string
  pk: Record<string, unknown>
  onClose: () => void
}) {
  const { data: tableSchema } = useSuspenseQuery(
    tableSchemaQueryOptions(schema as never, resource as never)
  )
  const { data: columnsSchema } = useSuspenseQuery(
    columnsSchemaQueryOptions(schema as never, resource as never)
  )
  const { data: record } = useSuspenseQuery(
    singleResourceDataQueryOptions(schema as never, resource as never, pk)
  )

  const canUpdate = useHasPermission(`${schema}.${resource}:update`)

  if (!tableSchema || !columnsSchema?.length || !record) {
    return (
      <div className="flex flex-1 items-center justify-center p-4 text-sm text-muted-foreground">
        Record unavailable.
      </div>
    )
  }

  const primaryKeys = tableSchema.primary_keys ?? []
  const canEdit = primaryKeys.length > 0 && canUpdate

  if (canEdit) {
    return (
      <ResourceFormSheetContent
        mode="update"
        tableSchema={tableSchema}
        columnsSchema={columnsSchema}
        record={record}
        onClose={onClose}
      />
    )
  }

  const detailColumns = columnsSchema.filter(
    (col) =>
      !getMetaFields(tableSchema as ResourceSchema | null).includes(col.name)
  )

  return (
    <div className="flex-1 overflow-y-auto p-4">
      {detailColumns.map((column, index) => {
        const value = record[column.name]
        const columnMetadata = getColumnMetadata(tableSchema, column)

        return (
          <div key={column.id}>
            <div className="flex items-start gap-4">
              <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                <Label className="inline-flex items-center gap-1.5 text-sm font-medium">
                  {columnMetadata.icon} {formatTitle(columnMetadata.name)}
                </Label>
                <div className="text-sm text-muted-foreground">
                  {value ? (
                    columnMetadata.variant === "rich_text" ? (
                      <Editor
                        name={columnMetadata.name}
                        value={value as string}
                        disabled
                      />
                    ) : columnMetadata.variant === "file" ? (
                      <ResourceFileDisplay value={value as FileObject[]} />
                    ) : columnMetadata.variant === "avatar" ? (
                      <ResourceAvatarDisplay
                        value={(value as FileObject | null) ?? null}
                      />
                    ) : (
                      <AllCells columnMetadata={columnMetadata} value={value} />
                    )
                  ) : (
                    <div className="text-muted">N/A</div>
                  )}
                </div>
              </div>
            </div>
            {index < detailColumns.length - 1 && <Separator className="my-2" />}
          </div>
        )
      })}
    </div>
  )
}
