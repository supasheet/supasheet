import { ResourceFormLayout } from "#/components/resource/resource-form-layout"
import { useCustomForm } from "#/hooks/use-custom-form"
import type {
  ColumnSchema,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
} from "#/lib/database-meta.types"
import type { ResourceFormRow } from "#/lib/supabase/data/form"

export function CustomForm<S extends DatabaseSchemas>({
  schema,
  resource,
  form: formRow,
  fieldsSchema,
}: {
  schema: S
  resource: DatabaseTables<S> | DatabaseViews<S>
  form: ResourceFormRow<S>
  fieldsSchema: ColumnSchema<S>[]
}) {
  const { meta, writableCols, tableSchema, form } = useCustomForm({
    schema,
    resource,
    form: formRow,
    fieldsSchema,
  })

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        form.handleSubmit()
      }}
    >
      <div className="mb-4 space-y-1">
        <h2 className="text-lg font-semibold">{meta.name}</h2>
        {meta.description && (
          <p className="text-sm text-muted-foreground">{meta.description}</p>
        )}
      </div>
      <ResourceFormLayout
        tableSchema={tableSchema}
        writableCols={writableCols}
        form={form}
        mode="create"
        headerTitle={meta.name}
      />
    </form>
  )
}
