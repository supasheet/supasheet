import { useEffect, useState } from "react"

import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import {
  colorFromString,
  formatFieldValue,
} from "#/components/resource/resource-calendar"
import { Gantt } from "#/components/reui/gantt/gantt"
import { GanttNav } from "#/components/reui/gantt/gantt-nav"
import type {
  GanttEvent,
  GanttProposedUpdate,
  GanttResource,
  GanttScale,
} from "#/components/reui/gantt/gantt-types"
import { GanttView } from "#/components/reui/gantt/gantt-view"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  ColumnSchema,
  GanttLayout,
  PrimaryKey,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { getPkValue } from "#/lib/fields"
import { updateResourceMutationOptions } from "#/lib/supabase/data/resource"

const UNGROUPED_ID = "__ungrouped__"

export interface ResourceGanttData {
  resources: GanttResource[]
  events: GanttEvent<Record<string, unknown>>[]
  rowIds: Set<string>
}

export function buildGanttData(
  rows: Record<string, unknown>[],
  primaryKeys: PrimaryKey[],
  currentView: GanttLayout
): ResourceGanttData {
  const { title, start_date, end_date, group, progress, badge } = currentView

  const groups = new Map<string, GanttResource[]>()
  const rowIds = new Set<string>()
  const events: GanttEvent<Record<string, unknown>>[] = []

  for (const row of rows) {
    if (!row[start_date] || !row[end_date]) continue

    const rowId = getPkValue(row, primaryKeys)
    if (!rowId) continue
    rowIds.add(rowId)

    const groupValue =
      group && row[group] != null ? String(row[group]) : UNGROUPED_ID

    const leaf: GanttResource = {
      id: rowId,
      title: title ? String(row[title] ?? "") : "",
    }
    if (!groups.has(groupValue)) groups.set(groupValue, [])
    groups.get(groupValue)!.push(leaf)

    events.push({
      id: rowId,
      title: title ? String(row[title] ?? "") : "",
      start: new Date(String(row[start_date])),
      end: new Date(String(row[end_date])),
      allDay: true,
      resourceId: rowId,
      progress:
        progress && typeof row[progress] === "number"
          ? row[progress]
          : undefined,
      color: badge
        ? colorFromString(row[badge] != null ? String(row[badge]) : null)
        : undefined,
      data: row,
    })
  }

  let resources: GanttResource[]
  if (!group) {
    resources = groups.get(UNGROUPED_ID) ?? []
  } else {
    resources = Array.from(groups.entries()).map(([groupValue, children]) => ({
      id: `group:${groupValue}`,
      title: groupValue === UNGROUPED_ID ? "Ungrouped" : groupValue,
      children,
    }))
  }

  return { resources, events, rowIds }
}

export interface ResourceGanttProps {
  scale?: GanttScale
  resources: GanttResource[]
  events: GanttEvent<Record<string, unknown>>[]
  rowIds: Set<string>
  resourceSchema: ResourceSchema
  currentView: GanttLayout
  columnsSchema?: ColumnSchema[]
}

export function ResourceGantt({
  scale = "month",
  resources,
  events: initialEvents,
  rowIds,
  resourceSchema,
  currentView,
  columnsSchema = [],
}: ResourceGanttProps) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const startDateField = currentView.start_date
  const endDateField = currentView.end_date
  const readOnly = currentView.read_only ?? false

  const queryClient = useQueryClient()
  const navigate = useNavigate({
    from: "/$schema/resource/$resource/gantt/$ganttId",
  })

  const { mutate: updateResource } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )

  const canUpdate = useHasPermission({ schema, resource, action: "update" })

  const [events, setEvents] = useState(initialEvents)
  useEffect(() => {
    setEvents(initialEvents)
  }, [initialEvents])

  function getPk(row: Record<string, unknown>) {
    return Object.fromEntries(
      primaryKeys.map((pkField) => [pkField.name, row[pkField.name]])
    )
  }

  function onEventUpdate(update: GanttProposedUpdate<Record<string, unknown>>) {
    const row = update.event.data
    if (!row) return false

    const previous = events
    const startCol = columnsSchema.find((c) => c.name === startDateField)
    const endCol = columnsSchema.find((c) => c.name === endDateField)
    const patch: Record<string, unknown> = {
      [startDateField]: formatFieldValue(startCol?.format, update.start),
      [endDateField]: formatFieldValue(endCol?.format, update.end),
    }

    updateResource(
      { pk: getPk(row), data: patch },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({
            queryKey: ["supasheet", "resource-data", schema, resource],
          })
        },
        onError: (err) => {
          setEvents(previous)
          toast.error(
            err instanceof Error ? err.message : "Failed to update record"
          )
        },
      }
    )
  }

  function goToDetail(resourceId: string) {
    if (!rowIds.has(resourceId)) return
    void navigate({
      to: "/$schema/resource/$resource/$resourceId/detail",
      params: { schema, resource, resourceId },
    })
  }

  return (
    <div className="flex h-full min-h-0 flex-col rounded-md border bg-card">
      <Gantt
        className="h-full min-h-0"
        events={events}
        onEventsChange={setEvents}
        resources={resources}
        scale={scale}
        onScaleChange={(s) =>
          void navigate({
            search: (prev: Record<string, unknown>) => ({
              ...prev,
              scale: s,
            }),
          })
        }
        interactions={{
          drag: canUpdate && !readOnly,
          resize: canUpdate && !readOnly,
          selectSlot: false,
        }}
        onEventUpdate={canUpdate && !readOnly ? onEventUpdate : undefined}
        onEventClick={(occurrence) =>
          goToDetail(occurrence.event.resourceId ?? "")
        }
        onResourceClick={(ctx) => !ctx.isGroup && goToDetail(ctx.resource.id)}
        parentScheduling={false}
        summaryBars
      >
        <GanttNav />
        <GanttView />
      </Gantt>
    </div>
  )
}
