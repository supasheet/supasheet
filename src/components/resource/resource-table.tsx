import { useMemo } from "react"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableAdvancedToolbar } from "#/components/data-table/data-table-advanced-toolbar"
import { DataTableBulkActions } from "#/components/data-table/data-table-bulk-actions"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableFilterMenu } from "#/components/data-table/data-table-filter-menu"
import { DataTableSortMenu } from "#/components/data-table/data-table-sort-menu"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasPermission } from "#/hooks/use-permissions"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type {
  ColumnSchema,
  FilterPreset,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import {
  deleteBulkResourceMutationOptions,
  resourceActionsQueryOptions,
} from "#/lib/supabase/data/resource"

import { ResourceFilterPresets } from "./resource-filter-presets"
import { getResourceTableColumns } from "./resource-table-columns"

interface ResourceTableProps {
  data: Record<string, unknown>[]
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
  pageCount: number
  filterPresets?: FilterPreset[]
}

export function ResourceTable({
  data,
  columnsSchema,
  resourceSchema,
  pageCount,
  filterPresets = [],
}: ResourceTableProps) {
  const queryClient = useQueryClient()
  const schema = resourceSchema.schema
  const resource = resourceSchema.name
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const canDelete = useHasPermission({ schema, resource, action: "delete" })

  const { data: actions = [] } = useQuery(
    resourceActionsQueryOptions(schema, resource)
  )

  const { mutateAsync: deleteRows } = useMutation(
    deleteBulkResourceMutationOptions(schema, resource)
  )
  const handleDelete = async (rows: Record<string, unknown>[]) => {
    try {
      await deleteRows(
        rows.map((row) =>
          Object.fromEntries(
            primaryKeys.map((key) => [key.name, row[key.name]])
          )
        )
      )
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(
        rows.length === 1 ? "Record deleted" : `${rows.length} records deleted`
      )
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to delete record"
      )
    }
  }

  const columns = useMemo(
    () => getResourceTableColumns({ columnsSchema, resourceSchema, actions }),
    [columnsSchema, resourceSchema, actions]
  )

  const { table } = useDataTable({
    columns,
    data,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
    getRowId: (row) => primaryKeys.map((key) => row[key.name]).join("/"),
  })

  return (
    <DataTable
      table={table}
      actionBar={
        <DataTableBulkActions
          table={table}
          filename={resource}
          onDelete={canDelete ? handleDelete : undefined}
        />
      }
    >
      <DataTableAdvancedToolbar table={table}>
        <ResourceFilterPresets table={table} filterPresets={filterPresets} />
        <DataTableFilterMenu table={table} />
        <DataTableSortMenu table={table} />
        <DataTableExportButton table={table} filename={resource} />
      </DataTableAdvancedToolbar>
    </DataTable>
  )
}
