import { useMemo } from "react"

import { buildLayoutPlan } from "#/components/resource/resource-form-utils"
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
  showMetadata?: boolean
}

export function ResourceFullDetail({
  resourceSchema,
  columnsSchema,
  record,
  showMetadata = true,
}: Props) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null

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
