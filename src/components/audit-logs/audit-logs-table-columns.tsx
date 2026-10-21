import { Link } from "@tanstack/react-router"

import { AlertCircleIcon, ArrowUpRightIcon } from "lucide-react"

import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { getDataTableSelectColumn } from "#/components/data-table/data-table-select-column"
import { Badge } from "#/components/ui/badge"
import { getColumnDefMeta } from "#/lib/columns"
import type { DataTableColumnDef } from "#/lib/data-table-types"
import type { ColumnSchema } from "#/lib/database-meta.types"
import type { Database } from "#/lib/database.types"
import { formatDate } from "#/lib/format"

export type AuditLog = Database["supasheet"]["Tables"]["audit_logs"]["Row"]

export function getAuditLogsTableColumns({
  columnsSchema,
}: {
  columnsSchema: ColumnSchema<"supasheet">[]
}): DataTableColumnDef<AuditLog>[] {
  return [
    getDataTableSelectColumn<AuditLog>(),
    {
      id: "detail",
      header: () => null,
      cell: ({ row }) => (
        <Link
          to="/core/audit_logs/$auditLogId"
          params={{ auditLogId: row.original.id }}
          className="inline-flex rounded border p-0.5 opacity-0 transition-opacity group-hover:opacity-100"
          onClick={(e) => e.stopPropagation()}
        >
          <ArrowUpRightIcon className="size-3" />
        </Link>
      ),
      size: 40,
      enableSorting: false,
      enableHiding: false,
    },
    {
      accessorKey: "id",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="ID" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-xs text-muted-foreground">
          {row.original.id.slice(0, 8)}…
        </span>
      ),
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "id") as ColumnSchema
      ),
    },
    {
      accessorKey: "created_at",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Created At" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string>("created_at")
        return (
          <span className="text-sm text-muted-foreground">
            {formatDate(value, { dateStyle: "medium", timeStyle: "short" })}
          </span>
        )
      },
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "created_at") as ColumnSchema
      ),
    },
    {
      accessorKey: "operation",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Operation" />
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
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "operation") as ColumnSchema
      ),
    },
    {
      accessorKey: "schema_name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Schema" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-sm text-muted-foreground">
          {row.getValue("schema_name")}
        </span>
      ),
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "schema_name") as ColumnSchema
      ),
    },
    {
      accessorKey: "table_name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Table" />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-sm">{row.getValue("table_name")}</span>
      ),
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "table_name") as ColumnSchema
      ),
    },
    {
      accessorKey: "record_id",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Record ID" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string | null>("record_id")
        return (
          <span className="font-mono text-sm text-muted-foreground">
            {value ?? "—"}
          </span>
        )
      },
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "record_id") as ColumnSchema
      ),
    },
    {
      accessorKey: "role",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Role" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string | null>("role")
        if (!value)
          return <span className="text-sm text-muted-foreground">—</span>
        return <Badge variant="outline">{value}</Badge>
      },
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "role") as ColumnSchema
      ),
    },
    {
      accessorKey: "user_type",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="User Type" />
      ),
      cell: ({ row }) => {
        const value = row.getValue<string>("user_type")
        return (
          <Badge variant={value === "system" ? "secondary" : "outline"}>
            {value}
          </Badge>
        )
      },
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "user_type") as ColumnSchema
      ),
    },
    {
      accessorKey: "is_error",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label="Error" />
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
      enableColumnFilter: true,
      meta: getColumnDefMeta(
        null,
        columnsSchema.find((col) => col.name === "is_error") as ColumnSchema
      ),
    },
  ]
}
