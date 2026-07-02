import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import type {
  ColumnSchema,
  TableMetadata,
  TableSchema,
} from "#/lib/database-meta.types"
import { insertResourceMutationOptions } from "#/lib/supabase/data/resource"

import { useAppForm } from "./form-hook"
import { ResourceFormLayout } from "./resource-form-layout"
import {
  buildCreatePayload,
  getCreateInitialValue,
  isSkippedForCreate,
} from "./resource-form-utils"

export function ResourceNewForm({
  columnsSchema,
  tableSchema,
  defaults,
  saveOnly,
}: {
  columnsSchema: ColumnSchema[]
  tableSchema: TableSchema
  defaults?: Record<string, string>
  saveOnly?: boolean
}) {
  const schema = tableSchema.schema
  const table = tableSchema.name

  const queryClient = useQueryClient()
  const navigate = useNavigate()

  const writableCols = columnsSchema.filter((col) => !isSkippedForCreate(col))

  const defaultValues = Object.fromEntries(
    writableCols.map((col) => {
      const key = col.name ?? col.id
      const override = defaults?.[key]
      return [
        key,
        override !== undefined ? override : getCreateInitialValue(col),
      ]
    })
  )

  const { mutateAsync: insertRow } = useMutation(
    insertResourceMutationOptions(schema, table)
  )

  const primaryKeys = tableSchema.primary_keys ?? []

  const behavior = (JSON.parse(tableSchema.comment ?? "{}") as TableMetadata)
    .fields?.behavior

  const form = useAppForm({
    defaultValues,
    onSubmit: async ({ value, meta }) => {
      const payload = buildCreatePayload(value, writableCols, behavior)
      let inserted: Record<string, unknown> | null = null
      try {
        inserted = await insertRow(payload)
      } catch (error) {
        toast.error(
          error instanceof Error ? error.message : "An error occurred"
        )
        console.error(error)
        return
      }
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, table],
      })
      toast.success("Record created")

      const resourceId =
        inserted && primaryKeys.length
          ? String(inserted[primaryKeys[0].name] ?? "")
          : ""

      const target = (meta as { target?: string } | undefined)?.target ?? "stay"

      if (target === "stay" && resourceId) {
        navigate({
          to: "/$schema/resource/$resource/$resourceId/detail",
          params: { schema, resource: table, resourceId },
        })
      } else {
        navigate({
          to: "/$schema/resource/$resource",
          params: { schema, resource: table },
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
        writableCols={writableCols}
        form={form}
        mode="create"
        headerTitle="New record"
        saveOnly={saveOnly}
      />
    </form>
  )
}
