import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import type {
  ColumnSchema,
  PrimaryKey,
  TableMetadata,
  TableSchema,
} from "#/lib/database-meta.types"
import { updateResourceMutationOptions } from "#/lib/supabase/data/resource"

import { useAppForm } from "./form-hook"
import { ResourceFormLayout } from "./resource-form-layout"
import {
  buildUpdatePayload,
  getUpdateInitialValue,
  isSkippedForUpdate,
} from "./resource-form-utils"

interface ResourceUpdateFormProps {
  columnsSchema: ColumnSchema[]
  primaryKeys: PrimaryKey[]
  record: Record<string, unknown>
  tableSchema: TableSchema
  saveOnly?: boolean
}

export function ResourceUpdateForm({
  columnsSchema,
  primaryKeys,
  record,
  tableSchema,
  saveOnly,
}: ResourceUpdateFormProps) {
  const schema = tableSchema?.schema
  const resource = tableSchema?.name

  const queryClient = useQueryClient()
  const navigate = useNavigate()

  const pk = Object.fromEntries(
    primaryKeys.map((k) => [k.name, record[k.name]])
  )

  const editableCols = columnsSchema.filter(
    (col) => !isSkippedForUpdate(col, primaryKeys) && (col.is_updatable ?? true)
  )

  const defaultValues = Object.fromEntries(
    editableCols.map((col) => [
      col.name ?? col.id,
      getUpdateInitialValue(col, record),
    ])
  )

  const { mutateAsync: updateRow } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )

  const behavior = (JSON.parse(tableSchema?.comment ?? "{}") as TableMetadata)
    .fields?.behavior

  const form = useAppForm({
    defaultValues,
    onSubmit: async ({ value, meta }) => {
      const data = buildUpdatePayload(value, editableCols, behavior)
      await updateRow({ pk, data })
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success("Record updated")
      if ((meta as { target?: string } | undefined)?.target === "close") {
        navigate({
          to: "/$schema/resource/$resource",
          params: { schema, resource },
        })
      }
    },
  })

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        form.handleSubmit()
      }}
    >
      <ResourceFormLayout
        tableSchema={tableSchema}
        writableCols={editableCols}
        form={form}
        mode="update"
        headerTitle="Edit record"
        saveOnly={saveOnly}
      />
    </form>
  )
}
