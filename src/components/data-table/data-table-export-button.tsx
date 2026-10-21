import type { RowData } from "@tanstack/react-table"

import { DownloadIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type { DataTableInstance } from "#/lib/data-table-types"
import { getVisibleSelectedRows } from "#/lib/data-table-utils"
import { EXPORT_FORMATS, exportTable } from "#/lib/export"

interface DataTableExportButtonProps<TData extends RowData> {
  table: DataTableInstance<TData>
  filename?: string
}

export function DataTableExportButton<TData extends RowData>({
  table,
  filename,
}: DataTableExportButtonProps<TData>) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button variant="outline">
            <DownloadIcon className="size-4" />
            Export
          </Button>
        }
      />
      <DropdownMenuContent align="end">
        {EXPORT_FORMATS.map(({ format, label }) => (
          <DropdownMenuItem
            key={format}
            onClick={() =>
              exportTable(table, {
                format,
                filename,
                excludeColumns: ["select", "actions"],
                onlySelected: getVisibleSelectedRows(table).length > 0,
              })
            }
          >
            Export as {label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
