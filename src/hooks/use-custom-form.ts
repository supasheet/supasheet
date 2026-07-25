import { useState } from "react"

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
  ColumnMetadata,
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

export type FormResult =
  | { kind: "object"; data: Record<string, unknown> }
  | { kind: "set"; data: Record<string, unknown>[] }

function toFormResult(data: unknown): FormResult | null {
  if (Array.isArray(data)) return { kind: "set", data }
  if (data !== null && typeof data === "object") {
    return { kind: "object", data: data as Record<string, unknown> }
  }
  return null
}

function withDisplayName<S extends DatabaseSchemas>(
  col: ColumnSchema<S>
): ColumnSchema<S> {
  const paramName = col.name ?? col.id
  if (!paramName?.startsWith("p_")) return col

  const existingMeta = col.comment
    ? (JSON.parse(col.comment) as ColumnMetadata)
    : {}
  return {
    ...col,
    comment: JSON.stringify({
      ...existingMeta,
      name: existingMeta.name ?? paramName.slice(2),
    }),
  }
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
  const [result, setResult] = useState<FormResult | null>(null)

  const writableCols = fieldsSchema
    .filter((col) => !isSkippedForCreate(col))
    .map(withDisplayName)

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

      let data: unknown
      try {
        data = await runResourceForm({
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

      const formResult = toFormResult(data)
      if (!formResult) {
        goBack()
        return
      }

      setResult(formResult)
    },
  })

  return { meta, writableCols, tableSchema, form, result }
}
