import * as React from "react"

import {
  type Cell,
  type ColumnPinningPosition,
  FlexRender,
  type Header,
  type ReactTable,
  type Row,
  type RowData,
  Subscribe,
} from "@tanstack/react-table"

import { cn } from "cn"

import { DataTableFooter } from "#/components/data-table/data-table-footer"
import { DataTablePagination } from "#/components/data-table/data-table-pagination"
import { useDirection } from "#/components/ui/direction"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import type { DataTableFeatures } from "#/lib/data-table-features"
import {
  getAriaSort,
  getColumnPinningStyle,
  getColumnSizingStyle,
  getVisibleSelectedRows,
} from "#/lib/data-table-utils"

interface DataTableProps<
  TData extends RowData,
> extends React.ComponentProps<"div"> {
  table: ReactTable<DataTableFeatures, TData, unknown>
  actionBar?: React.ReactNode
}

export function DataTable<TData extends RowData>({
  table,
  actionBar,
  children,
  className,
  "aria-label": ariaLabel,
  "aria-labelledby": ariaLabelledBy,
  ...props
}: DataTableProps<TData>) {
  const dir = useDirection()

  return (
    <div
      data-slot="data-table"
      dir={dir}
      className={cn("flex w-full flex-col gap-2.5 overflow-auto", className)}
      {...props}
    >
      {children}
      <div className="isolate flex min-h-0 flex-1 flex-col overflow-hidden rounded-md border [&_[data-slot=table-container]]:min-h-0 [&_[data-slot=table-container]]:flex-1 [&_[data-slot=table-container]]:overflow-auto [&_[data-slot=table-header]]:sticky [&_[data-slot=table-header]]:top-0 [&_[data-slot=table-header]]:z-10 [&_[data-slot=table-header]]:bg-background">
        <DataTableLayout
          table={table}
          aria-label={ariaLabel}
          aria-labelledby={ariaLabelledBy}
        >
          <DataTableHeader table={table} />
          <DataTableBody table={table} />
          <DataTableFooter table={table} />
        </DataTableLayout>
      </div>
      <div className="flex flex-col gap-2.5">
        <DataTablePagination table={table} />
        {actionBar ? (
          <DataTableActionBar table={table} actionBar={actionBar} />
        ) : null}
      </div>
    </div>
  )
}

interface DataTableLayoutProps<TData extends RowData> extends Pick<
  React.ComponentProps<"table">,
  "aria-label" | "aria-labelledby"
> {
  table: ReactTable<DataTableFeatures, TData, unknown>
  children: React.ReactNode
}

function DataTableLayout<TData extends RowData>({
  table,
  children,
  ...props
}: DataTableLayoutProps<TData>) {
  return (
    <table.Subscribe
      selector={(state) => ({
        columnOrder: state.columnOrder,
        columnPinning: state.columnPinning,
        columnSizing: state.columnSizing,
        columnVisibility: state.columnVisibility,
      })}
    >
      {() => (
        <Table
          className="table-fixed"
          style={getColumnSizingStyle(table)}
          {...props}
        >
          {children}
        </Table>
      )}
    </table.Subscribe>
  )
}

interface DataTableHeaderProps<TData extends RowData> {
  table: ReactTable<DataTableFeatures, TData, unknown>
}

function DataTableHeader<TData extends RowData>({
  table,
}: DataTableHeaderProps<TData>) {
  return (
    <table.Subscribe
      selector={(state) => ({
        columnOrder: state.columnOrder,
        columnPinning: state.columnPinning,
        columnVisibility: state.columnVisibility,
      })}
    >
      {() => (
        <TableHeader>
          {table.getHeaderGroups().map((headerGroup) => (
            <TableRow key={headerGroup.id} className="group/row">
              {headerGroup.headers.map((header) => (
                <DataTableHeadCell
                  key={header.id}
                  header={header}
                  pinned={header.column.getIsPinned()}
                />
              ))}
            </TableRow>
          ))}
        </TableHeader>
      )}
    </table.Subscribe>
  )
}

interface DataTableHeadCellProps<TData extends RowData> {
  header: Header<DataTableFeatures, TData>
  pinned: ColumnPinningPosition
}

function DataTableHeadCell<TData extends RowData>({
  header,
  pinned,
}: DataTableHeadCellProps<TData>) {
  return (
    <Subscribe
      source={header.column.table.atoms.sorting}
      selector={(sorting) => getAriaSort(sorting, header.column.id)}
    >
      {(ariaSort) => (
        <TableHead
          aria-sort={ariaSort}
          colSpan={header.colSpan}
          className={getCellClassName(pinned)}
          style={getColumnPinningStyle(header.column)}
        >
          {header.isPlaceholder ? null : <FlexRender header={header} />}
          {header.column.getCanResize() ? (
            <DataTableResizeHandle header={header} />
          ) : null}
        </TableHead>
      )}
    </Subscribe>
  )
}

function DataTableResizeHandle<TData extends RowData>({
  header,
}: {
  header: Header<DataTableFeatures, TData>
}) {
  const isResizing = header.column.getIsResizing()

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label={`Resize ${header.column.id} column`}
      onMouseDown={header.getResizeHandler()}
      onTouchStart={header.getResizeHandler()}
      onDoubleClick={() => header.column.resetSize()}
      className="absolute inset-y-0 end-0 z-10 flex w-2 cursor-col-resize touch-none justify-end select-none"
    >
      <div
        className={cn(
          "my-3 w-px bg-border",
          isResizing && "my-2 w-0.5 bg-primary"
        )}
      />
    </div>
  )
}

interface DataTableBodyProps<TData extends RowData> {
  table: ReactTable<DataTableFeatures, TData, unknown>
}

function DataTableBody<TData extends RowData>({
  table,
}: DataTableBodyProps<TData>) {
  const rows = table.getRowModel().rows

  if (!rows.length) {
    return (
      <Subscribe source={table.atoms.columnVisibility}>
        {() => (
          <TableBody>
            <TableRow>
              <TableCell
                colSpan={table.getVisibleLeafColumns().length || 1}
                className="h-24 text-center"
              >
                No results.
              </TableCell>
            </TableRow>
          </TableBody>
        )}
      </Subscribe>
    )
  }

  return (
    <TableBody>
      {rows.map((row) => (
        <DataTableRow key={row.id} row={row} />
      ))}
    </TableBody>
  )
}

interface DataTableRowProps<TData extends RowData> {
  row: Row<DataTableFeatures, TData>
}

const DataTableRow = React.memo(DataTableRowImpl) as typeof DataTableRowImpl

function DataTableRowImpl<TData extends RowData>({
  row,
}: DataTableRowProps<TData>) {
  return (
    <Subscribe
      source={row.table.store}
      selector={(state) => ({
        columnOrder: state.columnOrder,
        columnPinning: state.columnPinning,
        columnVisibility: state.columnVisibility,
        isSelected: state.rowSelection[row.id] === true,
      })}
    >
      {({ isSelected }) => (
        <TableRow
          data-state={isSelected ? "selected" : undefined}
          className="group/row"
        >
          {row.getVisibleCells().map((cell) => (
            <DataTableCell
              key={cell.id}
              cell={cell}
              pinned={cell.column.getIsPinned()}
            />
          ))}
        </TableRow>
      )}
    </Subscribe>
  )
}

interface DataTableCellProps<TData extends RowData> {
  cell: Cell<DataTableFeatures, TData>
  pinned: ColumnPinningPosition
}

const DataTableCell = React.memo(DataTableCellImpl) as typeof DataTableCellImpl

function DataTableCellImpl<TData extends RowData>({
  cell,
  pinned,
}: DataTableCellProps<TData>) {
  return (
    <TableCell
      className={getCellClassName(pinned)}
      style={getColumnPinningStyle(cell.column)}
    >
      <FlexRender cell={cell} />
    </TableCell>
  )
}

interface DataTableActionBarProps<TData extends RowData> {
  table: ReactTable<DataTableFeatures, TData, unknown>
  actionBar: React.ReactNode
}

function DataTableActionBar<TData extends RowData>({
  table,
  actionBar,
}: DataTableActionBarProps<TData>) {
  return (
    <table.Subscribe selector={() => getVisibleSelectedRows(table).length > 0}>
      {(hasVisibleSelectedRows) => (hasVisibleSelectedRows ? actionBar : null)}
    </table.Subscribe>
  )
}

function getCellClassName(pinned: ColumnPinningPosition) {
  return pinned
    ? "overflow-hidden bg-background transition-colors group-hover/row:bg-[color-mix(in_srgb,var(--muted)_50%,var(--background))] group-has-aria-expanded/row:bg-[color-mix(in_srgb,var(--muted)_50%,var(--background))] group-data-[state=selected]/row:bg-muted"
    : "overflow-hidden"
}
