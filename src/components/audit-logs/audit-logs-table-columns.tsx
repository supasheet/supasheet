import { Link } from "@tanstack/react-router"

import type { ColumnDef } from "@tanstack/react-table"

import { AlertCircleIcon, ArrowUpRightIcon } from "lucide-react"

import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { Badge } from "#/components/ui/badge"
import { Checkbox } from "#/components/ui/checkbox"
import { getColumnMetadata } from "#/lib/columns"
import type { ColumnSchema } from "#/lib/database-meta.types"
import type { Database } from "#/lib/database.types"
import { formatDate } from "#/lib/format"

export type AuditLog = Database["supasheet"]["Tables"]["audit_logs"]["Row"]

export function getAuditLogsTableColumns({
  columnsSchema,
}: {
  columnsSchema: ColumnSchema<"supasheet">[]
}): ColumnDef<AuditLog, unknown>[] {
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
          <Link
            to="/core/audit_logs/$auditLogId"
            params={{ auditLogId: row.original.id }}
            className="inline-flex rounded border p-0.5 opacity-0 transition-opacity group-hover:opacity-100"
            onClick={(e) => e.stopPropagation()}
          >
            <ArrowUpRightIcon className="size-3" />
          </Link>
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
          {row.original.id.slice(0, 8)}…
        </span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "id") as ColumnSchema
      ),
    },
    {
      accessorKey: "created_at",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Created At" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string>("created_at")
        return (
          <span className="text-sm text-muted-foreground">
            {formatDate(value, { dateStyle: "medium", timeStyle: "short" })}
          </span>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "created_at") as ColumnSchema
      ),
    },
    {
      accessorKey: "operation",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Operation" />
      ),
      cell: ({ row }) => {
        const op = row.getValue<string>("operation")
        const variant =
          op === "INSERT"
            ? "default"
            : op === "UPDATE"
              ? "secondary"
              : op === "DELETE"
                ? "destructive"
                : "outline"
        return <Badge variant={variant}>{op}</Badge>
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "operation") as ColumnSchema
      ),
    },
    {
      accessorKey: "schema_name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Schema" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-sm text-muted-foreground">
          {row.getValue("schema_name")}
        </span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "schema_name") as ColumnSchema
      ),
    },
    {
      accessorKey: "table_name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Table" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-sm">{row.getValue("table_name")}</span>
      ),
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "table_name") as ColumnSchema
      ),
    },
    {
      accessorKey: "record_id",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Record ID" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string | null>("record_id")
        return (
          <span className="font-mono text-sm text-muted-foreground">
            {value ?? "—"}
          </span>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "record_id") as ColumnSchema
      ),
    },
    {
      accessorKey: "role",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Role" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string | null>("role")
        if (!value)
          return <span className="text-sm text-muted-foreground">—</span>
        return <Badge variant="outline">{value}</Badge>
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "role") as ColumnSchema
      ),
    },
    {
      accessorKey: "user_type",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="User Type" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string>("user_type")
        return (
          <Badge variant={value === "system" ? "secondary" : "outline"}>
            {value}
          </Badge>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "user_type") as ColumnSchema
      ),
    },
    {
      accessorKey: "is_error",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Error" />
      ),
      cell: ({ row }) => {
        const isError = row.getValue("is_error")
        if (!isError)
          return <span className="text-sm text-muted-foreground">—</span>
        return (
          <div className="flex items-center gap-1 text-destructive">
            <AlertCircleIcon className="size-4" />
            <span className="text-sm font-medium">Error</span>
          </div>
        )
      },
      meta: getColumnMetadata(
        null,
        columnsSchema.find((col) => col.name === "is_error") as ColumnSchema
      ),
    },
  ]
}
