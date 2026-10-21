import { useMemo } from "react"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableAdvancedToolbar } from "#/components/data-table/data-table-advanced-toolbar"
import { DataTableBulkActions } from "#/components/data-table/data-table-bulk-actions"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableFilterMenu } from "#/components/data-table/data-table-filter-menu"
import { DataTableSortMenu } from "#/components/data-table/data-table-sort-menu"
import { useDataTable } from "#/hooks/use-data-table"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type { ColumnSchema } from "#/lib/database-meta.types"

import type { AuditLog } from "./audit-logs-table-columns"
import { getAuditLogsTableColumns } from "./audit-logs-table-columns"

interface AuditLogTableProps {
  data: AuditLog[]
  columnsSchema: ColumnSchema<"supasheet">[]
  pageCount: number
}

export function AuditLogTable({
  data,
  columnsSchema,
  pageCount,
}: AuditLogTableProps) {
  const columns = useMemo(
    () => getAuditLogsTableColumns({ columnsSchema }),
    [columnsSchema]
  )
  const { table } = useDataTable({
    columns,
    data,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
    getRowId: (row) => row.id,
  })
  return (
    <DataTable
      table={table}
      actionBar={<DataTableBulkActions table={table} filename="audit_logs" />}
    >
      <DataTableAdvancedToolbar table={table}>
        <DataTableFilterMenu table={table} />
        <DataTableSortMenu table={table} />
        <DataTableExportButton table={table} filename="audit_logs" />
      </DataTableAdvancedToolbar>
    </DataTable>
  )
}
