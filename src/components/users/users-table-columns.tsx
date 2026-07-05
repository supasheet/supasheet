import { Link } from "@tanstack/react-router"

import type { ColumnDef } from "@tanstack/react-table"

import { ArrowUpRightIcon, PencilIcon, UserIcon } from "lucide-react"

import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { Avatar, AvatarFallback, AvatarImage } from "#/components/ui/avatar"
import { Checkbox } from "#/components/ui/checkbox"
import { getColumnMetadata } from "#/lib/columns"
import type { ColumnSchema } from "#/lib/database-meta.types"
import type { Database } from "#/lib/database.types"
import { formatDate } from "#/lib/format"

export type User = Database["supasheet"]["Tables"]["users"]["Row"]

export function getUsersTableColumns({
  columnsSchema,
  canUpdate = false,
}: {
  columnsSchema: ColumnSchema<"supasheet">[]
  canUpdate?: boolean
}): ColumnDef<User, unknown>[] {
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
        <div className="flex items-center gap-1.5">
          <Checkbox
            checked={row.getIsSelected()}
            onCheckedChange={(checked) => row.toggleSelected(!!checked)}
            aria-label="Select row"
          />
          {canUpdate ? (
            <Link
              to="/core/users/$userId/edit"
              params={{ userId: row.original.id }}
              className="inline-flex rounded border p-0.5 opacity-0 transition-opacity group-hover:opacity-100"
              onClick={(e) => e.stopPropagation()}
            >
              <PencilIcon className="size-3" />
            </Link>
          ) : (
            <Link
              to="/core/users/$userId"
              params={{ userId: row.original.id }}
              className="inline-flex rounded border p-0.5 opacity-0 transition-opacity group-hover:opacity-100"
              onClick={(e) => e.stopPropagation()}
            >
              <ArrowUpRightIcon className="size-3" />
            </Link>
          )}
        </div>
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
          {row.original.id}
        </span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "id") as ColumnSchema
      ),
    },
    {
      accessorKey: "name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Name" />
      ),
      cell: ({ row }) => {
        const name = row.getValue<string>("name")
        const pictureUrl = row.original.picture_url
        return (
          <div className="flex items-center gap-2">
            <Avatar className="size-7">
              <AvatarImage src={pictureUrl ?? undefined} alt={name} />
              <AvatarFallback className="text-xs">
                {name.slice(0, 2).toUpperCase() || (
                  <UserIcon className="size-3" />
                )}
              </AvatarFallback>
            </Avatar>
            <span className="font-medium">{name}</span>
          </div>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "name") as ColumnSchema
      ),
    },
    {
      accessorKey: "email",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Email" />
      ),
      cell: ({ row }) => (
        <span className="text-sm text-muted-foreground">
          {row.getValue("email") ?? "—"}
        </span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "email") as ColumnSchema
      ),
    },
    {
      accessorKey: "created_at",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Created At" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string | null>("created_at")
        if (!value)
          return <span className="text-sm text-muted-foreground">—</span>
        return (
          <span className="text-sm text-muted-foreground">
            {formatDate(value, { dateStyle: "medium" })}
          </span>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "created_at") as ColumnSchema
      ),
    },
    {
      accessorKey: "updated_at",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Updated At" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string | null>("updated_at")
        if (!value)
          return <span className="text-sm text-muted-foreground">—</span>
        return (
          <span className="text-sm text-muted-foreground">
            {formatDate(value, { dateStyle: "medium" })}
          </span>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "updated_at") as ColumnSchema
      ),
    },
  ]
}
