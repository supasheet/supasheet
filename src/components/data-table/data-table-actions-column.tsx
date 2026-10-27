import type * as React from "react"

import type {
  CellContext,
  ColumnDef,
  Row,
  RowData,
} from "@tanstack/react-table"

import { Ellipsis } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type { DataTableFeatures } from "#/lib/data-table-features"

interface GetDataTableActionsColumnOptions<TData extends RowData> extends Omit<
  Partial<ColumnDef<DataTableFeatures, TData>>,
  "id" | "header" | "cell"
> {
  actions: (context: CellContext<DataTableFeatures, TData>) => React.ReactNode
  getAriaLabel?: (row: Row<DataTableFeatures, TData>) => string
}

export function getDataTableActionsColumn<TData extends RowData>({
  actions,
  getAriaLabel = (row) => `Open actions for row ${row.getDisplayIndex() + 1}`,
  size = 48,
  enableHiding = false,
  enableSorting = false,
  enableResizing = false,
  ...props
}: GetDataTableActionsColumnOptions<TData>): ColumnDef<
  DataTableFeatures,
  TData
> {
  return {
    id: "actions",
    header: () => <span className="sr-only">Actions</span>,
    cell: (context) => (
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button
              aria-label={getAriaLabel(context.row)}
              variant="ghost"
              size="icon-sm"
              className="text-muted-foreground data-popup-open:bg-accent"
            />
          }
        >
          <Ellipsis />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {actions(context)}
        </DropdownMenuContent>
      </DropdownMenu>
    ),
    size,
    enableHiding,
    enableSorting,
    enableResizing,
    ...props,
  }
}
