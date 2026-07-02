import { coerceColumnValue } from "#/lib/columns"
import type { ColumnSchema } from "#/lib/database-meta.types"

export const IMPORT_BATCH_SIZE = 500

export const IMPORT_FILE_ACCEPT =
  ".csv,.tsv,.json,text/csv,text/tab-separated-values,application/json"

export interface ParsedData {
  headers: string[]
  rows: Record<string, string>[]
}

export function parseDelimited(text: string, delimiter = ","): ParsedData {
  const records: string[][] = []
  let record: string[] = []
  let current = ""
  let inQuotes = false

  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (ch === '"') {
      if (inQuotes && text[i + 1] === '"') {
        current += '"'
        i++
      } else {
        inQuotes = !inQuotes
      }
    } else if (ch === delimiter && !inQuotes) {
      record.push(current)
      current = ""
    } else if ((ch === "\n" || ch === "\r") && !inQuotes) {
      if (ch === "\r" && text[i + 1] === "\n") i++
      record.push(current)
      records.push(record)
      record = []
      current = ""
    } else {
      current += ch
    }
  }
  if (current !== "" || record.length > 0) {
    record.push(current)
    records.push(record)
  }

  const nonEmpty = records.filter((r) => r.some((cell) => cell.trim() !== ""))
  if (nonEmpty.length < 2) return { headers: [], rows: [] }

  const headers = nonEmpty[0]
  const rows = nonEmpty
    .slice(1)
    .map((values) =>
      Object.fromEntries(headers.map((h, i) => [h, values[i] ?? ""]))
    )

  return { headers, rows }
}

export function parseJSON(text: string): ParsedData {
  const data: unknown = JSON.parse(text)
  const items = Array.isArray(data) ? data : [data]

  const headers: string[] = []
  const seen = new Set<string>()
  const rows = items
    .filter(
      (item): item is Record<string, unknown> =>
        typeof item === "object" && item !== null && !Array.isArray(item)
    )
    .map((item) =>
      Object.fromEntries(
        Object.entries(item).map(([key, value]) => {
          if (!seen.has(key)) {
            seen.add(key)
            headers.push(key)
          }
          if (value === null || value === undefined) return [key, ""]
          if (typeof value === "object") return [key, JSON.stringify(value)]
          return [key, String(value)]
        })
      )
    )

  if (rows.length === 0) return { headers: [], rows: [] }
  return { headers, rows }
}

export async function parseImportFile(file: File): Promise<ParsedData> {
  const text = await file.text()
  const ext = file.name.split(".").pop()?.toLowerCase()

  if (ext === "json") return parseJSON(text)
  if (ext === "tsv") return parseDelimited(text, "\t")
  return parseDelimited(text, ",")
}

export function matchHeaders(
  csvHeaders: string[],
  columnsSchema: ColumnSchema[]
): { matched: string[]; unmatched: string[] } {
  const tableNames = new Set(
    columnsSchema.map((c) => c.name?.toLowerCase() ?? "")
  )
  return {
    matched: csvHeaders.filter((h) => tableNames.has(h.toLowerCase())),
    unmatched: csvHeaders.filter((h) => !tableNames.has(h.toLowerCase())),
  }
}

export function coerceImportRow(
  rawRow: Record<string, string>,
  matchedHeaders: string[],
  columnMap: Map<string, ColumnSchema>
): Record<string, unknown> {
  return Object.fromEntries(
    matchedHeaders
      .map((h) => {
        const col = columnMap.get(h.toLowerCase())
        return [h, coerceColumnValue(rawRow[h] ?? "", col)] as [string, unknown]
      })
      .filter(([, v]) => v !== null && v !== undefined)
  )
}

export function buildColumnMap(
  columnsSchema: ColumnSchema[]
): Map<string, ColumnSchema> {
  return new Map(columnsSchema.map((c) => [c.name?.toLowerCase() ?? "", c]))
}
