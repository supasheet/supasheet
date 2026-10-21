import { getColumnDefMeta } from "#/lib/columns"
import type {
  DataTableColumn,
  DataTableColumnDef,
} from "#/lib/data-table-types"
import type { ColumnSchema, TableSchema } from "#/lib/database-meta.types"

import { ResourceGridColumnHeader } from "./resource-grid-column-header"

export function getResourceGridColumns({
  columnsSchema,
  tableSchema,
}: {
  columnsSchema: ColumnSchema[]
  tableSchema: TableSchema | null
}) {
  const cols: DataTableColumnDef<Record<string, unknown>>[] = []

  for (const col of columnsSchema) {
    const name = col.name ?? col.id
    const meta = getColumnDefMeta(tableSchema, col)

    cols.push({
      id: name,
      accessorKey: name,
      header: ({
        column,
      }: {
        column: DataTableColumn<Record<string, unknown>>
      }) => (
        <ResourceGridColumnHeader
          column={column}
          title={meta.field?.name ?? name}
          tableSchema={tableSchema}
          columnSchema={col}
          isSorted={column.getIsSorted()}
        />
      ),
      size: 170,
      enableSorting: true,
      enableHiding: true,
      enableColumnFilter: true,
      meta,
    })
  }

  return cols
}
