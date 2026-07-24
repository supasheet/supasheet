import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { useAppForm } from "#/components/resource/form-hook"
import {
  buildCreatePayload,
  getCreateInitialValue,
  isSkippedForCreate,
} from "#/components/resource/resource-form-utils"
import type {
  ColumnSchema,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  FormMeta,
  JoinClause,
  Relationship,
  TableMetadata,
  TableSchema,
} from "#/lib/database-meta.types"
import type { ResourceFormRow } from "#/lib/supabase/data/form"
import { runResourceFormMutationOptions } from "#/lib/supabase/data/form"

export function getFormMeta(form: ResourceFormRow): FormMeta {
  return (form.comment ? JSON.parse(form.comment) : {}) as FormMeta
}

function buildRelationshipConfig<S extends DatabaseSchemas>(
  schema: S,
  sourceTableName: string,
  relations: NonNullable<NonNullable<FormMeta["fields"]>["relations"]>
): { relationships: Relationship[]; join: JoinClause[] } {
  const entries = Object.entries(relations)

  const relationships: Relationship[] = entries.map(
    ([paramName, relation], index) => ({
      id: index + 1,
      constraint_name: `${sourceTableName}_${paramName}`,
      source_schema: schema,
      source_table_name: sourceTableName as DatabaseTables<DatabaseSchemas>,
      source_column_name: paramName,
      target_table_schema: relation.schema ?? schema,
      target_table_name: relation.table as DatabaseTables<DatabaseSchemas>,
      target_column_name: relation.column ?? "id",
    })
  )

  const join: JoinClause[] = entries.map(([paramName, relation]) => ({
    table: relation.table,
    on: paramName,
    columns: relation.display,
  }))

  return { relationships, join }
}

export function useCustomForm<S extends DatabaseSchemas>({
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
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const meta = getFormMeta(formRow)

  const writableCols = fieldsSchema.filter((col) => !isSkippedForCreate(col))

  const { mutateAsync: runResourceForm } = useMutation(
    runResourceFormMutationOptions()
  )

  const defaultValues = Object.fromEntries(
    writableCols.map((col) => [col.name ?? col.id, getCreateInitialValue(col)])
  )

  const relations = meta.fields?.relations
  const { relationships, join } = relations
    ? buildRelationshipConfig(schema, formRow.name, relations)
    : { relationships: [], join: [] }

  const tableMetaForForm: TableMetadata = {
    fields: meta.fields,
    query: join.length ? { join } : undefined,
  }

  const tableSchema: TableSchema<S> = {
    id: 0,
    schema,
    name: resource,
    comment: JSON.stringify(tableMetaForForm),
    primary_keys: [],
    relationships,
    bytes: null,
    dead_rows_estimate: null,
    live_rows_estimate: null,
    replica_identity: null,
    rls_enabled: null,
    rls_forced: null,
    size: null,
  }

  function goBack() {
    navigate({
      to: "/$schema/resource/$resource",
      params: { schema, resource },
    })
  }

  const form = useAppForm({
    defaultValues,
    onSubmit: async ({ value }) => {
      const payload = buildCreatePayload(value, writableCols)

      try {
        await runResourceForm({
          schema: formRow.schema,
          functionName: formRow.name,
          params: payload,
        })
      } catch (err) {
        toast.error(
          err instanceof Error ? err.message : `Failed to submit ${meta.name}`
        )
        return
      }

      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(meta.success_message ?? `${meta.name} submitted`)
      goBack()
    },
  })

  return { meta, writableCols, tableSchema, form }
}
