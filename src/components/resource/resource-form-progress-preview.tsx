import type {
  ColumnSchema,
  EnumColumnMetadata,
} from "#/lib/database-meta.types"

import { ResourceProgressField } from "./detail/resource-progress-field"
import type { ResourceFormApi } from "./form-hook"

export function ProgressFieldPreview({
  column,
  enumMeta,
  form,
}: {
  column: ColumnSchema
  enumMeta: EnumColumnMetadata
  form: ResourceFormApi
}) {
  return (
    <form.Subscribe selector={(s) => s.values[column.name] as string | null}>
      {(value) => (
        <ResourceProgressField
          column={column}
          value={value ?? null}
          enumMeta={enumMeta}
        />
      )}
    </form.Subscribe>
  )
}
