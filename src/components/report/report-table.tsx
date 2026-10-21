import { useMemo } from "react"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import { useDataTable } from "#/hooks/use-data-table"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type { ColumnSchema } from "#/lib/database-meta.types"

import { getReportTableColumns } from "./report-table-columns"

interface ReportTableProps {
  data: Record<string, unknown>[]
  columnsSchema: ColumnSchema[]
  pageCount: number
  filename?: string
}

export function ReportTable({
  data,
  columnsSchema,
  pageCount,
  filename,
}: ReportTableProps) {
  const columns = useMemo(
    () => getReportTableColumns(columnsSchema),
    [columnsSchema]
  )

  const { table } = useDataTable({
    columns,
    data,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
  })

  return (
    <DataTable table={table}>
      <DataTableToolbar table={table}>
        <DataTableExportButton table={table} filename={filename} />
      </DataTableToolbar>
    </DataTable>
  )
}
