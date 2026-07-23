import { useCallback, useState } from "react"

import type { Table } from "@tanstack/react-table"

import { Trash2Icon } from "lucide-react"

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

interface DataTableActionBarProps<TData> {
  table: Table<TData>
  onDelete?: (rows: TData[]) => void | Promise<void>
}

export function DataTableActionBar<TData>({
  table,
  onDelete,
}: DataTableActionBarProps<TData>) {
  const [confirmOpen, setConfirmOpen] = useState(false)
  const rows = table.getFilteredSelectedRowModel().rows

  const onOpenChange = useCallback(
    (open: boolean) => {
      if (!open) {
        table.toggleAllRowsSelected(false)
      }
    },
    [table]
  )

  async function handleConfirm() {
    await onDelete?.(rows.map((r) => r.original))
    table.toggleAllRowsSelected(false)
    setConfirmOpen(false)
  }

  if (!onDelete) {
    return null
  }

  return (
    <>
      <ActionBar open={rows.length > 0} onOpenChange={onOpenChange}>
        <ActionBarSelection className="hidden sm:flex whitespace-nowrap">
          {rows.length} selected
        </ActionBarSelection>
        <ActionBarSeparator className="hidden sm:block" />
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
