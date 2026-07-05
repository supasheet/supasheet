import type { ColumnDef } from "@tanstack/react-table"

import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { Checkbox } from "#/components/ui/checkbox"
import { getColumnMetadata } from "#/lib/columns"
import type { ColumnSchema } from "#/lib/database-meta.types"
import type { Database } from "#/lib/database.types"

export type UserRole = Database["supasheet"]["Tables"]["user_roles"]["Row"]

export function getUserRolesTableColumns({
  columnsSchema,
}: {
  columnsSchema: ColumnSchema<"supasheet">[]
}): ColumnDef<UserRole, unknown>[] {
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
      accessorKey: "user_id",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="User ID" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-xs text-muted-foreground">
          {row.getValue("user_id")}
        </span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "user_id") as ColumnSchema
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
  ]
}
