import type * as React from "react"

import type { ReactTable, RowData } from "@tanstack/react-table"

import { cn } from "cn"

import { DataTableViewOptions } from "#/components/data-table/data-table-view-options"
import type { DataTableFeatures } from "#/lib/data-table-features"

interface DataTableAdvancedToolbarProps<
  TData extends RowData,
> extends React.ComponentProps<"div"> {
  table: ReactTable<DataTableFeatures, TData, unknown>
  hideViewOptions?: boolean
}

export function DataTableAdvancedToolbar<TData extends RowData>({
  table,
  hideViewOptions,
  children,
  className,
  ...props
}: DataTableAdvancedToolbarProps<TData>) {
  return (
    <div
      data-slot="data-table-advanced-toolbar"
      className={cn(
        "flex w-full items-start justify-between gap-2 p-1",
        className
      )}
      {...props}
    >
      <div className="flex flex-1 flex-wrap items-center gap-2">{children}</div>
      {!hideViewOptions && (
        <div className="flex items-center gap-2">
          <DataTableViewOptions table={table} align="end" />
        </div>
      )}
    </div>
  )
}
