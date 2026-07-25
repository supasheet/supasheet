import type { ReactNode } from "react"

import type { Table } from "@tanstack/react-table"
import { flexRender } from "@tanstack/react-table"

import {
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  Table as TableRoot,
  TableRow,
} from "#/components/ui/table"
import { cn } from "#/lib/utils"

import { DataTableFooter } from "./data-table-footer"
import { DataTablePagination } from "./data-table-pagination"

interface DataTableProps<TData> {
  table: Table<TData>
  className?: string
  children?: ReactNode
}

export function DataTable<TData>({
  table,
  className,
  children,
}: DataTableProps<TData>) {
  const colCount = table.getAllColumns().length

  return (
    <div className={cn("flex w-full flex-col gap-2", className)}>
      {children}
      <div className="overflow-auto rounded-md border bg-card">
        <TableRoot>
          <TableHeader>
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(
                          header.column.columnDef.header,
                          header.getContext()
                        )}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  data-state={row.getIsSelected() && "selected"}
                  className="group"
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext()
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell colSpan={colCount} className="h-24 text-center">
                  No results.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
          <DataTableFooter table={table} />
        </TableRoot>
      </div>
      <DataTablePagination table={table} />
    </div>
  )
}
