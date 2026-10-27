import * as React from "react"

import { useCreateAtom, useSelector } from "@tanstack/react-store"
import type { Atom } from "@tanstack/react-store"
import { useTable } from "@tanstack/react-table"
import type {
  ColumnDef,
  ColumnFiltersState,
  PaginationState,
  RowData,
  SortingState,
  TableOptions,
} from "@tanstack/react-table"

import { dataTableFeatures } from "#/lib/data-table-features"
import type { DataTableFeatures } from "#/lib/data-table-features"
import { DEFAULT_PAGE_SIZE } from "#/lib/data-table-search"
import type { TableQuery } from "#/lib/data-table-search"
import type {
  ColumnSortItem,
  FilterVariant,
  JoinOperator,
} from "#/lib/data-table-types"
import { getActiveFilters, normalizeColumnFilter } from "#/lib/data-table-utils"

export interface LocalTableState {
  pagination: Atom<PaginationState>
  sorting: Atom<SortingState>
  columnFilters: Atom<ColumnFiltersState>
  joinOperator: Atom<JoinOperator>
}

/**
 * Table state kept in external atoms instead of the URL, for tables embedded in
 * sheets/dialogs/tabs where URL-synced state would clash with the page's own.
 * Returns the `TableQuery` to fetch with, and the atoms to hand to
 * `useLocalDataTable` once the data is available. The table owns the atoms, so
 * it writes to them directly.
 */
export function useLocalTableState<TData extends RowData>(
  columns: ColumnDef<DataTableFeatures, TData, unknown>[],
  initialPageSize = DEFAULT_PAGE_SIZE
) {
  const pagination = useCreateAtom<PaginationState>({
    pageIndex: 0,
    pageSize: initialPageSize,
  })
  const sorting = useCreateAtom<SortingState>([])
  const columnFilters = useCreateAtom<ColumnFiltersState>([])
  const joinOperator = useCreateAtom<JoinOperator>("and")

  React.useEffect(() => {
    const subscription = columnFilters.subscribe(() => {
      pagination.set((old) => ({ ...old, pageIndex: 0 }))
    })
    return () => subscription.unsubscribe()
  }, [columnFilters, pagination])

  const variantById = React.useMemo(
    () =>
      Object.fromEntries(
        columns.flatMap((column) =>
          column.id ? [[column.id, column.meta?.variant]] : []
        )
      ) as Record<string, FilterVariant | undefined>,
    [columns]
  )

  const paginationValue = useSelector(pagination)
  const sortingValue = useSelector(sorting)
  const columnFiltersValue = useSelector(columnFilters)
  const joinOperatorValue = useSelector(joinOperator)

  const state = React.useMemo<LocalTableState>(
    () => ({ pagination, sorting, columnFilters, joinOperator }),
    [pagination, sorting, columnFilters, joinOperator]
  )

  const query = React.useMemo<TableQuery>(
    () => ({
      page: paginationValue.pageIndex + 1,
      perPage: paginationValue.pageSize,
      sorting: sortingValue as ColumnSortItem[],
      filters: getActiveFilters(
        columnFiltersValue.map((filter) =>
          normalizeColumnFilter(filter, variantById[filter.id] ?? "text")
        )
      ),
      joinOperator: joinOperatorValue,
    }),
    [
      paginationValue,
      sortingValue,
      columnFiltersValue,
      joinOperatorValue,
      variantById,
    ]
  )

  return { query, state }
}

type UseLocalDataTableProps<TData extends RowData> = Omit<
  TableOptions<DataTableFeatures, TData>,
  | "atoms"
  | "state"
  | "features"
  | "manualFiltering"
  | "manualPagination"
  | "manualSorting"
  | "pageCount"
> & {
  tableState: LocalTableState
  pageCount: number
}

export function useLocalDataTable<TData extends RowData>({
  tableState,
  pageCount,
  ...props
}: UseLocalDataTableProps<TData>) {
  const table = useTable(
    {
      ...props,
      features: dataTableFeatures,
      enableColumnResizing: true,
      columnResizeMode: "onChange",
      pageCount,
      atoms: tableState,
      manualPagination: true,
      manualSorting: true,
      manualFiltering: true,
    },
    (state) => ({
      columnFilters: state.columnFilters,
      joinOperator: state.joinOperator,
      pagination: state.pagination,
      sorting: state.sorting,
    })
  )

  return React.useMemo(() => ({ table }), [table])
}
