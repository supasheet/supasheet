import { ArrowUpRightIcon } from "lucide-react"

import { getDataTableSelectColumn } from "#/components/data-table/data-table-select-column"
import { DetailRecordTrigger } from "#/components/resource/sheet/detail-record-trigger"
import { getColumnDefMeta } from "#/lib/columns"
import type {
  DataTableColumn,
  DataTableColumnDef,
  DataTableRow,
} from "#/lib/data-table-types"
import type {
  ColumnSchema,
  ResourceDataSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import type { ResourceActionRow } from "#/lib/supabase/data/resource"

import { ResourceColumnHeader } from "./resource-column-header"
import { ResourceRowActions } from "./resource-row-actions"
import { ResourceRowCell } from "./resource-row-cell"

export function getResourceTableColumns({
  columnsSchema,
  resourceSchema,
  actions = [],
}: {
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
  actions?: ResourceActionRow[]
}) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null

  const tableMeta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata

  const cols: DataTableColumnDef<ResourceDataSchema>[] = []

  if (tableSchema?.primary_keys) {
    const primaryKeys = tableSchema.primary_keys ?? []
    const primaryKeyNames = primaryKeys.map((k) => k.name)
    cols.push(getDataTableSelectColumn<ResourceDataSchema>(), {
      id: "detail",
      header: () => null,
      cell: ({ row }) => {
        const pk = Object.fromEntries(
          primaryKeys.map((k) => [k.name, row.original[k.name]])
        )
        return (
          <DetailRecordTrigger
            pk={pk}
            primaryKeyNames={primaryKeyNames}
            size="icon-xs"
            variant="outline"
            className="size-5 opacity-0 transition-opacity group-hover:opacity-100 [&_svg]:size-3"
          >
            <ArrowUpRightIcon />
          </DetailRecordTrigger>
        )
      },
      size: 40,
      enableSorting: false,
      enableHiding: false,
    })
  }

  if (actions.length > 0) {
    cols.push({
      id: "actions",
      header: () => null,
      cell: ({ row }: { row: DataTableRow<ResourceDataSchema> }) => (
        <ResourceRowActions
          schema={resourceSchema.schema}
          resource={resourceSchema.name}
          record={row.original}
          actions={actions}
          columnsSchema={columnsSchema}
        />
      ),
      size: 40,
      enableSorting: false,
      enableHiding: false,
      enableColumnFilter: false,
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
    const meta = getColumnDefMeta(tableSchema, col)

    cols.push({
      id: name,
      accessorKey: name,
      header: ({ column }: { column: DataTableColumn<ResourceDataSchema> }) => (
        <ResourceColumnHeader
          column={column}
          title={meta.field?.name ?? name}
          isSorted={column.getIsSorted()}
        />
      ),
      cell: ({ row }: { row: DataTableRow<ResourceDataSchema> }) => (
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
