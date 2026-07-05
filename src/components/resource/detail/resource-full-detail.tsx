import { useMemo } from "react"

import { buildLayoutPlan } from "#/components/resource/resource-form-utils"
import { Card, CardContent, CardHeader, CardTitle } from "#/components/ui/card"
import { Label } from "#/components/ui/label"
import type {
  ColumnSchema,
  EnumColumnMetadata,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"

import { ResourceDetailView } from "./resource-detail-view"
import { ResourceMetadataView } from "./resource-metadata-view"
import { ResourceProgressField } from "./resource-progress-field"
import { ResourceSectionDetail } from "./resource-section-detail"

type Props = {
  resourceSchema: ResourceSchema
  columnsSchema: ColumnSchema[]
  record: Record<string, unknown>
  showIdentifiers?: boolean
  showMetadata?: boolean
}

export function ResourceFullDetail({
  resourceSchema,
  columnsSchema,
  record,
  showIdentifiers = true,
  showMetadata = true,
}: Props) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null
  const primaryKeys = tableSchema ? (tableSchema.primary_keys ?? []) : []

  const { colByName, progressFields, filteredPlan } = useMemo(() => {
    const tableMeta = JSON.parse(
      resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const availableNames = new Set(
      columnsSchema.map((c) => c.name ?? c.id ?? "")
    )
    const plan = buildLayoutPlan(
      tableMeta.fields?.sections,
      availableNames,
      "read"
    )
    const byName = new Map(columnsSchema.map((c) => [c.name ?? c.id ?? "", c]))
    const progress = columnsSchema
      .map((col) => {
        const meta = JSON.parse(col.comment ?? "{}") as EnumColumnMetadata
        if (!meta?.progress || !meta.enums) return null
        return { col, meta }
      })
      .filter((x): x is { col: ColumnSchema; meta: EnumColumnMetadata } =>
        Boolean(x)
      )
    const progressNames = new Set(progress.map(({ col }) => col.name))
    const filtered = plan
      ? {
          ...plan,
          sections: plan.sections
            .map((s) => ({
              ...s,
              fields: s.fields.filter((f) => !progressNames.has(f)),
            }))
            .filter((s) => s.fields.length > 0),
        }
      : plan
    return {
      colByName: byName,
      progressFields: progress,
      filteredPlan: filtered,
    }
  }, [resourceSchema.comment, columnsSchema])

  const primaryKeyDisplay = primaryKeys
    .map((key) => {
      const col = colByName.get(key.name)
      if (!col) return null
      return {
        name: col.name,
        value: String(record[col.name] ?? ""),
      }
    })
    .filter((p): p is { name: string; value: string } => Boolean(p))

  return (
    <div className="space-y-4">
      {progressFields.length > 0 && (
        <div className="space-y-4">
          {progressFields.map(({ col, meta }) => (
            <ResourceProgressField
              key={col.id}
              column={col}
              value={(record[col.name] as string | null) ?? null}
              enumMeta={meta}
            />
          ))}
        </div>
      )}
      {filteredPlan ? (
        <>
          {showIdentifiers && primaryKeyDisplay.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle>Identifiers</CardTitle>
              </CardHeader>
              <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
                {primaryKeyDisplay.map((p) => (
                  <div
                    key={p.name}
                    className="flex min-w-0 flex-col gap-1.5 md:col-span-2"
                  >
                    <Label className="inline-flex items-center gap-1.5 text-sm font-medium">
                      {p.name}
                    </Label>
                    <div className="font-mono text-sm text-muted-foreground">
                      {p.value}
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}
          {filteredPlan.sections.map((s) => (
            <ResourceSectionDetail
              key={s.id}
              section={s}
              colByName={colByName}
              tableSchema={tableSchema}
              record={record}
            />
          ))}
        </>
      ) : (
        <ResourceDetailView
          resourceSchema={resourceSchema}
          columnsSchema={columnsSchema}
          singleResourceData={record}
        />
      )}
      {showMetadata && (
        <ResourceMetadataView
          resourceSchema={resourceSchema}
          columnsSchema={columnsSchema}
          singleResourceData={record}
        />
      )}
    </div>
  )
}
