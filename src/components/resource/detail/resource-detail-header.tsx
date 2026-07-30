import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { Trash2Icon } from "lucide-react"
import { toast } from "sonner"

import { ResourceRowActions } from "#/components/resource/resource-row-actions"
import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import { useHasPermission } from "#/hooks/use-permissions"
import { getColumnMetadata } from "#/lib/columns"
import type {
  ColumnSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import {
  deleteResourceMutationOptions,
  resourceActionsQueryOptions,
} from "#/lib/supabase/data/resource"

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
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const schema = resourceSchema.schema
  const resource = resourceSchema.name
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const hasDeletePermission = useHasPermission({
    schema,
    resource,
    action: "delete",
  })
  const canDelete = primaryKeys.length > 0 && hasDeletePermission

  const { mutateAsync: deleteRow } = useMutation(
    deleteResourceMutationOptions(schema, resource)
  )

  const deleteConfirm = useConfirmAction<true>(async () => {
    const pk = Object.fromEntries(
      primaryKeys.map((key) => [key.name, record[key.name]])
    )
    try {
      await deleteRow(pk)
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success("Record deleted")
      navigate({
        to: "/$schema/resource/$resource",
        params: { schema, resource },
      })
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to delete record"
      )
    }
  })

  const detailMeta = (
    JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  ).detail?.header

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

  const { data: actions = [] } = useQuery(
    resourceActionsQueryOptions(
      resourceSchema.schema as never,
      resourceSchema.name
    )
  )

  return (
    <div className="mb-4 flex items-center justify-between gap-4">
      <div className="min-w-0 space-y-2">
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
      <div className="flex items-center gap-2">
        <ResourceRowActions
          schema={resourceSchema.schema}
          resource={resourceSchema.name}
          record={record}
          actions={actions}
          columnsSchema={columnsSchema}
          variant="menu"
        />
        {canDelete && (
          <Button
            size="sm"
            variant="destructive"
            className="px-2 sm:px-2.5"
            onClick={() => deleteConfirm.request(true)}
          >
            <Trash2Icon />
            <span className="hidden sm:inline">Delete</span>
          </Button>
        )}
      </div>
      <ConfirmDeleteDialog
        open={deleteConfirm.open}
        onOpenChange={(open) => !open && deleteConfirm.cancel()}
        onConfirm={deleteConfirm.confirm}
        title="Delete record?"
        pending={deleteConfirm.pending}
      />
    </div>
  )
}
