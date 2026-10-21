import { ArrowUpRightIcon } from "lucide-react"

import { getDataTableSelectColumn } from "#/components/data-table/data-table-select-column"
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
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import type { ResourceActionRow } from "#/lib/supabase/data/resource"

import { ResourceColumnHeader } from "../resource-column-header"
import { ResourceRowActions } from "../resource-row-actions"
import { ResourceRowCell } from "../resource-row-cell"
import { DetailRecordTrigger } from "../sheet/detail-record-trigger"

export function getResourceForeignTableColumns({
  columnsSchema,
  resourceSchema,
  actions = [],
}: {
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
  actions?: ResourceActionRow[]
}) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null
  const primaryKeys = tableSchema?.primary_keys ?? []
  const primaryKeyNames = primaryKeys.map((k) => k.name)
  const hasPrimaryKeys = primaryKeys.length > 0

  const selectColumns: DataTableColumnDef<ResourceDataSchema>[] = hasPrimaryKeys
    ? [
        getDataTableSelectColumn<ResourceDataSchema>(),
        {
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
                schema={resourceSchema.schema}
                resource={resourceSchema.name}
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
          enableColumnFilter: false,
        },
      ]
    : []

  return [
    ...selectColumns,
    ...(actions.length > 0
      ? [
          {
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
          },
        ]
      : []),
    ...(columnsSchema ?? []).map((c) => {
      const meta = getColumnDefMeta(resourceSchema, c)

      return {
        id: c.name,
        accessorKey: c.name,
        header: ({
          column,
        }: {
          column: DataTableColumn<ResourceDataSchema>
        }) => (
          <ResourceColumnHeader
            column={column}
            title={meta.field?.name ?? c.name}
            isSorted={column.getIsSorted()}
          />
        ),
        cell: ({ row }: { row: DataTableRow<ResourceDataSchema> }) => (
          <ResourceRowCell
            row={row}
            columnSchema={c}
            resourceSchema={resourceSchema}
          />
        ),
        size: 150,
        enableColumnFilter: true,
        enableSorting: true,
        enableHiding: true,
        meta,
      }
    }),
  ] as DataTableColumnDef<ResourceDataSchema>[]
}
