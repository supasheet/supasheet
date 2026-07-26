import { useState } from "react"

import type { Table } from "@tanstack/react-table"

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "#/components/ui/select"
import { TableCell, TableFooter, TableRow } from "#/components/ui/table"
import {
  AGGREGATE_FUNCTION_LABELS,
  computeAggregate,
  formatAggregateValue,
  getAvailableAggregates,
} from "#/lib/aggregate"
import type { AggregateFunction } from "#/lib/database-meta.types"

interface DataTableFooterProps<TData> {
  table: Table<TData>
}

export function DataTableFooter<TData>({ table }: DataTableFooterProps<TData>) {
  const columns = table
    .getAllLeafColumns()
    .filter((column) => column.getIsVisible())
  const aggregatableColumns = columns.filter(
    (column) => !!column.columnDef.meta
  )

  const [selected, setSelected] = useState<Record<string, AggregateFunction>>(
    () =>
      Object.fromEntries(
        aggregatableColumns.map((column) => [
          column.id,
          column.columnDef.meta?.aggregate ?? "none",
        ])
      )
  )

  if (!aggregatableColumns.length) return null

  const rows = table.getRowModel().rows

  return (
    <TableFooter>
      <TableRow>
        {columns.map((column) => {
          const meta = column.columnDef.meta
          if (!meta) return <TableCell key={column.id} className="h-10" />

          const fn = selected[column.id] ?? "none"
          const values = rows.map((row) => row.getValue(column.id))
          const result = computeAggregate(values, fn, meta.variant)

          return (
            <TableCell key={column.id} className="h-10">
              <div className="flex items-center gap-1.5">
                <Select
                  value={fn}
                  onValueChange={(value) =>
                    setSelected((prev) => ({
                      ...prev,
                      [column.id]: value as AggregateFunction,
                    }))
                  }
                >
                  <SelectTrigger
                    size="sm"
                    className="h-6 shrink-0 border-none bg-transparent px-1 text-xs text-muted-foreground shadow-none hover:bg-muted"
                  >
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {getAvailableAggregates(meta.variant).map((availableFn) => (
                      <SelectItem key={availableFn} value={availableFn}>
                        {AGGREGATE_FUNCTION_LABELS[availableFn]}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {fn !== "none" && (
                  <span className="truncate text-xs font-medium">
                    {formatAggregateValue(result)}
                  </span>
                )}
              </div>
            </TableCell>
          )
        })}
      </TableRow>
    </TableFooter>
  )
}
