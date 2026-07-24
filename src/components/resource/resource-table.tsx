import { useMemo } from "react"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

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
        onDelete={canDelete ? handleDelete : undefined}
      />
    </DataTable>
  )
}
