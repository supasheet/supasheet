import { useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import type {
  ColumnFiltersState,
  PaginationState,
  SortingState,
} from "@tanstack/react-table"

import { toast } from "sonner"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableActionBar } from "#/components/data-table/data-table-action-bar"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasRole } from "#/hooks/use-permissions"
import type { ColumnSchema } from "#/lib/database-meta.types"
import { adminDeleteUserMutationOptions } from "#/lib/supabase/data/admin-auth"

import { getUsersTableColumns } from "./users-table-columns"
import type { User } from "./users-table-columns"

interface UsersTableProps {
  data: User[]
  columnsSchema: ColumnSchema<"supasheet">[]
  sorting: SortingState
  pagination: PaginationState
  columnFilters: ColumnFiltersState
  pageCount: number
}

export function UsersTable({
  data,
  columnsSchema,
  sorting,
  pagination,
  columnFilters,
  pageCount,
}: UsersTableProps) {
  const queryClient = useQueryClient()
  const canDelete = useHasRole("x-admin")
  const canUpdate = useHasRole("x-admin")
  const canViewAll = useHasRole("x-admin")
  const columns = useMemo(
    () => getUsersTableColumns({ columnsSchema, canUpdate, canViewAll }),
    [columnsSchema, canUpdate, canViewAll]
  )
  const table = useDataTable({
    columns,
    data,
    pageCount,
    state: { sorting, pagination, columnFilters },
    meta: { filename: "users" },
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
    <DataTable table={table}>
      <DataTableToolbar table={table} />
      <DataTableActionBar
        table={table}
        onDelete={canDelete ? handleDelete : undefined}
      />
    </DataTable>
  )
}
