import { useCallback, useMemo, useState } from "react"
import type { ReactNode } from "react"

import type { Table } from "@tanstack/react-table"
import { flexRender } from "@tanstack/react-table"

import type { Column, RowsChangeData } from "react-data-grid"

import { DataGrid as ReactDataGrid } from "#/components/ui/data-grid"
import { cn } from "#/lib/utils"

import { DataTablePagination } from "../data-table/data-table-pagination"
import { getEditCell } from "./data-grid-edit-cell"

type GridRow = Record<string, unknown>

interface DataGridProps<TData> {
  table: Table<TData>
  isEditable?: boolean
  onRowsChange?: (rows: GridRow[], data: RowsChangeData<GridRow>) => void
  className?: string
  children?: ReactNode
}

export function DataGrid<TData>({
  table,
  isEditable = true,
  onRowsChange,
  className,
  children,
}: DataGridProps<TData>) {
  const rowModel = table.getRowModel()
  const gridRows = useMemo(
    () => rowModel.rows.map((row) => row.original as GridRow),
    [rowModel.rows]
  )

  // Sync local rows from external data (e.g. after query refetch) without useEffect
  const [prevGridRows, setPrevGridRows] = useState(gridRows)
  const [localRows, setLocalRows] = useState<GridRow[]>(gridRows)
  if (prevGridRows !== gridRows) {
    setPrevGridRows(gridRows)
    setLocalRows(gridRows)
  }

  const gridColumns: Column<GridRow>[] = table
    .getHeaderGroups()
    .flatMap((headerGroup) =>
      headerGroup.headers.map((header) => {
        const meta = header.column.columnDef.meta
        return {
          key: header.id,
          name: header.id,
          renderHeaderCell: () =>
            header.isPlaceholder
              ? null
              : flexRender(header.column.columnDef.header, header.getContext()),
          renderEditCell: isEditable ? getEditCell(meta) : undefined,
        }
      })
    )

  const handleRowsChange = useCallback(
    (rows: GridRow[], changeData: RowsChangeData<GridRow>) => {
      setLocalRows(rows)
      onRowsChange?.(rows, changeData)
    },
    [onRowsChange]
  )

  return (
    <div className={cn("flex w-full flex-col gap-2", className)}>
      {children}
      <ReactDataGrid
        className="h-min! overflow-auto!"
        columns={gridColumns}
        rows={localRows}
        onRowsChange={handleRowsChange}
        defaultColumnOptions={{ resizable: true }}
        renderers={{
          noRowsFallback: (
            <div className="col-span-full py-12 text-center">No Results.</div>
          ),
        }}
      />
      <DataTablePagination table={table} />
    </div>
  )
}
