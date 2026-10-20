import { AlertCircleIcon, CheckCircle2Icon } from "lucide-react"

import { Progress } from "#/components/ui/progress"
import { ScrollArea } from "#/components/ui/scroll-area"
import type { ParsedData } from "#/lib/import"

export function ResourceImportPreview({
  parsed,
  filename,
  matchedHeaders,
  unmatchedHeaders,
  importing,
  progress,
  done,
  errors,
  onReset,
}: {
  parsed: ParsedData
  filename: string
  matchedHeaders: string[]
  unmatchedHeaders: string[]
  importing: boolean
  progress: number
  done: boolean
  errors: string[]
  onReset: () => void
}) {
  const previewRows = parsed.rows.slice(0, 5)

  return (
    <>
      <div className="flex items-start justify-between gap-2 text-sm">
        <span className="truncate text-muted-foreground">{filename}</span>
        <button
          type="button"
          className="shrink-0 text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
          onClick={onReset}
          disabled={importing}
        >
          Change file
        </button>
      </div>

      <div className="grid grid-cols-2 gap-2 text-sm">
        <div className="rounded-md bg-muted/50 p-3">
          <p className="text-xs text-muted-foreground">Rows</p>
          <p className="font-medium">{parsed.rows.length}</p>
        </div>
        <div className="rounded-md bg-muted/50 p-3">
          <p className="text-xs text-muted-foreground">Columns matched</p>
          <p className="font-medium">
            {matchedHeaders.length}{" "}
            <span className="font-normal text-muted-foreground">
              / {parsed.headers.length}
            </span>
          </p>
        </div>
      </div>

      {unmatchedHeaders.length > 0 && (
        <div className="flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 dark:border-amber-800/40 dark:bg-amber-950/20 dark:text-amber-400">
          <AlertCircleIcon className="mt-0.5 size-3.5 shrink-0" />
          <span>
            Skipped columns: <strong>{unmatchedHeaders.join(", ")}</strong>
          </span>
        </div>
      )}

      {matchedHeaders.length === 0 ? (
        <div className="flex items-center gap-2 rounded-md border border-destructive/30 bg-destructive/5 p-3 text-sm text-destructive">
          <AlertCircleIcon className="size-4 shrink-0" />
          No CSV columns matched any table columns.
        </div>
      ) : (
        <div className="flex flex-col gap-1.5">
          <p className="text-xs text-muted-foreground">
            Preview (first {Math.min(5, previewRows.length)} rows)
          </p>
          <ScrollArea className="rounded-md border">
            <div className="min-w-max">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-muted/50">
                  <tr>
                    {matchedHeaders.map((h) => (
                      <th
                        key={h}
                        className="px-3 py-2 text-left font-medium whitespace-nowrap"
                      >
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {previewRows.map((row, i) => (
                    <tr key={i} className="border-t">
                      {matchedHeaders.map((h) => (
                        <td
                          key={h}
                          className="max-w-[180px] truncate px-3 py-1.5 text-muted-foreground"
                        >
                          {row[h]}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </ScrollArea>
          {parsed.rows.length > 5 && (
            <p className="text-xs text-muted-foreground">
              + {parsed.rows.length - 5} more rows
            </p>
          )}
        </div>
      )}

      {importing && (
        <Progress value={progress}>
          <span className="text-xs text-muted-foreground">
            Importing… {progress}%
          </span>
        </Progress>
      )}

      {done && !importing && (
        <div className="flex items-center gap-2 text-sm text-green-600 dark:text-green-400">
          <CheckCircle2Icon className="size-4 shrink-0" />
          Import complete — {parsed.rows.length - errors.length} of{" "}
          {parsed.rows.length} records inserted.
        </div>
      )}

      {errors.length > 0 && (
        <div className="flex flex-col gap-1.5">
          <p className="text-xs font-medium text-destructive">
            Errors ({errors.length})
          </p>
          <ScrollArea className="max-h-32 rounded-md border border-destructive/20 bg-destructive/5 p-2">
            {errors.map((e, i) => (
              <p key={i} className="text-xs text-destructive">
                {e}
              </p>
            ))}
          </ScrollArea>
        </div>
      )}
    </>
  )
}
