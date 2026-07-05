import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Label } from "#/components/ui/label"
import { getColumnMetadata } from "#/lib/columns"
import type { ColumnSchema, ResourceSchema } from "#/lib/database-meta.types"
import { getMetaFields, isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"

import { AllCells } from "../cells/all-cells"
import { getColumnFieldSpan } from "../resource-form-utils"

export function ResourceMetadataView({
  resourceSchema,
  columnsSchema,
  singleResourceData,
}: {
  resourceSchema: ResourceSchema
  columnsSchema: ColumnSchema[]
  singleResourceData: Record<string, unknown>
}) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null
  const metadataColumns =
    columnsSchema?.filter((column) => {
      const name = column.name
      return getMetaFields(resourceSchema).includes(name)
    }) ?? []

  if (!metadataColumns.length) return null

  return (
    <Card>
      <CardHeader>
        <CardTitle>Metadata</CardTitle>
        <CardDescription>
          Timestamps and other metadata information
        </CardDescription>
      </CardHeader>
      <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
        {metadataColumns.map((column) => {
          const value = singleResourceData?.[column.name]

          const columnMetadata = getColumnMetadata(tableSchema, column)
          const span = getColumnFieldSpan(column, tableSchema)

          return (
            <div
              key={column.id}
              className={
                span === 2
                  ? "flex min-w-0 flex-col gap-1.5 md:col-span-2"
                  : "flex min-w-0 flex-col gap-1.5"
              }
            >
              <Label className="inline-flex items-center gap-1.5 text-sm font-medium">
                {columnMetadata.icon} {formatTitle(columnMetadata.name)}
              </Label>
              <div className="text-sm text-muted-foreground">
                <AllCells columnMetadata={columnMetadata} value={value} />
              </div>
            </div>
          )
        })}
      </CardContent>
    </Card>
  )
}
