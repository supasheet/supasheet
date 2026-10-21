import { useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"
import { Subscribe } from "@tanstack/react-table"

import { toast } from "sonner"

import { DataTableAdvancedToolbar } from "#/components/data-table/data-table-advanced-toolbar"
import { DataTableBulkActions } from "#/components/data-table/data-table-bulk-actions"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableFilterMenu } from "#/components/data-table/data-table-filter-menu"
import { DataTablePagination } from "#/components/data-table/data-table-pagination"
import { DataTableSortMenu } from "#/components/data-table/data-table-sort-menu"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasPermission } from "#/hooks/use-permissions"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
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
  pageCount: number
  filterPresets?: FilterPreset[]
}

export function ResourceList({
  data,
  columnsSchema,
  resourceSchema,
  listView,
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

  const { table } = useDataTable({
    columns,
    data,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
    getRowId: (row) => primaryKeys.map((key) => row[key.name]).join("/"),
  })

  const rows = table.getRowModel().rows

  return (
    <div className="flex w-full flex-col gap-2">
      <DataTableAdvancedToolbar table={table} hideViewOptions>
        <ResourceFilterPresets table={table} filterPresets={filterPresets} />
        <DataTableFilterMenu table={table} />
        <DataTableSortMenu table={table} />
        <DataTableExportButton table={table} filename={resource} />
      </DataTableAdvancedToolbar>
      <DataTableBulkActions
        table={table}
        filename={resource}
        onDelete={canDelete ? handleDelete : undefined}
      />
      {rows.length === 0 ? (
        <ResourceListEmpty />
      ) : (
        <Subscribe source={table.atoms.rowSelection}>
          {() => (
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
        </Subscribe>
      )}
      <DataTablePagination table={table} />
    </div>
  )
}
