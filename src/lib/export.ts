import type { Table } from "@tanstack/react-table"

export type ExportFormat = "csv" | "tsv" | "json"

export const EXPORT_FORMATS: { format: ExportFormat; label: string }[] = [
  { format: "csv", label: "CSV" },
  { format: "tsv", label: "TSV" },
  { format: "json", label: "JSON" },
]

interface ExportTableOptions<TData> {
  format?: ExportFormat
  filename?: string
  excludeColumns?: (keyof TData | "select" | "actions")[]
  onlySelected?: boolean
}

function getExportData<TData>(
  table: Table<TData>,
  opts: Pick<ExportTableOptions<TData>, "excludeColumns" | "onlySelected">
): { headers: string[]; rows: unknown[][] } {
  const { excludeColumns = [], onlySelected = false } = opts

  const columns = table
    .getAllLeafColumns()
    .filter(
      (column) =>
        !excludeColumns.includes(
          column.id as keyof TData | "select" | "actions"
        )
    )

  // Display label for end users; falls back to the column id (name).
  const headers = columns.map(
    (column) => column.columnDef.meta?.name ?? column.id
  )

  const rows = (
    onlySelected
      ? table.getFilteredSelectedRowModel().rows
      : table.getRowModel().rows
  ).map((row) =>
    // Always look up the value by the column id (the data key).
    columns.map((column) => row.getValue(column.id))
  )

  return { headers, rows }
}

function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.setAttribute("href", url)
  link.setAttribute("download", filename)
  link.style.visibility = "hidden"
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

function serializeDelimited(
  headers: string[],
  rows: unknown[][],
  delimiter: string
): string {
  const serializeCell = (value: unknown): string => {
    if (value === null || value === undefined) return ""
    const str =
      typeof value === "object" ? JSON.stringify(value) : String(value)
    return str.includes(delimiter) || /["\n\r]/.test(str)
      ? `"${str.replace(/"/g, '""')}"`
      : str
  }

  return [
    headers.map(serializeCell).join(delimiter),
    ...rows.map((row) => row.map(serializeCell).join(delimiter)),
  ].join("\n")
}

export function exportTable<TData>(
  table: Table<TData>,
  opts: ExportTableOptions<TData> = {}
): void {
  const { format = "csv", filename = "table", ...rest } = opts
  const { headers, rows } = getExportData(table, rest)

  if (format === "json") {
    const records = rows.map((row) =>
      Object.fromEntries(headers.map((header, i) => [header, row[i] ?? null]))
    )
    downloadBlob(
      new Blob([JSON.stringify(records, null, 2)], {
        type: "application/json;charset=utf-8;",
      }),
      `${filename}.json`
    )
    return
  }

  const delimiter = format === "tsv" ? "\t" : ","
  const mimeType =
    format === "tsv"
      ? "text/tab-separated-values;charset=utf-8;"
      : "text/csv;charset=utf-8;"
  downloadBlob(
    new Blob([serializeDelimited(headers, rows, delimiter)], {
      type: mimeType,
    }),
    `${filename}.${format}`
  )
}
