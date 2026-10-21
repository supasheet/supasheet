import { useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableBulkActions } from "#/components/data-table/data-table-bulk-actions"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasRole } from "#/hooks/use-permissions"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type { ColumnSchema } from "#/lib/database-meta.types"
import { adminDeleteUserMutationOptions } from "#/lib/supabase/data/admin-auth"

import { getUsersTableColumns } from "./users-table-columns"
import type { User } from "./users-table-columns"

interface UsersTableProps {
  data: User[]
  columnsSchema: ColumnSchema<"supasheet">[]
  pageCount: number
}

export function UsersTable({
  data,
  columnsSchema,
  pageCount,
}: UsersTableProps) {
  const queryClient = useQueryClient()
  const canDelete = useHasRole("x-admin")
  const canViewAll = useHasRole("x-admin")
  const columns = useMemo(
    () => getUsersTableColumns({ columnsSchema, canViewAll }),
    [columnsSchema, canViewAll]
  )
  const { table } = useDataTable({
    columns,
    data,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
    getRowId: (row) => row.id,
  })

  const { mutateAsync: deleteUser } = useMutation(
    adminDeleteUserMutationOptions
  )

  const handleDelete = async (rows: User[]) => {
    try {
      await Promise.all(rows.map((r) => deleteUser(r.id)))
      queryClient.invalidateQueries({ queryKey: ["supasheet", "users"] })
      queryClient.invalidateQueries({ queryKey: ["admin", "auth", "users"] })
      toast.success(
        rows.length === 1 ? "User deleted" : `${rows.length} users deleted`
      )
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to delete users")
    }
  }

  return (
    <DataTable
      table={table}
      actionBar={
        <DataTableBulkActions
          table={table}
          filename="users"
          onDelete={canDelete ? handleDelete : undefined}
        />
      }
    >
      <DataTableToolbar table={table}>
        <DataTableExportButton table={table} filename="users" />
      </DataTableToolbar>
    </DataTable>
  )
}
