import type { Column, ColumnDef, Row } from "@tanstack/react-table"

import { ArrowUpRightIcon } from "lucide-react"

import { DetailRecordTrigger } from "#/components/resource/sheet/detail-record-trigger"
import { Checkbox } from "#/components/ui/checkbox"
import { getColumnMetadata } from "#/lib/columns"
import type {
  ColumnSchema,
  ResourceDataSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"

import { ResourceColumnHeader } from "./resource-column-header"
import { ResourceRowCell } from "./resource-row-cell"

export function getResourceTableColumns({
  columnsSchema,
  resourceSchema,
}: {
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
}) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null

  const tableMeta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata

  const cols: ColumnDef<Record<string, unknown>, unknown>[] = []

  if (tableSchema?.primary_keys) {
    const primaryKeys = tableSchema.primary_keys ?? []
    const primaryKeyNames = primaryKeys.map((k) => k.name)
    cols.push({
      id: "select",
      header: ({ table }) => (
        <Checkbox
          checked={table.getIsAllPageRowsSelected()}
          indeterminate={
            table.getIsSomePageRowsSelected() &&
            !table.getIsAllPageRowsSelected()
          }
          onCheckedChange={(checked) =>
            table.toggleAllPageRowsSelected(!!checked)
          }
          aria-label="Select all"
        />
      ),
      cell: ({ row }) => {
        const pk = Object.fromEntries(
          primaryKeys.map((k) => [k.name, row.original[k.name]])
        )
        return (
          <div className="flex items-center gap-1.5">
            <Checkbox
              checked={row.getIsSelected()}
              onCheckedChange={(checked) => row.toggleSelected(!!checked)}
              aria-label="Select row"
            />
            <DetailRecordTrigger
              pk={pk}
              primaryKeyNames={primaryKeyNames}
              size="icon-xs"
              variant="outline"
              className="opacity-0 transition-opacity group-hover:opacity-100 [&_svg]:size-3 size-5"
            >
              <ArrowUpRightIcon />
            </DetailRecordTrigger>
          </div>
        )
      },
      enableSorting: false,
      enableHiding: false,
    })
  }

  const selectColumns = tableMeta.query?.select
  const visibleColumns = selectColumns
    ? selectColumns
        .map((name) =>
          columnsSchema.find((col) => (col.name ?? col.id) === name)
        )
        .filter((col) => col !== undefined)
    : columnsSchema

  for (const col of visibleColumns) {
    const name = col.name ?? col.id
    const meta = getColumnMetadata(tableSchema, col)

    cols.push({
      id: name,
      accessorKey: name,
      header: ({
        column,
      }: {
        column: Column<Record<string, unknown>, unknown>
      }) => (
        <ResourceColumnHeader
          column={column}
          title={meta.name}
          isSorted={column.getIsSorted()}
        />
      ),
      cell: ({ row }: { row: Row<ResourceDataSchema> }) => (
        <ResourceRowCell
          row={row}
          columnSchema={col}
          resourceSchema={resourceSchema}
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
