import { useMemo, useState } from "react"

import { useQuery } from "@tanstack/react-query"

import type { ColumnFiltersState, SortingState } from "@tanstack/react-table"
import { getCoreRowModel, useReactTable } from "@tanstack/react-table"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "#/components/ui/sheet"
import { useIsMobile } from "#/hooks/use-mobile"
import type {
  Relationship,
  ResourceDataSchema,
} from "#/lib/database-meta.types"
import {
  columnsSchemaQueryOptions,
  resourceDataQueryOptions,
} from "#/lib/supabase/data/resource"
import { cn } from "#/lib/utils"

import { foreignTableColumns } from "./foreign-table-columns"

type ForeignTableSheetProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  relationship: Relationship
  setRecord: (record: ResourceDataSchema) => void
}

export function ForeignTableSheet({
  relationship,
  setRecord,
  open,
  onOpenChange,
}: ForeignTableSheetProps) {
  const isMobile = useIsMobile()
  const side = isMobile ? "bottom" : "right"

  const [pagination, setPagination] = useState({
    pageIndex: 0,
    pageSize: 20,
  })

  const [sorting, setSorting] = useState<SortingState>([])
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>([])

  const sortCol = sorting[0]

  const { data } = useQuery(
    resourceDataQueryOptions(
      relationship.target_table_schema,
      relationship.target_table_name,
      {},
      pagination.pageIndex + 1,
      pagination.pageSize,
      sortCol?.id,
      sortCol?.desc,
      columnFilters
    )
  )

  const { data: columnsSchema } = useQuery(
    columnsSchemaQueryOptions(
      relationship.target_table_schema,
      relationship.target_table_name
    )
  )

  const columns = useMemo(
    () =>
      foreignTableColumns({
        columnsSchema: columnsSchema ?? [],
        setRecord,
      }),
    [columnsSchema, setRecord]
  )

  const table = useReactTable({
    data: data?.result ?? [],
    columns,
    state: {
      pagination,
      sorting,
      columnFilters,
    },
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    onPaginationChange: setPagination,
    getCoreRowModel: getCoreRowModel(),
    manualPagination: true,
    manualSorting: true,
    manualFiltering: true,
    rowCount: data?.count ?? 0,
    enableRowSelection: false,
  })

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side={side}
        className={cn(
          "gap-0",
          side === "right" && "w-full! sm:max-w-lg!",
          side === "bottom" && "max-h-[80vh] overflow-hidden"
        )}
      >
        <SheetHeader className="border-b">
          <SheetTitle>
            Select to reference from {relationship.target_table_name}
          </SheetTitle>
          <SheetDescription>
            Select a record from the table to create a reference.
          </SheetDescription>
        </SheetHeader>
        {columnsSchema && !columnsSchema.length ? (
          <div className="flex flex-1 items-center justify-center p-4">
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <circle cx="12" cy="12" r="10" />
                    <line x1="12" y1="8" x2="12" y2="12" />
                    <line x1="12" y1="16" x2="12.01" y2="16" />
                  </svg>
                </EmptyMedia>
                <EmptyTitle>Access denied</EmptyTitle>
              </EmptyHeader>
              <EmptyContent>
                <EmptyDescription>
                  You don&apos;t have permission to access this table.
                </EmptyDescription>
              </EmptyContent>
            </Empty>
          </div>
        ) : (
          <div className="flex min-h-0 flex-1 flex-col gap-2 p-4">
            <DataTable
              table={table}
              className="flex-1 min-h-0 [&>div:nth-child(2)]:flex-1 [&>div:nth-child(2)]:min-h-0 [&>div:nth-child(2)]:overflow-auto"
            >
              <DataTableToolbar table={table} />
            </DataTable>
          </div>
        )}
      </SheetContent>
    </Sheet>
  )
}
