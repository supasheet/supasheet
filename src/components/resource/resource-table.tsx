import { useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import type {
  ColumnFiltersState,
  PaginationState,
  SortingState,
} from "@tanstack/react-table"

import { toast } from "sonner"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableActionBar } from "#/components/data-table/data-table-action-bar"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  ColumnSchema,
  FilterPreset,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import {
  deleteBulkResourceMutationOptions,
  insertBulkResourceMutationOptions,
} from "#/lib/supabase/data/resource"

import { ResourceFilterPresets } from "./resource-filter-presets"
import { getResourceTableColumns } from "./resource-table-columns"

interface ResourceTableProps {
  data: Record<string, unknown>[]
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
  sorting: SortingState
  pagination: PaginationState
  columnFilters: ColumnFiltersState
  pageCount: number
  filterPresets?: FilterPreset[]
}

export function ResourceTable({
  data,
  columnsSchema,
  resourceSchema,
  sorting,
  pagination,
  columnFilters,
  pageCount,
  filterPresets = [],
}: ResourceTableProps) {
  const queryClient = useQueryClient()
  const schema = resourceSchema.schema
  const resource = resourceSchema.name
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const canDelete = useHasPermission(`${schema}.${resource}:delete`)
  const canInsert = useHasPermission(`${schema}.${resource}:insert`)

  const { mutateAsync: deleteRows } = useMutation(
    deleteBulkResourceMutationOptions(schema, resource)
  )
  const { mutateAsync: insertBulkRows } = useMutation(
    insertBulkResourceMutationOptions(schema, resource)
  )

  const duplicated = resourceSchema.comment
    ? (JSON.parse(resourceSchema.comment) as TableMetadata).fields?.duplicated
    : undefined

  const handleDuplicate = async (rows: Record<string, unknown>[]) => {
    try {
      const pkNames = new Set(primaryKeys.map((k) => k.name))
      const columnNames = new Set(
        columnsSchema.map((c) => c.name).filter((n): n is string => n !== null)
      )
      const fields = duplicated ?? [...columnNames]
      const stripped = rows.map((row) =>
        Object.fromEntries(
          fields
            .filter((f) => !pkNames.has(f) && columnNames.has(f))
            .map((f) => [f, row[f]])
        )
      )
      await insertBulkRows(stripped)
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(
        rows.length === 1
          ? "Record duplicated"
          : `${rows.length} records duplicated`
      )
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to duplicate records"
      )
    }
  }

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
    () => getResourceTableColumns({ columnsSchema, resourceSchema }),
    [columnsSchema, resourceSchema]
  )

  const table = useDataTable({
    columns,
    data,
    pageCount,
    state: { sorting, pagination, columnFilters },
    getRowId: (row) => primaryKeys.map((key) => row[key.name]).join("/"),
    meta: { filename: resource },
  })

  return (
    <DataTable table={table}>
      <DataTableToolbar table={table}>
        <ResourceFilterPresets
          filterPresets={filterPresets}
          currentFilters={columnFilters}
        />
      </DataTableToolbar>
      <DataTableActionBar
        table={table}
        onDuplicate={canInsert ? handleDuplicate : undefined}
        onDelete={canDelete ? handleDelete : undefined}
      />
    </DataTable>
  )
}
