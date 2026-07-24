"use client"

import * as React from "react"

import {
  useMutation,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from "#/components/ui/sheet"
import { useIsMobile } from "#/hooks/use-mobile"
import {
  IMPORT_BATCH_SIZE,
  buildColumnMap,
  coerceImportRow,
  matchHeaders,
  parseImportFile,
} from "#/lib/import"
import type { ParsedData } from "#/lib/import"
import {
  columnsSchemaQueryOptions,
  insertBulkResourceMutationOptions,
} from "#/lib/supabase/data/resource"
import { cn } from "#/lib/utils"

import { ResourceFormSheetSkeleton } from "./resource-form-sheet-skeleton"
import { ResourceImportDropzone } from "./resource-import-dropzone"
import { ResourceImportPreview } from "./resource-import-preview"

interface ResourceImportSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  schema: string
  resource: string
}

export function ResourceImportSheet(props: ResourceImportSheetProps) {
  const isMobile = useIsMobile()
  const side = isMobile ? "bottom" : "right"

  return (
    <Sheet open={props.open} onOpenChange={props.onOpenChange}>
      <SheetContent
        side={side}
        className={cn(
          "gap-0",
          side === "right" && "w-full! sm:max-w-lg!",
          side === "bottom" && "max-h-[80vh] overflow-hidden"
        )}
      >
        <React.Suspense fallback={<ResourceFormSheetSkeleton />}>
          <ResourceImportSheetBody {...props} />
        </React.Suspense>
      </SheetContent>
    </Sheet>
  )
}

function ResourceImportSheetBody({
  onOpenChange,
  schema,
  resource,
}: ResourceImportSheetProps) {
  const queryClient = useQueryClient()
  const { data: columnsSchema = [] } = useSuspenseQuery(
    columnsSchemaQueryOptions(schema as never, resource as never)
  )

  const [parsed, setParsed] = React.useState<ParsedData | null>(null)
  const [filename, setFilename] = React.useState("")
  const [progress, setProgress] = React.useState(0)
  const [importing, setImporting] = React.useState(false)
  const [done, setDone] = React.useState(false)
  const [errors, setErrors] = React.useState<string[]>([])

  const columnMap = React.useMemo(
    () => buildColumnMap(columnsSchema),
    [columnsSchema]
  )

  const { matched: matchedHeaders, unmatched: unmatchedHeaders } =
    React.useMemo(
      () =>
        parsed
          ? matchHeaders(parsed.headers, columnsSchema)
          : { matched: [], unmatched: [] },
      [parsed, columnsSchema]
    )

  const { mutateAsync: insertBulk } = useMutation(
    insertBulkResourceMutationOptions(schema as never, resource as never)
  )

  function reset() {
    setParsed(null)
    setFilename("")
    setProgress(0)
    setDone(false)
    setErrors([])
  }

  function handleFile(file: File) {
    setFilename(file.name)
    setParsed(null)
    setDone(false)
    setErrors([])
    setProgress(0)
    parseImportFile(file)
      .then(setParsed)
      .catch(() => {
        setFilename("")
        toast.error(`Could not parse ${file.name}`)
      })
  }

  async function handleImport() {
    if (!parsed || matchedHeaders.length === 0) return
    setImporting(true)
    setErrors([])
    const errs: string[] = []
    let inserted = 0

    const coercedRows = parsed.rows.map((rawRow) =>
      coerceImportRow(rawRow, matchedHeaders, columnMap)
    )

    const batches: Record<string, unknown>[][] = []
    for (let i = 0; i < coercedRows.length; i += IMPORT_BATCH_SIZE) {
      batches.push(coercedRows.slice(i, i + IMPORT_BATCH_SIZE))
    }

    for (let b = 0; b < batches.length; b++) {
      const batch = batches[b]
      const start = b * IMPORT_BATCH_SIZE + 1
      const end = start + batch.length - 1
      try {
        await insertBulk(batch)
        inserted += batch.length
      } catch (err) {
        errs.push(
          `Rows ${start}–${end}: ${err instanceof Error ? err.message : "Unknown error"}`
        )
      }
      setProgress(Math.round(((b + 1) / batches.length) * 100))
    }

    setErrors(errs)
    setImporting(false)
    setDone(true)

    if (inserted > 0) {
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(
        `Imported ${inserted} of ${parsed.rows.length} record${inserted !== 1 ? "s" : ""}`
      )
    }
    if (errs.length > 0) {
      toast.error(
        `${errs.length} batch${errs.length !== 1 ? "es" : ""} failed to import`
      )
    }
  }

  function handleOpenChange(next: boolean) {
    if (importing) return
    onOpenChange(next)
    if (!next) setTimeout(reset, 200)
  }

  return (
    <>
      <SheetHeader className="border-b p-4 pr-10">
        <SheetTitle>Import data</SheetTitle>
        <SheetDescription>
          Upload a CSV, TSV, or JSON file to import records into{" "}
          <strong className="text-foreground">{resource}</strong>. Column
          headers (or JSON keys) must match table column names.
        </SheetDescription>
      </SheetHeader>

      <div className="flex flex-1 flex-col gap-4 overflow-y-auto p-4">
        {!parsed ? (
          <ResourceImportDropzone onFile={handleFile} />
        ) : (
          <ResourceImportPreview
            parsed={parsed}
            filename={filename}
            matchedHeaders={matchedHeaders}
            unmatchedHeaders={unmatchedHeaders}
            importing={importing}
            progress={progress}
            done={done}
            errors={errors}
            onReset={reset}
          />
        )}
      </div>

      <SheetFooter className="border-t">
        {!parsed && (
          <Button variant="outline" onClick={() => handleOpenChange(false)}>
            Cancel
          </Button>
        )}
        {parsed && !done && (
          <>
            <Button
              variant="outline"
              onClick={() => handleOpenChange(false)}
              disabled={importing}
            >
              Cancel
            </Button>
            <Button
              onClick={handleImport}
              disabled={
                importing ||
                matchedHeaders.length === 0 ||
                parsed.rows.length === 0
              }
            >
              {importing
                ? "Importing…"
                : `Import ${parsed.rows.length} record${parsed.rows.length !== 1 ? "s" : ""}`}
            </Button>
          </>
        )}
        {parsed && done && (
          <>
            <Button variant="outline" onClick={reset}>
              Import another
            </Button>
            <Button onClick={() => handleOpenChange(false)}>Done</Button>
          </>
        )}
      </SheetFooter>
    </>
  )
}
