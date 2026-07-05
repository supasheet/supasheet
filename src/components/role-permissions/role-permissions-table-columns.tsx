import type { ColumnDef } from "@tanstack/react-table"

import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { Checkbox } from "#/components/ui/checkbox"
import { getColumnMetadata } from "#/lib/columns"
import type { ColumnSchema } from "#/lib/database-meta.types"
import type { Database } from "#/lib/database.types"

type RolePermission = Database["supasheet"]["Tables"]["role_permissions"]["Row"]

export function getRolePermissionsTableColumns({
  columnsSchema,
}: {
  columnsSchema: ColumnSchema<"supasheet">[]
}): ColumnDef<RolePermission, unknown>[] {
  return [
    {
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
      cell: ({ row }) => (
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(checked) => row.toggleSelected(!!checked)}
          aria-label="Select row"
        />
      ),
      enableSorting: false,
      enableHiding: false,
    },
    {
      accessorKey: "id",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="ID" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-xs text-muted-foreground">
          {row.getValue("id")}
        </span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "id") as ColumnSchema
      ),
    },
    {
      accessorKey: "role",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Role" />
      ),
      cell: ({ row }) => (
        <span className="text-sm font-medium">{row.getValue("role")}</span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "role") as ColumnSchema
      ),
    },
    {
      accessorKey: "permission",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Permission" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-xs">{row.getValue("permission")}</span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "permission") as ColumnSchema
      ),
    },
  ]
}
