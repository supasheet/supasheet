import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { CalendarRange, Columns, Grid2x2, Grid3x3, List } from "lucide-react"
import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import { ButtonGroup } from "#/components/ui/button-group"
import {
  EventCalendarAgendaView,
  EventCalendarContainer,
  EventCalendarDayView,
  EventCalendarHeader,
  EventCalendarMonthView,
  EventCalendarRoot,
  EventCalendarWeekView,
  EventCalendarYearView,
} from "#/components/ui/event-calendar"
import type { IEvent, TCalendarView } from "#/components/ui/event-calendar"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  CalendarLayout,
  ColumnSchema,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { getPkValue } from "#/lib/fields"
import {
  deleteResourceMutationOptions,
  updateResourceMutationOptions,
} from "#/lib/supabase/data/resource"

type TEventColor =
  "blue" | "green" | "red" | "yellow" | "purple" | "orange" | "gray"

const COLORS: TEventColor[] = [
  "blue",
  "green",
  "red",
  "yellow",
  "purple",
  "orange",
  "gray",
]

export function colorFromString(str: string | null | undefined): TEventColor {
  if (!str) return "blue"
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash)
  }
  return COLORS[Math.abs(hash) % COLORS.length]
}

export interface ResourceCalendarProps {
  view?: TCalendarView
  data: IEvent[]
  resourceSchema: ResourceSchema
  currentView: CalendarLayout
  columnsSchema?: ColumnSchema[]
}

function formatSlotValue(format: string | undefined, slot: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0")
  const date = `${slot.getFullYear()}-${pad(slot.getMonth() + 1)}-${pad(slot.getDate())}`
  if (format === "date") return date
  return `${date}T${pad(slot.getHours())}:${pad(slot.getMinutes())}`
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

  const queryClient = useQueryClient()
  const navigate = useNavigate({
    from: "/$schema/resource/$resource/calendar/$calendarId",
  })

  const { mutate: updateResource } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )
  const { mutateAsync: deleteRow } = useMutation(
    deleteResourceMutationOptions(schema, resource)
  )

  function getPk(event: IEvent): Record<string, unknown> {
    return Object.fromEntries(
      primaryKeys.map((pkField) => [pkField.name, event.data?.[pkField.name]])
    )
  }

  function onDragEvent(event: IEvent) {
    updateResource(
      {
        pk: getPk(event),
        data: {
          [startDateField]: event.startDate,
          [endDateField]: event.endDate,
        },
      },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({
            queryKey: ["supasheet", "resource-data", schema, resource],
          })
        },
      }
    )
  }

  function onAddEvent({
    startDate,
    hour,
    minute,
  }: {
    startDate: Date
    hour: number
    minute: number
  }) {
    const start = new Date(startDate)
    start.setHours(hour, minute)
    const startCol = columnsSchema.find((c) => c.name === startDateField)
    const defaults = startDateField
      ? {
          [startDateField]: formatSlotValue(
            startCol?.format ?? undefined,
            start
          ),
        }
      : undefined
    void navigate({
      to: "/$schema/resource/$resource/new",
      params: { schema, resource },
      search: defaults ? { defaults } : undefined,
    })
  }

  function onEventView(event: IEvent) {
    const resourceId = getPkValue(event.data ?? {}, primaryKeys)
    void navigate({
      to: "/$schema/resource/$resource/$resourceId/detail",
      params: { schema, resource, resourceId },
    })
  }

  async function onEventDelete(event: IEvent) {
    try {
      await deleteRow(getPk(event))
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success("Record deleted")
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to delete record"
      )
    }
  }

  const hasPk = primaryKeys.length > 0
  const canUpdate = useHasPermission(`${schema}.${resource}:update`)
  const canDelete = useHasPermission(`${schema}.${resource}:delete`)

  return (
    <div className="flex h-full flex-col gap-2">
      <EventCalendarRoot
        view={view}
        events={data}
        onViewUpdate={(v) =>
          void navigate({
            search: (prev: Record<string, unknown>) => ({
              ...prev,
              view: v,
            }),
          })
        }
        onDragEvent={canUpdate ? onDragEvent : undefined}
        onAddEvent={hasPk ? onAddEvent : undefined}
        onEventView={hasPk ? onEventView : undefined}
        onEventDelete={hasPk && canDelete ? onEventDelete : undefined}
      >
        <EventCalendarHeader>
          <EventCalendarNavigation view={view} />
        </EventCalendarHeader>
        <EventCalendarContainer>
          <EventCalendarDayView />
          <EventCalendarWeekView />
          <EventCalendarMonthView />
          <EventCalendarYearView />
          <EventCalendarAgendaView />
        </EventCalendarContainer>
      </EventCalendarRoot>
    </div>
  )
}

function EventCalendarNavigation({ view }: { view: TCalendarView }) {
  const navigate = useNavigate({
    from: "/$schema/resource/$resource/calendar/$calendarId",
  })

  function goTo(v: TCalendarView) {
    void navigate({
      search: (prev: Record<string, unknown>) => ({
        ...prev,
        view: v,
      }),
    })
  }

  return (
    <ButtonGroup>
      <Button
        aria-label="View by day"
        size="icon-sm"
        variant={view === "day" ? "default" : "outline"}
        onClick={() => goTo("day")}
      >
        <List className="size-4" />
      </Button>

      <Button
        aria-label="View by week"
        size="icon-sm"
        variant={view === "week" ? "default" : "outline"}
        onClick={() => goTo("week")}
      >
        <Columns className="size-4" />
      </Button>

      <Button
        aria-label="View by month"
        size="icon-sm"
        variant={view === "month" ? "default" : "outline"}
        onClick={() => goTo("month")}
      >
        <Grid2x2 className="size-4" />
      </Button>

      <Button
        aria-label="View by year"
        size="icon-sm"
        variant={view === "year" ? "default" : "outline"}
        onClick={() => goTo("year")}
      >
        <Grid3x3 className="size-4" />
      </Button>

      <Button
        aria-label="View by agenda"
        size="icon-sm"
        variant={view === "agenda" ? "default" : "outline"}
        onClick={() => goTo("agenda")}
      >
        <CalendarRange className="size-4" />
      </Button>
    </ButtonGroup>
  )
}
