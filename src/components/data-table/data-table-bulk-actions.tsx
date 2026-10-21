import { useState } from "react"

import { Subscribe } from "@tanstack/react-table"
import type { RowData } from "@tanstack/react-table"

import { DownloadIcon, Trash2Icon } from "lucide-react"

import {
  ActionBar,
  ActionBarGroup,
  ActionBarItem,
  ActionBarSelection,
  ActionBarSeparator,
} from "#/components/ui/action-bar"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "#/components/ui/alert-dialog"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type { DataTableInstance } from "#/lib/data-table-types"
import { getVisibleSelectedRows } from "#/lib/data-table-utils"
import { EXPORT_FORMATS, exportTable } from "#/lib/export"

interface DataTableBulkActionsProps<TData extends RowData> {
  table: DataTableInstance<TData>
  filename?: string
  onDelete?: (rows: TData[]) => void | Promise<void>
}

/**
 * Floating bar shown while rows are selected. Pass it to `DataTable` via the
 * `actionBar` prop, which only renders it when a visible row is selected.
 */
export function DataTableBulkActions<TData extends RowData>(
  props: DataTableBulkActionsProps<TData>
) {
  return (
    <Subscribe source={props.table.atoms.rowSelection}>
      {() => <BulkActionsContent {...props} />}
    </Subscribe>
  )
}

function BulkActionsContent<TData extends RowData>({
  table,
  filename,
  onDelete,
}: DataTableBulkActionsProps<TData>) {
  const [confirmOpen, setConfirmOpen] = useState(false)
  const rows = getVisibleSelectedRows(table)

  async function handleConfirm() {
    await onDelete?.(rows.map((row) => row.original))
    table.resetRowSelection()
    setConfirmOpen(false)
  }

  return (
    <>
      <ActionBar
        open={rows.length > 0}
        onOpenChange={(open) => {
          if (!open) table.resetRowSelection()
        }}
      >
        <ActionBarSelection className="hidden whitespace-nowrap sm:flex">
          {rows.length} selected
        </ActionBarSelection>
        <ActionBarSeparator className="hidden sm:block" />
        <ActionBarGroup>
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <ActionBarItem onSelect={(e) => e.preventDefault()}>
                  <DownloadIcon className="size-4" />
                  Export
                </ActionBarItem>
              }
            />
            <DropdownMenuContent align="start">
              {EXPORT_FORMATS.map(({ format, label }) => (
                <DropdownMenuItem
                  key={format}
                  onClick={() =>
                    exportTable(table, {
                      format,
                      filename,
                      excludeColumns: ["select", "actions"],
                      onlySelected: true,
                    })
                  }
                >
                  Export as {label}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        </ActionBarGroup>
        {onDelete && <ActionBarSeparator />}
        {onDelete && (
          <ActionBarGroup>
            <ActionBarItem
              variant="destructive"
              onSelect={(e) => e.preventDefault()}
              onClick={() => setConfirmOpen(true)}
            >
              <Trash2Icon className="size-4" />
              Delete ({rows.length})
            </ActionBarItem>
          </ActionBarGroup>
        )}
      </ActionBar>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Delete {rows.length} {rows.length === 1 ? "row" : "rows"}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={handleConfirm}>
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
