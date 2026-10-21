import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { getColumnDefMeta } from "#/lib/columns"
import type {
  DataTableColumn,
  DataTableColumnDef,
  DataTableRow,
} from "#/lib/data-table-types"
import type { ColumnSchema } from "#/lib/database-meta.types"

function formatCellValue(value: unknown): string {
  if (value === null || value === undefined) return "—"
  if (typeof value === "object") return JSON.stringify(value)
  return String(value)
}

export function getReportTableColumns(columnsSchema: ColumnSchema[]) {
  return columnsSchema.map((col) => {
    const meta = getColumnDefMeta(null, col)

    return {
      id: col.name ?? col.id,
      accessorKey: col.name,
      header: ({
        column,
      }: {
        column: DataTableColumn<Record<string, unknown>>
      }) => (
        <DataTableColumnHeader column={column} label={meta.label ?? col.name} />
      ),
      cell: ({ row }: { row: DataTableRow<Record<string, unknown>> }) => {
        const value = row.getValue(col.name)
        return (
          <span className="text-sm text-muted-foreground">
            {formatCellValue(value)}
          </span>
        )
      },
      size: 170,
      enableSorting: true,
      enableHiding: true,
      enableColumnFilter: true,
      meta,
    }
  }) as DataTableColumnDef<Record<string, unknown>>[]
}
