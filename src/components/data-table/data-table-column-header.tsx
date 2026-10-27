import * as React from "react"

import {
  type Column,
  type RowData,
  type SortDirection,
  type SortingState,
  Subscribe,
} from "@tanstack/react-table"

import { cn } from "cn"
import { ChevronDown, ChevronUp, ChevronsUpDown, EyeOff } from "lucide-react"

import { useDirection } from "#/components/ui/direction"
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type { DataTableFeatures } from "#/lib/data-table-features"

interface DataTableColumnHeaderProps<
  TData extends RowData,
  TValue,
> extends React.ComponentProps<typeof DropdownMenuTrigger> {
  column: Column<DataTableFeatures, TData, TValue>
  label: string
}

export function DataTableColumnHeader<TData extends RowData, TValue>({
  column,
  label,
  className,
  ...props
}: DataTableColumnHeaderProps<TData, TValue>) {
  if (!column.getCanSort() && !column.getCanHide()) {
    return <div className={cn(className)}>{label}</div>
  }

  return (
    <Subscribe
      source={column.table.store}
      selector={(state) => ({
        isVisible: state.columnVisibility[column.id] !== false,
        sortDirection: getSortDirection(state.sorting, column.id),
      })}
    >
      {(headerState) => (
        <DataTableColumnHeaderMenu
          column={column}
          label={label}
          className={className}
          isVisible={headerState.isVisible}
          sortDirection={headerState.sortDirection}
          {...props}
        />
      )}
    </Subscribe>
  )
}

interface DataTableColumnHeaderMenuProps<
  TData extends RowData,
  TValue,
> extends DataTableColumnHeaderProps<TData, TValue> {
  isVisible: boolean
  sortDirection: SortDirection | "none"
}

function DataTableColumnHeaderMenu<TData extends RowData, TValue>({
  column,
  label,
  className,
  isVisible,
  sortDirection,
  ...props
}: DataTableColumnHeaderMenuProps<TData, TValue>) {
  const dir = useDirection()

  function onSortDirectionChange(direction: SortDirection) {
    if (sortDirection === direction) {
      column.clearSorting()
      return
    }

    column.toggleSorting(direction === "desc", true)
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          "flex items-center gap-2 truncate [&_svg]:size-3.5 [&_svg]:shrink-0 [&_svg]:text-muted-foreground",
          className
        )}
        {...props}
      >
        {label}
        {column.getCanSort() &&
          (sortDirection === "desc" ? (
            <ChevronDown />
          ) : sortDirection === "asc" ? (
            <ChevronUp />
          ) : (
            <ChevronsUpDown />
          ))}
      </DropdownMenuTrigger>
      <DropdownMenuContent
        dir={dir}
        align="start"
        className="w-28 data-closed:fill-mode-forwards"
      >
        {column.getCanSort() && (
          <>
            <DropdownMenuCheckboxItem
              className="[&_svg]:text-muted-foreground"
              checked={sortDirection === "asc"}
              onClick={() => onSortDirectionChange("asc")}
            >
              <ChevronUp />
              Asc
            </DropdownMenuCheckboxItem>
            <DropdownMenuCheckboxItem
              className="[&_svg]:text-muted-foreground"
              checked={sortDirection === "desc"}
              onClick={() => onSortDirectionChange("desc")}
            >
              <ChevronDown />
              Desc
            </DropdownMenuCheckboxItem>
          </>
        )}
        {column.getCanHide() && (
          <DropdownMenuCheckboxItem
            className="[&_svg]:text-muted-foreground"
            checked={!isVisible}
            onClick={() => column.toggleVisibility(false)}
          >
            <EyeOff />
            Hide
          </DropdownMenuCheckboxItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function getSortDirection(
  sorting: SortingState,
  columnId: string
): SortDirection | "none" {
  const sort = sorting.find((sort) => sort.id === columnId)
  if (!sort) return "none"
  return sort.desc ? "desc" : "asc"
}
