import { startTransition, useCallback, useState } from "react"

import { useNavigate } from "@tanstack/react-router"

import type {
  ColumnDef,
  ColumnFiltersState,
  PaginationState,
  Row,
  RowSelectionState,
  SortingState,
  Updater,
  VisibilityState,
} from "@tanstack/react-table"
import { getCoreRowModel, useReactTable } from "@tanstack/react-table"

interface UseDataTableOptions<TData, TValue> {
  columns: ColumnDef<TData, TValue>[]
  data: TData[]
  pageCount: number
  state?: {
    sorting?: SortingState
    pagination?: PaginationState
    columnFilters?: ColumnFiltersState
  }
  getRowId?:
    | ((
        originalRow: TData,
        index: number,
        parent?: Row<TData> | undefined
      ) => string)
    | undefined
  meta?: { filename?: string }
}

export function useDataTable<TData, TValue>({
  columns,
  data,
  pageCount,
  state,
  getRowId,
  meta,
}: UseDataTableOptions<TData, TValue>) {
  const sorting = state?.sorting ?? []
  const pagination = state?.pagination ?? { pageIndex: 0, pageSize: 20 }
  const columnFilters = state?.columnFilters ?? []

  const [rowSelection, setRowSelection] = useState<RowSelectionState>({})
  const [columnVisibility, setColumnVisibility] = useState<VisibilityState>({})

  const navigate = useNavigate()

  const onSortingChange = useCallback(
    (updater: Updater<SortingState>) => {
      const next = typeof updater === "function" ? updater(sorting) : updater
      const first = next[0] as SortingState[0] | undefined
      startTransition(() => {
        navigate({
          to: ".",
          search: (prev) => ({
            ...prev,
            sortId: first?.id,
            sortDesc: first?.desc,
            page: 1,
          }),
          replace: true,
        })
      })
    },
    [sorting, navigate]
  )

  const onPaginationChange = useCallback(
    (updater: Updater<PaginationState>) => {
      const next = typeof updater === "function" ? updater(pagination) : updater
      startTransition(() => {
        navigate({
          to: ".",
          search: (prev) => ({
            ...prev,
            page: next.pageIndex + 1,
            pageSize: next.pageSize,
          }),
          replace: true,
        })
      })
    },
    [pagination, navigate]
  )

  const onColumnFiltersChange = useCallback(
    (updater: Updater<ColumnFiltersState>) => {
      const next =
        typeof updater === "function" ? updater(columnFilters) : updater
      startTransition(() => {
        navigate({
          to: ".",
          search: (prev) => ({
            ...prev,
            filters: next.length ? next : undefined,
            page: 1,
          }),
          replace: true,
        })
      })
    },
    [columnFilters, navigate]
  )

  const table = useReactTable({
    data,
    columns,
    pageCount,
    state: {
      rowSelection,
      columnVisibility,
      sorting,
      pagination,
      columnFilters,
    },
    getRowId,
    onRowSelectionChange: setRowSelection,
    onColumnVisibilityChange: setColumnVisibility,
    onSortingChange,
    onPaginationChange,
    onColumnFiltersChange,
    manualSorting: true,
    manualPagination: true,
    manualFiltering: true,
    getCoreRowModel: getCoreRowModel(),
    meta,
  })

  return table
}
