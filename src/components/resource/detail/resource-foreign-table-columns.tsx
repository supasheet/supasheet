import type { ColumnDef, Row } from "@tanstack/react-table"

import type {
  ColumnSchema,
  ResourceDataSchema,
  ResourceSchema,
} from "@/lib/database-meta.types"
import { isTableSchema } from "@/lib/database-meta.types"
import { formatTitle } from "@/lib/format"
import { ArrowUpRightIcon } from "lucide-react"

import { Checkbox } from "#/components/ui/checkbox"
import { getColumnMetadata } from "#/lib/columns"

import { ResourceRowCell } from "../resource-row-cell"
import { DetailRecordTrigger } from "../sheet/detail-record-trigger"

export function getResourceForeignTableColumns({
  columnsSchema,
  resourceSchema,
}: {
  columnsSchema: ColumnSchema[]
  resourceSchema: ResourceSchema
}) {
  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null
  const primaryKeys = tableSchema?.primary_keys ?? []
  const primaryKeyNames = primaryKeys.map((k) => k.name)
  const hasPrimaryKeys = primaryKeys.length > 0

  const selectColumn: ColumnDef<ResourceDataSchema, unknown> | null =
    hasPrimaryKeys
      ? {
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
                  schema={resourceSchema.schema}
                  resource={resourceSchema.name}
                  size="icon-xs"
                  variant="outline"
                  className="opacity-0 transition-opacity group-hover:opacity-100 [&_svg]:size-3 size-5"
                >
                  <ArrowUpRightIcon />
                </DetailRecordTrigger>
              </div>
            )
          },
          size: 60,
          enableSorting: false,
          enableHiding: false,
          enableColumnFilter: false,
        }
      : null

  return [
    ...(selectColumn ? [selectColumn] : []),
    ...(columnsSchema ?? []).map((c) => {
      const meta = getColumnMetadata(resourceSchema, c)

      return {
        id: c.name,
        accessorKey: c.name,
        header: () => (
          <div className="truncate select-none">{formatTitle(meta.name)}</div>
        ),
        cell: ({ row }: { row: Row<ResourceDataSchema> }) => (
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
  ] as ColumnDef<ResourceDataSchema, unknown>[]
}
