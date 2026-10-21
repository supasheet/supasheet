import { useState } from "react"

import { Subscribe } from "@tanstack/react-table"
import type { RowData } from "@tanstack/react-table"

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
import type { DataTableInstance } from "#/lib/data-table-types"
import type { AggregateFunction } from "#/lib/database-meta.types"

interface DataTableFooterProps<TData extends RowData> {
  table: DataTableInstance<TData>
}

/**
 * Per-column aggregates (sum, avg, ...) for columns that carry Supasheet
 * column metadata. Renders nothing for tables without it.
 */
export function DataTableFooter<TData extends RowData>({
  table,
}: DataTableFooterProps<TData>) {
  if (!table.getAllLeafColumns().some((column) => column.columnDef.meta?.field))
    return null

  return (
    <Subscribe source={table.atoms.columnVisibility}>
      {() => <FooterRow table={table} />}
    </Subscribe>
  )
}

function FooterRow<TData extends RowData>({
  table,
}: DataTableFooterProps<TData>) {
  const columns = table
    .getAllLeafColumns()
    .filter((column) => column.getIsVisible())

  const [selected, setSelected] = useState<Record<string, AggregateFunction>>(
    () =>
      Object.fromEntries(
        table
          .getAllLeafColumns()
          .map((column) => [
            column.id,
            column.columnDef.meta?.field?.aggregate ?? "none",
          ])
      )
  )

  const rows = table.getRowModel().rows

  return (
    <TableFooter>
      <TableRow className="h-10">
        {columns.map((column) => {
          const field = column.columnDef.meta?.field
          if (!field) return <TableCell key={column.id} className="h-10" />

          const fn = selected[column.id] ?? "none"
          const values = rows.map((row) => row.getValue(column.id))
          const result = computeAggregate(values, fn, field.variant)

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
                    className="h-6! shrink-0 border-none bg-transparent px-1 text-xs text-muted-foreground shadow-none hover:bg-muted"
                  >
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {getAvailableAggregates(field.variant).map(
                      (availableFn) => (
                        <SelectItem key={availableFn} value={availableFn}>
                          {AGGREGATE_FUNCTION_LABELS[availableFn]}
                        </SelectItem>
                      )
                    )}
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
