import { Badge } from "#/components/ui/badge"
import { getColumnMetadata } from "#/lib/columns"
import type {
  ColumnSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"

import { AllCells } from "../cells/all-cells"

type Props = {
  resourceSchema: ResourceSchema
  columnsSchema: ColumnSchema[]
  record: Record<string, unknown>
  fallbackId: string
}

export function ResourceDetailHeader({
  resourceSchema,
  columnsSchema,
  record,
  fallbackId,
}: Props) {
  const detailMeta = (
    JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  ).detail

  const colByName = new Map(columnsSchema.map((c) => [c.name ?? c.id ?? "", c]))

  const titleValue = detailMeta?.title ? record[detailMeta.title] : null
  const hasTitle = titleValue != null && titleValue !== ""
  const heading = hasTitle ? String(titleValue) : fallbackId

  const badges = (detailMeta?.badges ?? []).flatMap((name) => {
    const col = colByName.get(name)
    const value = record[name]
    if (!col || value == null || value === "") return []

    if (Array.isArray(value)) {
      return value.map((v, i) => (
        <Badge key={`${name}-${i}`} variant="secondary">
          {String(v)}
        </Badge>
      ))
    }

    const columnMetadata = getColumnMetadata(resourceSchema, col)
    if (columnMetadata.variant === "select") {
      return [
        <AllCells key={name} columnMetadata={columnMetadata} value={value} />,
      ]
    }

    return [
      <Badge key={name} variant="secondary">
        {String(value)}
      </Badge>,
    ]
  })

  return (
    <div className="mb-4 space-y-2">
      {hasTitle && (
        <div className="truncate font-mono text-xs tracking-wide text-muted-foreground">
          {fallbackId}
        </div>
      )}
      <h1 className="truncate text-xl font-bold tracking-tight">{heading}</h1>
      {badges.length > 0 && (
        <div className="flex flex-wrap items-center gap-1.5">{badges}</div>
      )}
    </div>
  )
}
