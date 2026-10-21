import { useMemo } from "react"

import { useTable } from "@tanstack/react-table"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableColumnHeader } from "#/components/data-table/data-table-column-header"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableViewOptions } from "#/components/data-table/data-table-view-options"
import { dataTableFeatures } from "#/lib/data-table-features"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type { DataTableColumnDef } from "#/lib/data-table-types"

type ResultRow = Record<string, unknown>

function formatCell(v: unknown): string {
  if (v === null || v === undefined) return ""
  if (typeof v === "object") return JSON.stringify(v)
  return String(v)
}

/**
 * Client-side table for AI query results. Unlike the resource tables its state
 * stays in memory, since several results can be on screen at once.
 */
export function ResultDataTable({ rows }: { rows: ResultRow[] }) {
  const columns = useMemo<DataTableColumnDef<ResultRow>[]>(() => {
    if (rows.length === 0) return []
    return Object.keys(rows[0]).map((key) => ({
      id: key,
      accessorKey: key,
      header: ({ column }) => (
        <DataTableColumnHeader column={column} label={key} />
      ),
      cell: ({ row }) => (
        <span className="font-mono text-xs">
          {formatCell(row.getValue(key))}
        </span>
      ),
      meta: { label: key },
    }))
  }, [rows])

  const table = useTable(
    {
      features: dataTableFeatures,
      data: rows,
      columns,
      initialState: { pagination: DEFAULT_PAGINATION },
    },
    (state) => ({ sorting: state.sorting, pagination: state.pagination })
  )

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-end gap-2">
        <DataTableExportButton table={table} filename="ai-result" />
        <DataTableViewOptions table={table} align="end" />
      </div>
      <DataTable table={table} />
    </div>
  )
}
