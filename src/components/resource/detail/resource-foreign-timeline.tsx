"use client"

import { useMemo, useState } from "react"

import { useSuspenseQuery } from "@tanstack/react-query"

import { format, formatDistanceToNow } from "date-fns"
import { PlusIcon } from "lucide-react"

import { SelectCell } from "#/components/resource/cells/select-cell"
import { NewRecordTrigger } from "#/components/resource/sheet/new-record-trigger"
import { Button } from "#/components/ui/button"
import {
  Timeline,
  TimelineContent,
  TimelineDate,
  TimelineHeader,
  TimelineIndicator,
  TimelineItem,
  TimelineSeparator,
  TimelineTitle,
} from "#/components/ui/timeline"
import { useHasPermission } from "#/hooks/use-permissions"
import { getColumnMetadata } from "#/lib/columns"
import type {
  ColumnSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { foreignTableDataQueryOptions } from "#/lib/supabase/data/resource"

type ResourceForeignTimelineProps = {
  parentResource: string
  parentColumn: string
  parentValue: unknown
  resourceSchema: ResourceSchema
  columnsSchema: ColumnSchema[]
  selectClause?: string
}

const PAGE_SIZE_STEP = 20

export function ResourceForeignTimeline({
  parentResource,
  parentColumn,
  parentValue,
  resourceSchema,
  columnsSchema,
  selectClause,
}: ResourceForeignTimelineProps) {
  const [pageSize, setPageSize] = useState(PAGE_SIZE_STEP)

  const schema = resourceSchema.schema
  const table = resourceSchema.name

  const canInsert = useHasPermission({
    schema,
    resource: table,
    action: "insert",
  })

  const defaultQuery = useMemo<TableMetadata["query"]>(() => {
    if (!resourceSchema.comment) return undefined
    try {
      return (JSON.parse(resourceSchema.comment) as TableMetadata).query
    } catch {
      return undefined
    }
  }, [resourceSchema.comment])

  const hasParentValue =
    parentValue !== undefined && parentValue !== null && parentValue !== ""

  const { data: queryResult } = useSuspenseQuery(
    foreignTableDataQueryOptions(
      schema,
      table,
      parentResource as never,
      parentColumn,
      hasParentValue ? parentValue : "__noop__",
      defaultQuery,
      selectClause,
      1,
      pageSize,
      "occurred_at",
      true,
      []
    )
  )

  const data = hasParentValue ? (queryResult?.result ?? []) : []
  const totalCount = hasParentValue ? (queryResult?.count ?? 0) : 0
  const hasMore = data.length < totalCount

  const eventTypeColumn = columnsSchema.find((c) => c.name === "event_type")
  const eventTypeMeta = eventTypeColumn
    ? getColumnMetadata(resourceSchema, eventTypeColumn)
    : null

  const defaults = hasParentValue
    ? { [parentColumn]: String(parentValue) }
    : undefined

  const newRecordUrl = (() => {
    const params = new URLSearchParams()
    if (defaults) params.set("defaults", JSON.stringify(defaults))
    const qs = params.toString()
    return `/${schema}/resource/${table}/new${qs ? `?${qs}` : ""}`
  })()

  return (
    <div className="flex flex-col gap-4">
      {canInsert && (
        <div className="flex justify-end">
          <NewRecordTrigger
            schema={schema}
            resource={table}
            defaults={defaults}
            url={newRecordUrl}
            size="sm"
          >
            <PlusIcon className="size-4" />
            New entry
          </NewRecordTrigger>
        </div>
      )}

      {data.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <p className="font-medium text-sm">No activity yet</p>
          <p className="mt-1 text-muted-foreground text-xs">
            Events for this record will appear here.
          </p>
        </div>
      ) : (
        <Timeline className="px-1 py-2" value={data.length}>
          {data.map((row, index) => {
            const occurredAt = row.occurred_at as string | null
            const actor = row.actor as { name?: string | null } | null
            const metadata = row.metadata

            return (
              <TimelineItem key={String(row.id ?? index)} step={index + 1}>
                <TimelineIndicator />
                <TimelineSeparator />
                <TimelineContent>
                  <TimelineHeader>
                    {occurredAt && (
                      <TimelineDate dateTime={occurredAt}>
                        {formatDistanceToNow(new Date(occurredAt), {
                          addSuffix: true,
                        })}
                        <span className="ml-1 text-muted-foreground/60">
                          · {format(new Date(occurredAt), "MMM d, HH:mm")}
                        </span>
                      </TimelineDate>
                    )}
                    <TimelineTitle className="flex items-center gap-1.5">
                      {String(row.title ?? "")}
                      {eventTypeMeta && (
                        <SelectCell
                          value={row.event_type as string | null}
                          columnMetadata={eventTypeMeta}
                        />
                      )}
                    </TimelineTitle>
                  </TimelineHeader>
                  {(actor?.name || metadata != null) && (
                    <div className="mt-1 flex flex-wrap items-center gap-2 text-muted-foreground text-xs">
                      {actor?.name && <span>by {actor.name}</span>}
                      {actor?.name && metadata != null && (
                        <span className="text-muted-foreground/50">·</span>
                      )}
                      {metadata != null && (
                        <span className="truncate font-mono">
                          {JSON.stringify(metadata)}
                        </span>
                      )}
                    </div>
                  )}
                </TimelineContent>
              </TimelineItem>
            )
          })}
        </Timeline>
      )}

      {hasMore && (
        <div className="flex justify-center">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setPageSize((s) => s + PAGE_SIZE_STEP)}
          >
            Load more
          </Button>
        </div>
      )}
    </div>
  )
}
