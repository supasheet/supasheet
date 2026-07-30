import { useEffect, useState } from "react"

import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { EVENT_CALENDAR_COLORS } from "#/components/reui/event-calendar/event-calendar-event"
import { EventCalendar } from "#/components/reui/event-calendar/event-calendar"
import { EventCalendarContent } from "#/components/reui/event-calendar/event-calendar-content"
import { EventCalendarNav } from "#/components/reui/event-calendar/event-calendar-nav"
import type {
  CalendarEvent,
  CalendarView,
  EventCalendarOccurrence,
  EventCalendarProposedUpdate,
  EventCalendarSlotInfo,
} from "#/components/reui/event-calendar/event-calendar-types"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  CalendarLayout,
  ColumnSchema,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { getPkValue } from "#/lib/fields"
import { updateResourceMutationOptions } from "#/lib/supabase/data/resource"

export function colorFromString(str: string | null | undefined): string {
  if (!str) return EVENT_CALENDAR_COLORS[0].value
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash)
  }
  return EVENT_CALENDAR_COLORS[Math.abs(hash) % EVENT_CALENDAR_COLORS.length]
    .value
}

const CALENDAR_VIEWS: CalendarView[] = ["month", "week", "day", "agenda"]

export interface ResourceCalendarProps {
  view?: CalendarView
  data: CalendarEvent[]
  resourceSchema: ResourceSchema
  currentView: CalendarLayout
  columnsSchema?: ColumnSchema[]
}

function formatFieldValue(
  format: string | null | undefined,
  date: Date
): string {
  const pad = (n: number) => String(n).padStart(2, "0")
  const value = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  if (format === "date") return value
  return `${value}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function ResourceCalendar({
  view = "month",
  data,
  resourceSchema,
  currentView,
  columnsSchema = [],
}: ResourceCalendarProps) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const startDateField = currentView.start_date ?? ""
  const endDateField = currentView.end_date ?? ""
  const hasPk = primaryKeys.length > 0
  const readOnly = currentView.read_only ?? false

  const queryClient = useQueryClient()
  const navigate = useNavigate({
    from: "/$schema/resource/$resource/calendar/$calendarId",
  })

  const { mutate: updateResource } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )

  const canUpdate = useHasPermission({ schema, resource, action: "update" })

  // Controlled `events` gives drag/resize an optimistic move while the
  // mutation is in flight; reseeded whenever fresh data arrives from the
  // query cache (mirrors ResourceKanban's local column state).
  const [events, setEvents] = useState(data)
  useEffect(() => {
    setEvents(data)
  }, [data])

  function getPk(row: Record<string, unknown>) {
    return Object.fromEntries(
      primaryKeys.map((pkField) => [pkField.name, row[pkField.name]])
    )
  }

  function onEventUpdate(update: EventCalendarProposedUpdate) {
    const row = update.event.data as Record<string, unknown> | undefined
    if (!row || !hasPk) return false

    const previous = events
    const startCol = columnsSchema.find((c) => c.name === startDateField)
    const endCol = columnsSchema.find((c) => c.name === endDateField)
    const patch: Record<string, unknown> = {
      [startDateField]: formatFieldValue(startCol?.format, update.start),
    }
    if (endDateField) {
      patch[endDateField] = formatFieldValue(endCol?.format, update.end)
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

  function onSlotClick(slot: EventCalendarSlotInfo) {
    if (!hasPk) return
    const startCol = columnsSchema.find((c) => c.name === startDateField)
    const defaults = startDateField
      ? { [startDateField]: formatFieldValue(startCol?.format, slot.date) }
      : undefined
    void navigate({
      to: "/$schema/resource/$resource/new",
      params: { schema, resource },
      search: defaults ? { defaults } : undefined,
    })
  }

  function onEventClick(occurrence: EventCalendarOccurrence) {
    const row = occurrence.event.data as Record<string, unknown> | undefined
    if (!row || !hasPk) return
    const resourceId = getPkValue(row, primaryKeys)
    void navigate({
      to: "/$schema/resource/$resource/$resourceId/detail",
      params: { schema, resource, resourceId },
    })
  }

  return (
    <div className="flex h-full min-h-0 flex-col rounded-xl bg-card">
      <EventCalendar
        className="h-full min-h-0"
        events={events}
        onEventsChange={setEvents}
        view={view}
        onViewChange={(v) =>
          void navigate({
            search: (prev: Record<string, unknown>) => ({ ...prev, view: v }),
          })
        }
        views={CALENDAR_VIEWS}
        showDayAddButton={hasPk && !readOnly}
        interactions={{
          drag: canUpdate && !readOnly,
          resize: canUpdate && !readOnly && Boolean(endDateField),
          selectSlot: false,
        }}
        onEventUpdate={canUpdate && !readOnly ? onEventUpdate : undefined}
        onSlotClick={hasPk && !readOnly ? onSlotClick : undefined}
        onEventClick={hasPk ? onEventClick : undefined}
      >
        <EventCalendarNav />
        <EventCalendarContent />
      </EventCalendar>
    </div>
  )
}
