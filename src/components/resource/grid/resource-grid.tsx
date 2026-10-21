import { useCallback, useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { DataGrid } from "#/components/data-grid/data-grid"
import { DataTableAdvancedToolbar } from "#/components/data-table/data-table-advanced-toolbar"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableFilterMenu } from "#/components/data-table/data-table-filter-menu"
import { DataTableSortMenu } from "#/components/data-table/data-table-sort-menu"
import { useDataTable } from "#/hooks/use-data-table"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type {
  ColumnSchema,
  FilterPreset,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { updateResourceMutationOptions } from "#/lib/supabase/data/resource"

import { ResourceFilterPresets } from "../resource-filter-presets"
import { getResourceGridColumns } from "./resource-grid-columns"

interface ResourceGridProps {
  data: Record<string, unknown>[]
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
  pageCount: number
  filterPresets?: FilterPreset[]
}

export function ResourceGrid({
  data,
  columnsSchema,
  resourceSchema,
  pageCount,
  filterPresets = [],
}: ResourceGridProps) {
  const queryClient = useQueryClient()
  const schema = resourceSchema.schema
  const resource = resourceSchema.name
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null
  const primaryKeys = tableSchema?.primary_keys ?? []

  const columns = useMemo(() => {
    const tableMeta = JSON.parse(
      resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const selectColumns = tableMeta.query?.select
    const visibleColumnsSchema = selectColumns
      ? selectColumns
          .map((name) =>
            columnsSchema.find((col) => (col.name ?? col.id) === name)
          )
          .filter((col) => col !== undefined)
      : columnsSchema
    return getResourceGridColumns({
      columnsSchema: visibleColumnsSchema,
      tableSchema,
    })
  }, [columnsSchema, tableSchema, resourceSchema.comment])

  const { table } = useDataTable({
    columns,
    data,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
    getRowId: (row) => primaryKeys.map((key) => row[key.name]).join("/"),
  })

  const { mutateAsync: updateRow } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )

  const handleRowsChange = useCallback(
    (
      rows: Record<string, unknown>[],
      { indexes, column }: { indexes: number[]; column: { key: string } }
    ) => {
      const updatedRow = rows[indexes[0]]
      if (!updatedRow) return

      const pk = Object.fromEntries(
        primaryKeys.map((k) => [k.name, updatedRow[k.name]])
      )

      const fieldKey = column.key
      let value = updatedRow[fieldKey]

      if (value === "" || value === null || value === undefined) {
        value = null
      } else {
        const col = columnsSchema.find((c) => (c.name ?? c.id) === fieldKey)
        if (
          col &&
          (col.format === "json" || col.format === "jsonb") &&
          typeof value === "string"
        ) {
          try {
            value = JSON.parse(value)
          } catch {}
        }
      }

      updateRow({ pk, data: { [fieldKey]: value } })
        .then(() => {
          queryClient.invalidateQueries({
            queryKey: ["supasheet", "resource-data", schema, resource],
          })
          toast.success("Record updated")
        })
        .catch((err: Error) => {
          toast.error(err.message ?? "Failed to update record")
        })
    },
    [primaryKeys, columnsSchema, updateRow, queryClient, schema, resource]
  )

  return (
    <DataGrid
      table={table}
      className="min-h-0 flex-1"
      isEditable={!!tableSchema}
      onRowsChange={handleRowsChange}
    >
      <DataTableAdvancedToolbar table={table}>
        <ResourceFilterPresets table={table} filterPresets={filterPresets} />
        <DataTableFilterMenu table={table} />
        <DataTableSortMenu table={table} />
        <DataTableExportButton table={table} filename={resource} />
      </DataTableAdvancedToolbar>
    </DataGrid>
  )
}
