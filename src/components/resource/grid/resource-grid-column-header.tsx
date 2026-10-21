import { memo } from "react"

import type { RowData } from "@tanstack/react-table"

import { ChevronDown, ChevronUp, ChevronsUpDown, EyeOff, X } from "lucide-react"

import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type { DataTableColumn } from "#/lib/data-table-types"
import type { ColumnSchema, TableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { cn } from "#/lib/utils"

export const ResourceGridColumnHeader = memo(function <
  TData extends RowData,
  TValue,
>({
  column,
  title,
  className,
  isSorted,
}: {
  column: DataTableColumn<TData, TValue>
  title: string
  className?: string
  isSorted: false | "asc" | "desc"
}) {
  if (!column.getCanSort() && !column.getCanHide()) {
    return (
      <div className={cn("flex items-center gap-2 truncate", className)}>
        {column.columnDef.meta?.field?.icon && (
          <span className="shrink-0">{column.columnDef.meta.field?.icon}</span>
        )}
        {formatTitle(title)}
      </div>
    )
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          "flex items-center gap-2 truncate [&_svg]:size-3.5 [&_svg]:shrink-0 [&_svg]:text-muted-foreground",
          className
        )}
      >
        {column.columnDef.meta?.field?.icon && (
          <span className="shrink-0">{column.columnDef.meta.field?.icon}</span>
        )}
        <span className="truncate">{formatTitle(title)}</span>
        {column.getCanSort() &&
          (isSorted === "desc" ? (
            <ChevronDown />
          ) : isSorted === "asc" ? (
            <ChevronUp />
          ) : (
            <ChevronsUpDown />
          ))}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-28">
        {column.getCanSort() && (
          <>
            <DropdownMenuCheckboxItem
              checked={isSorted === "asc"}
              onClick={() => column.toggleSorting(false)}
            >
              <ChevronUp />
              Asc
            </DropdownMenuCheckboxItem>
            <DropdownMenuCheckboxItem
              checked={isSorted === "desc"}
              onClick={() => column.toggleSorting(true)}
            >
              <ChevronDown />
              Desc
            </DropdownMenuCheckboxItem>
            {isSorted && (
              <DropdownMenuItem onClick={() => column.clearSorting()}>
                <X />
                Reset
              </DropdownMenuItem>
            )}
          </>
        )}
        {column.getCanHide() && (
          <DropdownMenuCheckboxItem
            checked={!column.getIsVisible()}
            onClick={() => column.toggleVisibility(false)}
          >
            <EyeOff />
            Hide
          </DropdownMenuCheckboxItem>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}) as <TData extends RowData, TValue>(props: {
  column: DataTableColumn<TData, TValue>
  title: string
  className?: string
  tableSchema: TableSchema | null
  columnSchema: ColumnSchema
  isSorted: false | "asc" | "desc"
}) => React.ReactElement
