import { useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import type {
  ColumnFiltersState,
  PaginationState,
  SortingState,
} from "@tanstack/react-table"

import { toast } from "sonner"

import { DataTableActionBar } from "#/components/data-table/data-table-action-bar"
import { DataTablePagination } from "#/components/data-table/data-table-pagination"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  ColumnSchema,
  FilterPreset,
  ListLayout,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { deleteBulkResourceMutationOptions } from "#/lib/supabase/data/resource"

import { ResourceFilterPresets } from "../resource-filter-presets"
import { getResourceTableColumns } from "../resource-table-columns"
import { ResourceListEmpty } from "./resource-list-empty"
import { ResourceListRow } from "./resource-list-row"

interface ResourceListProps {
  data: Record<string, unknown>[]
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
  listView: ListLayout
  sorting: SortingState
  pagination: PaginationState
  columnFilters: ColumnFiltersState
  pageCount: number
  filterPresets?: FilterPreset[]
}

export function ResourceList({
  data,
  columnsSchema,
  resourceSchema,
  listView,
  sorting,
  pagination,
  columnFilters,
  pageCount,
  filterPresets = [],
}: ResourceListProps) {
  const queryClient = useQueryClient()
  const schema = resourceSchema.schema
  const resource = resourceSchema.name
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const canDelete = useHasPermission({ schema, resource, action: "delete" })

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
    () => getResourceTableColumns({ columnsSchema, resourceSchema }),
    [columnsSchema, resourceSchema]
  )

  const table = useDataTable({
    columns,
    data,
    pageCount,
    state: { sorting, pagination, columnFilters },
    getRowId: (row) => primaryKeys.map((key) => row[key.name]).join("/"),
  })

  const rows = table.getRowModel().rows

  return (
    <div className="flex w-full flex-col gap-2">
      <DataTableToolbar table={table} hideColumnVisibility>
        <ResourceFilterPresets
          filterPresets={filterPresets}
          currentFilters={columnFilters}
        />
      </DataTableToolbar>
      <DataTableActionBar
        table={table}
        onDelete={canDelete ? handleDelete : undefined}
      />
      {rows.length === 0 ? (
        <ResourceListEmpty />
      ) : (
        <div className="divide-y overflow-hidden rounded-md border bg-card">
          {rows.map((row) => (
            <ResourceListRow
              key={row.id}
              row={row}
              listView={listView}
              schema={schema}
              resource={resource}
              primaryKeys={primaryKeys}
            />
          ))}
        </div>
      )}
      <DataTablePagination table={table} />
    </div>
  )
}
