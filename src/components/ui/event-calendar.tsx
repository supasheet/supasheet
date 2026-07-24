import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import type { Dispatch, HTMLAttributes, SetStateAction } from "react"

import {
  DndContext,
  DragOverlay,
  PointerSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
} from "@dnd-kit/core"
import type { DragEndEvent, DragStartEvent } from "@dnd-kit/core"
import { cva } from "class-variance-authority"
import type { VariantProps } from "class-variance-authority"
import {
  addDays,
  addMonths,
  addWeeks,
  addYears,
  areIntervalsOverlapping,
  differenceInDays,
  differenceInMilliseconds,
  differenceInMinutes,
  eachDayOfInterval,
  endOfDay,
  endOfMonth,
  endOfWeek,
  endOfYear,
  format,
  formatDate,
  getDaysInMonth,
  isAfter,
  isBefore,
  isSameDay,
  isSameMonth,
  isSameWeek,
  isSameYear,
  isToday,
  isWithinInterval,
  parseISO,
  startOfDay,
  startOfMonth,
  startOfWeek,
  startOfYear,
  subDays,
  subMonths,
  subWeeks,
  subYears,
} from "date-fns"
import {
  CalendarIcon,
  CalendarX2,
  ChevronLeft,
  ChevronRight,
  Clock,
} from "lucide-react"

import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { Calendar } from "#/components/ui/calendar"
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "#/components/ui/context-menu"
import { ScrollArea, ScrollBar } from "#/components/ui/scroll-area"
import { cn } from "#/lib/utils"

export type TCalendarView = "day" | "week" | "month" | "year" | "agenda"
export type TEventColor =
  "blue" | "green" | "red" | "yellow" | "purple" | "orange" | "gray"
export type TBadgeVariant = "dot" | "colored" | "mixed"
export type TWorkingHours = { [key: number]: { from: number; to: number } }
export type TVisibleHours = { from: number; to: number }

export type IEvent = {
  id?: string
  title: string
  startDate: string
  endDate: string
  color: TEventColor
  data: Record<string, unknown>
}

export type ICalendarCell = {
  day: number
  currentMonth: boolean
  date: Date
}

const WORKING_HOURS = {
  0: { from: 0, to: 24 },
  1: { from: 0, to: 24 },
  2: { from: 0, to: 24 },
  3: { from: 0, to: 24 },
  4: { from: 0, to: 24 },
  5: { from: 0, to: 24 },
  6: { from: 0, to: 24 },
}

const VISIBLE_HOURS = { from: 0, to: 24 }

function rangeText(view: TCalendarView, date: Date) {
  const formatString = "MMM d, yyyy"
  let start: Date
  let end: Date

  switch (view) {
    case "agenda":
      start = startOfMonth(date)
      end = endOfMonth(date)
      break
    case "year":
      start = startOfYear(date)
      end = endOfYear(date)
      break
    case "month":
      start = startOfMonth(date)
      end = endOfMonth(date)
      break
    case "week":
      start = startOfWeek(date)
      end = endOfWeek(date)
      break
    case "day":
      return format(date, formatString)
    default:
      return "Error while formatting "
  }

  return `${format(start, formatString)} - ${format(end, formatString)}`
}

function navigateDate(
  date: Date,
  view: TCalendarView,
  direction: "previous" | "next"
): Date {
  const operations = {
    agenda: direction === "next" ? addMonths : subMonths,
    year: direction === "next" ? addYears : subYears,
    month: direction === "next" ? addMonths : subMonths,
    week: direction === "next" ? addWeeks : subWeeks,
    day: direction === "next" ? addDays : subDays,
  }

  return operations[view](date, 1)
}

function getEventsCount(
  events: IEvent[],
  date: Date,
  view: TCalendarView
): number {
  const compareFns = {
    agenda: isSameMonth,
    year: isSameYear,
    day: isSameDay,
    week: isSameWeek,
    month: isSameMonth,
  }

  return events.filter((event) =>
    compareFns[view](new Date(event.startDate), date)
  ).length
}

function getCurrentEvents(events: IEvent[]) {
  const now = new Date()
  return (
    events.filter((event) =>
      isWithinInterval(now, {
        start: parseISO(event.startDate),
        end: parseISO(event.endDate),
      })
    ) || null
  )
}

function groupEvents(dayEvents: IEvent[]) {
  const sortedEvents = dayEvents.sort(
    (a, b) => parseISO(a.startDate).getTime() - parseISO(b.startDate).getTime()
  )
  const groups: IEvent[][] = []

  for (const event of sortedEvents) {
    const eventStart = parseISO(event.startDate)

    let placed = false
    for (const group of groups) {
      const lastEventInGroup = group[group.length - 1]
      const lastEventEnd = parseISO(lastEventInGroup.endDate)

      if (eventStart >= lastEventEnd) {
        group.push(event)
        placed = true
        break
      }
    }

    if (!placed) groups.push([event])
  }

  return groups
}

function getEventBlockStyle(
  event: IEvent,
  day: Date,
  groupIndex: number,
  groupSize: number,
  visibleHoursRange?: { from: number; to: number }
) {
  const startDate = parseISO(event.startDate)
  const dayStart = new Date(day.setHours(0, 0, 0, 0))
  const eventStart = startDate < dayStart ? dayStart : startDate
  const startMinutes = differenceInMinutes(eventStart, dayStart)

  let top

  if (visibleHoursRange) {
    const visibleStartMinutes = visibleHoursRange.from * 60
    const visibleEndMinutes = visibleHoursRange.to * 60
    const visibleRangeMinutes = visibleEndMinutes - visibleStartMinutes
    top = ((startMinutes - visibleStartMinutes) / visibleRangeMinutes) * 100
  } else {
    top = (startMinutes / 1440) * 100
  }

  const width = 100 / groupSize
  const left = groupIndex * width

  return { top: `${top}%`, width: `${width}%`, left: `${left}%` }
}

function isWorkingHour(day: Date, hour: number, workingHours: TWorkingHours) {
  const dayIndex = day.getDay()
  const dayHours = workingHours[dayIndex]
  return hour >= dayHours.from && hour < dayHours.to
}

function getVisibleHours(
  visibleHours: TVisibleHours,
  singleDayEvents: IEvent[]
) {
  let earliestEventHour = visibleHours.from
  let latestEventHour = visibleHours.to

  singleDayEvents.forEach((event) => {
    const startHour = parseISO(event.startDate).getHours()
    const endTime = parseISO(event.endDate)
    const endHour = endTime.getHours() + (endTime.getMinutes() > 0 ? 1 : 0)
    if (startHour < earliestEventHour) earliestEventHour = startHour
    if (endHour > latestEventHour) latestEventHour = endHour
  })

  latestEventHour = Math.min(latestEventHour, 24)

  const hours = Array.from(
    { length: latestEventHour - earliestEventHour },
    (_, i) => i + earliestEventHour
  )

  return { hours, earliestEventHour, latestEventHour }
}

function getCalendarCells(selectedDate: Date): ICalendarCell[] {
  const currentYear = selectedDate.getFullYear()
  const currentMonth = selectedDate.getMonth()

  const getDaysInMonthFn = (year: number, month: number) =>
    new Date(year, month + 1, 0).getDate()
  const getFirstDayOfMonth = (year: number, month: number) =>
    new Date(year, month, 1).getDay()

  const daysInMonth = getDaysInMonthFn(currentYear, currentMonth)
  const firstDayOfMonth = getFirstDayOfMonth(currentYear, currentMonth)
  const daysInPrevMonth = getDaysInMonthFn(currentYear, currentMonth - 1)
  const totalDays = firstDayOfMonth + daysInMonth

  const prevMonthCells = Array.from({ length: firstDayOfMonth }, (_, i) => ({
    day: daysInPrevMonth - firstDayOfMonth + i + 1,
    currentMonth: false,
    date: new Date(
      currentYear,
      currentMonth - 1,
      daysInPrevMonth - firstDayOfMonth + i + 1
    ),
  }))

  const currentMonthCells = Array.from({ length: daysInMonth }, (_, i) => ({
    day: i + 1,
    currentMonth: true,
    date: new Date(currentYear, currentMonth, i + 1),
  }))

  const nextMonthCells = Array.from(
    { length: (7 - (totalDays % 7)) % 7 },
    (_, i) => ({
      day: i + 1,
      currentMonth: false,
      date: new Date(currentYear, currentMonth + 1, i + 1),
    })
  )

  return [...prevMonthCells, ...currentMonthCells, ...nextMonthCells]
}

function calculateMonthEventPositions(
  multiDayEvents: IEvent[],
  singleDayEvents: IEvent[],
  selectedDate: Date
) {
  const monthStart = startOfMonth(selectedDate)
  const monthEnd = endOfMonth(selectedDate)

  const eventPositions: { [key: string]: number } = {}
  const occupiedPositions: { [key: string]: boolean[] } = {}

  eachDayOfInterval({ start: monthStart, end: monthEnd }).forEach((day) => {
    occupiedPositions[day.toISOString()] = [false, false, false]
  })

  const sortedEvents = [
    ...multiDayEvents.sort((a, b) => {
      const aDuration = differenceInDays(
        parseISO(a.endDate),
        parseISO(a.startDate)
      )
      const bDuration = differenceInDays(
        parseISO(b.endDate),
        parseISO(b.startDate)
      )
      return (
        bDuration - aDuration ||
        parseISO(a.startDate).getTime() - parseISO(b.startDate).getTime()
      )
    }),
    ...singleDayEvents.sort(
      (a, b) =>
        parseISO(a.startDate).getTime() - parseISO(b.startDate).getTime()
    ),
  ]

  sortedEvents.forEach((event) => {
    const eventStart = parseISO(event.startDate)
    const eventEnd = parseISO(event.endDate)
    const eventDays = eachDayOfInterval({
      start: eventStart < monthStart ? monthStart : eventStart,
      end: eventEnd > monthEnd ? monthEnd : eventEnd,
    })

    let position = -1

    for (let i = 0; i < 3; i++) {
      if (
        eventDays.every((day) => {
          const dayPositions = occupiedPositions[startOfDay(day).toISOString()]
          return dayPositions && !dayPositions[i]
        })
      ) {
        position = i
        break
      }
    }

    if (position !== -1) {
      eventDays.forEach((day) => {
        const dayKey = startOfDay(day).toISOString()
        occupiedPositions[dayKey][position] = true
      })
      eventPositions[event.id as string] = position
    }
  })

  return eventPositions
}

function getMonthCellEvents(
  date: Date,
  events: IEvent[],
  eventPositions: Record<string, number>
) {
  const eventsForDate = events.filter((event) => {
    const eventStart = parseISO(event.startDate)
    const eventEnd = parseISO(event.endDate)
    return (
      (date >= eventStart && date <= eventEnd) ||
      isSameDay(date, eventStart) ||
      isSameDay(date, eventEnd)
    )
  })

  return eventsForDate
    .map((event) => ({
      ...event,
      position: eventPositions[event.id as string] ?? -1,
      isMultiDay: event.startDate !== event.endDate,
    }))
    .sort((a, b) => {
      if (a.isMultiDay && !b.isMultiDay) return -1
      if (!a.isMultiDay && b.isMultiDay) return 1
      return a.position - b.position
    })
}

const EventCalendarContext = createContext(
  {} as {
    selectedDate: Date
    setSelectedDate: (date: Date | undefined) => void
    workingHours: TWorkingHours
    visibleHours: TVisibleHours
    events: IEvent[]
    setLocalEvents: Dispatch<SetStateAction<IEvent[]>>
    view: TCalendarView
    badgeVariant: TBadgeVariant
    updateEvent: (event: IEvent) => void
    singleDayEvents: IEvent[]
    multiDayEvents: IEvent[]
    onAddEvent?: ({
      startDate,
      hour,
      minute,
    }: {
      startDate: Date
      hour: number
      minute: number
    }) => void
    onDragEvent?: (event: IEvent) => void
    onEventClick?: (event: IEvent) => void
    onEventView?: (event: IEvent) => void
    onEventUpdate?: (event: IEvent) => void
    onEventDelete?: (event: IEvent) => void
    onViewUpdate?: (view: TCalendarView) => void
  }
)

function EventCalendarProvider({
  children,
  events,
  workingHours = WORKING_HOURS,
  visibleHours = VISIBLE_HOURS,
  view = "day",
  badgeVariant = "dot",
  onAddEvent,
  onDragEvent,
  onEventClick,
  onEventView,
  onEventUpdate,
  onEventDelete,
  onViewUpdate,
}: {
  children: React.ReactNode
  events: IEvent[]
  workingHours?: TWorkingHours
  visibleHours?: TVisibleHours
  view?: TCalendarView
  badgeVariant?: TBadgeVariant
  onAddEvent?: ({
    startDate,
    hour,
    minute,
  }: {
    startDate: Date
    hour: number
    minute: number
  }) => void
  onDragEvent?: (event: IEvent) => void
  onEventClick?: (event: IEvent) => void
  onEventView?: (event: IEvent) => void
  onEventUpdate?: (event: IEvent) => void
  onEventDelete?: (event: IEvent) => void
  onViewUpdate?: (view: TCalendarView) => void
}) {
  const [selectedDate, setSelectedDate] = useState(new Date())
  const [localEvents, setLocalEvents] = useState<IEvent[]>(events)

  useEffect(() => {
    setLocalEvents(events)
  }, [events])

  const filteredEvents = useMemo(() => {
    return localEvents.filter((event) => {
      const eventStartDate = parseISO(event.startDate)
      const eventEndDate = parseISO(event.endDate)

      if (view === "year") {
        const yearStart = new Date(selectedDate.getFullYear(), 0, 1)
        const yearEnd = new Date(
          selectedDate.getFullYear(),
          11,
          31,
          23,
          59,
          59,
          999
        )
        const isInSelectedYear =
          eventStartDate <= yearEnd && eventEndDate >= yearStart
        return isInSelectedYear
      }

      if (view === "month" || view === "agenda") {
        const monthStart = new Date(
          selectedDate.getFullYear(),
          selectedDate.getMonth(),
          1
        )
        const monthEnd = new Date(
          selectedDate.getFullYear(),
          selectedDate.getMonth() + 1,
          0,
          23,
          59,
          59,
          999
        )
        const isInSelectedMonth =
          eventStartDate <= monthEnd && eventEndDate >= monthStart
        return isInSelectedMonth
      }

      if (view === "week") {
        const dayOfWeek = selectedDate.getDay()

        const weekStart = new Date(selectedDate)
        weekStart.setDate(selectedDate.getDate() - dayOfWeek)
        weekStart.setHours(0, 0, 0, 0)

        const weekEnd = new Date(weekStart)
        weekEnd.setDate(weekStart.getDate() + 6)
        weekEnd.setHours(23, 59, 59, 999)

        const isInSelectedWeek =
          eventStartDate <= weekEnd && eventEndDate >= weekStart
        return isInSelectedWeek
      }

      if (view === "day") {
        const dayStart = new Date(
          selectedDate.getFullYear(),
          selectedDate.getMonth(),
          selectedDate.getDate(),
          0,
          0,
          0
        )
        const dayEnd = new Date(
          selectedDate.getFullYear(),
          selectedDate.getMonth(),
          selectedDate.getDate(),
          23,
          59,
          59
        )
        const isInSelectedDay =
          eventStartDate <= dayEnd && eventEndDate >= dayStart
        return isInSelectedDay
      }
    })
  }, [selectedDate, localEvents, view])

  const singleDayEvents = filteredEvents.filter((event) => {
    const startDate = parseISO(event.startDate)
    const endDate = parseISO(event.endDate)
    return isSameDay(startDate, endDate)
  })

  const multiDayEvents = filteredEvents.filter((event) => {
    const startDate = parseISO(event.startDate)
    const endDate = parseISO(event.endDate)
    return !isSameDay(startDate, endDate)
  })

  const handleSelectDate = (date: Date | undefined) => {
    if (!date) return
    setSelectedDate(date)
  }

  const updateEvent = (event: IEvent) => {
    onDragEvent?.(event)
    const newEvent: IEvent = event

    newEvent.startDate = new Date(event.startDate).toISOString()
    newEvent.endDate = new Date(event.endDate).toISOString()

    setLocalEvents((prev) => {
      const index = prev.findIndex((e) => e.id === event.id)
      if (index === -1) return prev
      return [...prev.slice(0, index), newEvent, ...prev.slice(index + 1)]
    })
  }

  return (
    <EventCalendarContext.Provider
      value={{
        selectedDate,
        setSelectedDate: handleSelectDate,
        visibleHours,
        workingHours,
        events: localEvents,
        setLocalEvents,
        view,
        badgeVariant,
        updateEvent,
        singleDayEvents,
        multiDayEvents,
        onAddEvent,
        onDragEvent,
        onEventClick,
        onEventView,
        onEventUpdate,
        onEventDelete,
        onViewUpdate,
      }}
    >
      {children}
    </EventCalendarContext.Provider>
  )
}

function useEventCalendar() {
  const context = useContext(EventCalendarContext)
  if (!context)
    throw new Error(
      "useEventCalendar must be used within a EventCalendarProvider."
    )
  return context
}

function CustomDragLayer({
  activeId,
  activeData,
}: {
  activeId: string | null
  activeData: {
    event: IEvent
    children: React.ReactNode
    width: number
    height: number
  } | null
}) {
  return (
    <DragOverlay dropAnimation={null}>
      {activeId && activeData ? (
        <div
          style={{
            width: activeData.width,
            height: activeData.height,
            cursor: "grabbing",
          }}
        >
          {activeData.children}
        </div>
      ) : null}
    </DragOverlay>
  )
}

function DndProviderWrapper({ children }: { children: React.ReactNode }) {
  const [activeId, setActiveId] = useState<string | null>(null)
  const [activeData, setActiveData] = useState<{
    event: IEvent
    children: React.ReactNode
    width: number
    height: number
  } | null>(null)
  const { updateEvent } = useEventCalendar()

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 8,
      },
    })
  )

  function handleDragStart(event: DragStartEvent) {
    setActiveId(event.active.id as string)
    setActiveData(
      event.active.data.current as {
        event: IEvent
        children: React.ReactNode
        width: number
        height: number
      } | null
    )
  }

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event

    if (over && active.data.current?.event) {
      const droppedEvent = active.data.current.event as IEvent
      const overData = over.data.current

      if (overData?.type === "day-cell") {
        const cell = overData.cell
        const eventStartDate = parseISO(droppedEvent.startDate)
        const eventEndDate = parseISO(droppedEvent.endDate)
        const eventDurationMs = differenceInMilliseconds(
          eventEndDate,
          eventStartDate
        )

        const newStartDate = new Date(cell.date)
        newStartDate.setHours(
          eventStartDate.getHours(),
          eventStartDate.getMinutes(),
          eventStartDate.getSeconds(),
          eventStartDate.getMilliseconds()
        )
        const newEndDate = new Date(newStartDate.getTime() + eventDurationMs)

        updateEvent({
          ...droppedEvent,
          startDate: newStartDate.toISOString(),
          endDate: newEndDate.toISOString(),
        })
      } else if (overData?.type === "time-block") {
        const { date, hour, minute } = overData
        const eventStartDate = parseISO(droppedEvent.startDate)
        const eventEndDate = parseISO(droppedEvent.endDate)
        const eventDurationMs = differenceInMilliseconds(
          eventEndDate,
          eventStartDate
        )

        const newStartDate = new Date(date)
        newStartDate.setHours(hour, minute, 0, 0)
        const newEndDate = new Date(newStartDate.getTime() + eventDurationMs)

        updateEvent({
          ...droppedEvent,
          startDate: newStartDate.toISOString(),
          endDate: newEndDate.toISOString(),
        })
      }
    }

    setActiveId(null)
    setActiveData(null)
  }

  return (
    <DndContext
      sensors={sensors}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
    >
      {children}
      <CustomDragLayer activeId={activeId} activeData={activeData} />
    </DndContext>
  )
}

function DraggableEvent({
  event,
  children,
  segmentId,
}: {
  event: IEvent
  children: React.ReactNode
  segmentId: string
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 })

  useEffect(() => {
    if (ref.current) {
      setDimensions({
        width: ref.current.offsetWidth,
        height: ref.current.offsetHeight,
      })
    }
  }, [children])

  const draggableId = `${event.id}-${segmentId}`

  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: draggableId,
    data: {
      event,
      children,
      width: dimensions.width,
      height: dimensions.height,
    },
  })

  useEffect(() => {
    setNodeRef(ref.current)
  }, [setNodeRef])

  return (
    <div
      ref={ref}
      {...listeners}
      {...attributes}
      className={cn(isDragging && "opacity-40")}
    >
      {children}
    </div>
  )
}

function DroppableDayCell({
  cell,
  children,
}: {
  cell: ICalendarCell
  children: React.ReactNode
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: `day-cell-${cell.date}`,
    data: {
      type: "day-cell",
      cell,
    },
  })

  return (
    <div ref={setNodeRef} className={cn(isOver && "bg-accent/50")}>
      {children}
    </div>
  )
}

function DroppableTimeBlock({
  date,
  hour,
  minute,
  children,
}: {
  date: Date
  hour: number
  minute: number
  children: React.ReactNode
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: `time-block-${date.toISOString()}-${hour}-${minute}`,
    data: {
      type: "time-block",
      date,
      hour,
      minute,
    },
  })

  return (
    <div ref={setNodeRef} className={cn("h-[24px]", isOver && "bg-accent/50")}>
      {children}
    </div>
  )
}

export function EventCalendarRoot({
  children,
  ...props
}: {
  children: React.ReactNode
  events: IEvent[]
  workingHours?: TWorkingHours
  visibleHours?: TVisibleHours
  view?: TCalendarView
  badgeVariant?: TBadgeVariant
  onAddEvent?: ({
    startDate,
    hour,
    minute,
  }: {
    startDate: Date
    hour: number
    minute: number
  }) => void
  onDragEvent?: (event: IEvent) => void
  onEventClick?: (event: IEvent) => void
  onEventView?: (event: IEvent) => void
  onEventUpdate?: (event: IEvent) => void
  onEventDelete?: (event: IEvent) => void
  onViewUpdate?: (view: TCalendarView) => void
}) {
  return (
    <EventCalendarProvider {...props}>
      <div className="overflow-hidden rounded-xl border">{children}</div>
    </EventCalendarProvider>
  )
}

export function EventCalendarContainer({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <DndProviderWrapper>
      <ScrollArea className="h-[calc(100svh-160px)]">
        {children}
        <ScrollBar orientation="vertical" className="relative z-30" />
      </ScrollArea>
    </DndProviderWrapper>
  )
}

export function EventCalendarHeader({
  children,
}: {
  children?: React.ReactNode
}) {
  const { selectedDate, setSelectedDate, events, view } = useEventCalendar()

  const today = new Date()
  const handleClick = () => setSelectedDate(today)

  const month = formatDate(selectedDate, "MMMM")
  const year = selectedDate.getFullYear()

  const eventCount = useMemo(
    () => getEventsCount(events, selectedDate, view),
    [events, selectedDate, view]
  )

  const handlePrevious = () =>
    setSelectedDate(navigateDate(selectedDate, view, "previous"))
  const handleNext = () =>
    setSelectedDate(navigateDate(selectedDate, view, "next"))

  return (
    <div className="flex flex-col gap-4 border-b p-4 lg:flex-row lg:items-center lg:justify-between">
      <div className="flex flex-1 items-center gap-3">
        <div className="flex flex-1 items-center gap-2">
          <Button size={"icon-sm"} onClick={handleClick}>
            {today.getDate()}
          </Button>
          <span className="text-lg font-semibold">
            {month} {year}
          </span>
          <Badge variant="outline" className="px-1.5">
            {eventCount} events
          </Badge>
        </div>

        <div className="space-y-0.5">
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              className="size-6.5 px-0 [&_svg]:size-4.5"
              onClick={handlePrevious}
            >
              <ChevronLeft />
            </Button>

            <p className="text-sm text-muted-foreground">
              {rangeText(view, selectedDate)}
            </p>

            <Button
              variant="outline"
              className="size-6.5 px-0 [&_svg]:size-4.5"
              onClick={handleNext}
            >
              <ChevronRight />
            </Button>
          </div>
        </div>
      </div>
      {children}
    </div>
  )
}

const agendaEventCardVariants = cva(
  "flex items-center justify-between gap-3 rounded-md border p-3 text-sm select-none focus-visible:ring-1 focus-visible:ring-ring focus-visible:outline-none",
  {
    variants: {
      color: {
        blue: "border-blue-200 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-300 [&_.event-dot]:fill-blue-600",
        green:
          "border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-300 [&_.event-dot]:fill-green-600",
        red: "border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-300 [&_.event-dot]:fill-red-600",
        yellow:
          "border-yellow-200 bg-yellow-50 text-yellow-700 dark:border-yellow-800 dark:bg-yellow-950 dark:text-yellow-300 [&_.event-dot]:fill-yellow-600",
        purple:
          "border-purple-200 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950 dark:text-purple-300 [&_.event-dot]:fill-purple-600",
        orange:
          "border-orange-200 bg-orange-50 text-orange-700 dark:border-orange-800 dark:bg-orange-950 dark:text-orange-300 [&_.event-dot]:fill-orange-600",
        gray: "border-neutral-200 bg-neutral-50 text-neutral-900 dark:border-neutral-700 dark:bg-neutral-900 dark:text-neutral-300 [&_.event-dot]:fill-neutral-600",
        "blue-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-blue-600",
        "green-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-green-600",
        "red-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-red-600",
        "orange-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-orange-600",
        "purple-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-purple-600",
        "yellow-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-yellow-600",
        "gray-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-neutral-600",
      },
    },
    defaultVariants: {
      color: "blue-dot",
    },
  }
)

function AgendaEventCard({
  event,
  eventCurrentDay,
  eventTotalDays,
}: {
  event: IEvent
  eventCurrentDay?: number
  eventTotalDays?: number
}) {
  const {
    badgeVariant,
    onEventClick,
    onEventView,
    onEventUpdate,
    onEventDelete,
  } = useEventCalendar()

  const startDate = parseISO(event.startDate)
  const endDate = parseISO(event.endDate)

  const color = (
    badgeVariant === "dot" ? `${event.color}-dot` : event.color
  ) as VariantProps<typeof agendaEventCardVariants>["color"]

  const agendaEventCardClasses = agendaEventCardVariants({ color })

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault()
      if (e.currentTarget instanceof HTMLElement) e.currentTarget.click()
    }
  }

  const hasContextMenu = onEventView || onEventUpdate || onEventDelete

  const cardContent = (
    <div
      role="button"
      tabIndex={0}
      className={agendaEventCardClasses}
      onKeyDown={handleKeyDown}
      onClick={() => onEventClick?.(event)}
    >
      <div className="flex flex-col gap-2">
        <div className="flex items-center gap-1.5">
          {["mixed", "dot"].includes(badgeVariant) && (
            <svg
              width="8"
              height="8"
              viewBox="0 0 8 8"
              className="event-dot shrink-0"
            >
              <circle cx="4" cy="4" r="4" />
            </svg>
          )}

          <p className="font-medium">
            {eventCurrentDay && eventTotalDays && (
              <span className="mr-1 text-xs">
                Day {eventCurrentDay} of {eventTotalDays} •{" "}
              </span>
            )}
            {event.title}
          </p>
        </div>

        <div className="flex items-center gap-1">
          <Clock className="size-3 shrink-0" />
          <p className="text-xs text-foreground">
            {format(startDate, "h:mm a")} - {format(endDate, "h:mm a")}
          </p>
        </div>
      </div>
    </div>
  )

  if (!hasContextMenu) {
    return cardContent
  }

  return (
    <ContextMenu>
      <ContextMenuTrigger>{cardContent}</ContextMenuTrigger>
      <ContextMenuContent className="w-52">
        {onEventView && (
          <ContextMenuItem onClick={() => onEventView(event)}>
            View Details
          </ContextMenuItem>
        )}
        {onEventUpdate && (
          <ContextMenuItem onClick={() => onEventUpdate(event)}>
            Edit Details
          </ContextMenuItem>
        )}
        {(onEventView || onEventUpdate) && onEventDelete && (
          <ContextMenuSeparator />
        )}
        {onEventDelete && (
          <ContextMenuItem
            variant="destructive"
            onClick={() => onEventDelete(event)}
          >
            Delete Event
          </ContextMenuItem>
        )}
      </ContextMenuContent>
    </ContextMenu>
  )
}

function AgendaDayGroup({
  date,
  events,
  multiDayEvents,
}: {
  date: Date
  events: IEvent[]
  multiDayEvents: IEvent[]
}) {
  const sortedEvents = [...events].sort(
    (a, b) => new Date(a.startDate).getTime() - new Date(b.startDate).getTime()
  )

  return (
    <div className="space-y-4">
      <div className="sticky top-0 flex items-center gap-4 bg-background py-2">
        <p className="text-sm font-semibold">
          {format(date, "EEEE, MMMM d, yyyy")}
        </p>
      </div>

      <div className="space-y-2">
        {multiDayEvents.length > 0 &&
          multiDayEvents.map((event) => {
            const eventStart = startOfDay(parseISO(event.startDate))
            const eventEnd = startOfDay(parseISO(event.endDate))
            const currentDate = startOfDay(date)

            const eventTotalDays = differenceInDays(eventEnd, eventStart) + 1
            const eventCurrentDay =
              differenceInDays(currentDate, eventStart) + 1
            return (
              <AgendaEventCard
                key={event.id}
                event={event}
                eventCurrentDay={eventCurrentDay}
                eventTotalDays={eventTotalDays}
              />
            )
          })}

        {sortedEvents.length > 0 &&
          sortedEvents.map((event) => (
            <AgendaEventCard key={event.id} event={event} />
          ))}
      </div>
    </div>
  )
}

export function EventCalendarAgendaView() {
  const { selectedDate, singleDayEvents, multiDayEvents, view } =
    useEventCalendar()

  const eventsByDay = useMemo(() => {
    const allDates = new Map<
      string,
      { date: Date; events: IEvent[]; multiDayEvents: IEvent[] }
    >()

    singleDayEvents.forEach((event) => {
      const eventDate = parseISO(event.startDate)
      if (!isSameMonth(eventDate, selectedDate)) return

      const dateKey = format(eventDate, "yyyy-MM-dd")

      if (!allDates.has(dateKey)) {
        allDates.set(dateKey, {
          date: startOfDay(eventDate),
          events: [],
          multiDayEvents: [],
        })
      }

      allDates.get(dateKey)?.events.push(event)
    })

    multiDayEvents.forEach((event) => {
      const eventStart = parseISO(event.startDate)
      const eventEnd = parseISO(event.endDate)

      let currentDate = startOfDay(eventStart)
      const lastDate = endOfDay(eventEnd)

      while (currentDate <= lastDate) {
        if (isSameMonth(currentDate, selectedDate)) {
          const dateKey = format(currentDate, "yyyy-MM-dd")

          if (!allDates.has(dateKey)) {
            allDates.set(dateKey, {
              date: new Date(currentDate),
              events: [],
              multiDayEvents: [],
            })
          }

          allDates.get(dateKey)?.multiDayEvents.push(event)
        }
        currentDate = new Date(currentDate.setDate(currentDate.getDate() + 1))
      }
    })

    return Array.from(allDates.values()).sort(
      (a, b) => a.date.getTime() - b.date.getTime()
    )
  }, [singleDayEvents, multiDayEvents, selectedDate])

  if (view !== "agenda") return null

  const hasAnyEvents = singleDayEvents.length > 0 || multiDayEvents.length > 0

  return (
    <div className="h-full">
      <ScrollArea className="h-full">
        <div className="space-y-6 p-4">
          {eventsByDay.map((dayGroup) => (
            <AgendaDayGroup
              key={format(dayGroup.date, "yyyy-MM-dd")}
              date={dayGroup.date}
              events={dayGroup.events}
              multiDayEvents={dayGroup.multiDayEvents}
            />
          ))}

          {!hasAnyEvents && (
            <div className="flex flex-col items-center justify-center gap-2 py-20 text-muted-foreground">
              <CalendarX2 className="size-10" />
              <p className="text-sm md:text-base">
                No events scheduled for the selected month
              </p>
            </div>
          )}
        </div>
      </ScrollArea>
    </div>
  )
}

function YearViewDayCell({
  day,
  date,
  events,
}: {
  day: number
  date: Date
  events: IEvent[]
}) {
  const { setSelectedDate, onViewUpdate } = useEventCalendar()

  const maxIndicators = 3
  const eventCount = events.length

  const handleClick = () => {
    setSelectedDate(date)
    onViewUpdate?.("day")
  }

  return (
    <button
      onClick={handleClick}
      type="button"
      className="flex h-11 flex-1 flex-col items-center justify-start gap-0.5 rounded-md pt-1 hover:bg-accent focus-visible:ring-1 focus-visible:ring-ring focus-visible:outline-none"
    >
      <div
        className={cn(
          "flex size-6 items-center justify-center rounded-full text-xs font-medium",
          isToday(date) && "bg-primary font-semibold text-primary-foreground"
        )}
      >
        {day}
      </div>

      {eventCount > 0 && (
        <div className="mt-0.5 flex gap-0.5">
          {eventCount <= maxIndicators ? (
            events.map((event) => (
              <div
                key={event.id}
                className={cn(
                  "size-1.5 rounded-full",
                  event.color === "blue" && "bg-blue-600",
                  event.color === "green" && "bg-green-600",
                  event.color === "red" && "bg-red-600",
                  event.color === "yellow" && "bg-yellow-600",
                  event.color === "purple" && "bg-purple-600",
                  event.color === "orange" && "bg-orange-600",
                  event.color === "gray" && "bg-neutral-600"
                )}
              />
            ))
          ) : (
            <>
              <div
                className={cn(
                  "size-1.5 rounded-full",
                  events[0].color === "blue" && "bg-blue-600",
                  events[0].color === "green" && "bg-green-600",
                  events[0].color === "red" && "bg-red-600",
                  events[0].color === "yellow" && "bg-yellow-600",
                  events[0].color === "purple" && "bg-purple-600",
                  events[0].color === "orange" && "bg-orange-600"
                )}
              />
              <span className="text-[7px] text-muted-foreground">
                +{eventCount - 1}
              </span>
            </>
          )}
        </div>
      )}
    </button>
  )
}

function YearViewMonth({ month, events }: { month: Date; events: IEvent[] }) {
  const { setSelectedDate, onViewUpdate } = useEventCalendar()

  const monthName = format(month, "MMMM")

  const daysInMonth = useMemo(() => {
    const totalDays = getDaysInMonth(month)
    const firstDay = startOfMonth(month).getDay()

    const days = Array.from({ length: totalDays }, (_, i) => i + 1)
    const blanks = Array(firstDay).fill(null)

    return [...blanks, ...days]
  }, [month])

  const weekDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  const handleClick = () => {
    setSelectedDate(new Date(month.getFullYear(), month.getMonth(), 1))
    onViewUpdate?.("month")
  }

  return (
    <div className="flex flex-col">
      <button
        type="button"
        onClick={handleClick}
        className="w-full rounded-t-lg border px-3 py-2 text-sm font-semibold hover:bg-accent focus-visible:ring-1 focus-visible:ring-ring focus-visible:outline-none"
      >
        {monthName}
      </button>

      <div className="flex-1 space-y-2 rounded-b-lg border border-t-0 p-3">
        <div className="grid grid-cols-7 gap-x-0.5 text-center">
          {weekDays.map((day, index) => (
            <div
              key={index}
              className="text-xs font-medium text-muted-foreground"
            >
              {day}
            </div>
          ))}
        </div>

        <div className="grid grid-cols-7 gap-x-0.5 gap-y-2">
          {daysInMonth.map((day, index) => {
            if (day === null)
              return <div key={`blank-${index}`} className="h-10" />

            const date = new Date(month.getFullYear(), month.getMonth(), day)
            const dayEvents = events.filter(
              (event) =>
                isSameDay(parseISO(event.startDate), date) ||
                isSameDay(parseISO(event.endDate), date)
            )

            return (
              <YearViewDayCell
                key={`day-${day}`}
                day={day}
                date={date}
                events={dayEvents}
              />
            )
          })}
        </div>
      </div>
    </div>
  )
}

export function EventCalendarYearView() {
  const { selectedDate, singleDayEvents, multiDayEvents, view } =
    useEventCalendar()

  const months = useMemo(() => {
    const yearStart = startOfYear(selectedDate)
    return Array.from({ length: 12 }, (_, i) => addMonths(yearStart, i))
  }, [selectedDate])

  if (view !== "year") return null

  const allEvents = [...singleDayEvents, ...multiDayEvents]

  return (
    <div className="h-max p-4">
      <div className="grid h-max grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {months.map((month) => (
          <YearViewMonth
            key={month.toString()}
            month={month}
            events={allEvents}
          />
        ))}
      </div>
    </div>
  )
}

const WEEK_DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

const MAX_VISIBLE_EVENTS = 3

const eventBadgeVariants = cva(
  "mx-1 flex size-auto h-6.5 items-center justify-between gap-1.5 truncate rounded-md border px-2 text-xs whitespace-nowrap select-none focus-visible:ring-1 focus-visible:ring-ring focus-visible:outline-none",
  {
    variants: {
      color: {
        blue: "border-blue-200 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-300 [&_.event-dot]:fill-blue-600",
        green:
          "border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-300 [&_.event-dot]:fill-green-600",
        red: "border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-300 [&_.event-dot]:fill-red-600",
        yellow:
          "border-yellow-200 bg-yellow-50 text-yellow-700 dark:border-yellow-800 dark:bg-yellow-950 dark:text-yellow-300 [&_.event-dot]:fill-yellow-600",
        purple:
          "border-purple-200 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950 dark:text-purple-300 [&_.event-dot]:fill-purple-600",
        orange:
          "border-orange-200 bg-orange-50 text-orange-700 dark:border-orange-800 dark:bg-orange-950 dark:text-orange-300 [&_.event-dot]:fill-orange-600",
        gray: "border-neutral-200 bg-neutral-50 text-neutral-900 dark:border-neutral-700 dark:bg-neutral-900 dark:text-neutral-300 [&_.event-dot]:fill-neutral-600",
        "blue-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-blue-600",
        "green-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-green-600",
        "red-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-red-600",
        "yellow-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-yellow-600",
        "purple-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-purple-600",
        "orange-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-orange-600",
        "gray-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-neutral-600",
      },
      multiDayPosition: {
        first:
          "relative z-10 mr-0 w-[calc(100%_-_3px)] rounded-r-none border-r-0 [&>span]:mr-2.5",
        middle:
          "relative z-10 mx-0 w-[calc(100%_+_1px)] rounded-none border-x-0",
        last: "ml-0 rounded-l-none border-l-0",
        none: "",
      },
    },
    defaultVariants: {
      color: "blue-dot",
    },
  }
)

function MonthEventBadge({
  event,
  cellDate,
  eventCurrentDay,
  eventTotalDays,
  className,
  position: propPosition,
  segmentId,
}: {
  event: IEvent
  cellDate: Date
  eventCurrentDay?: number
  eventTotalDays?: number
  className?: string
  position?: "first" | "middle" | "last" | "none"
  segmentId: string
} & Omit<
  VariantProps<typeof eventBadgeVariants>,
  "color" | "multiDayPosition"
>) {
  const {
    badgeVariant,
    onEventClick,
    onEventView,
    onEventUpdate,
    onEventDelete,
  } = useEventCalendar()

  const itemStart = startOfDay(parseISO(event.startDate))
  const itemEnd = endOfDay(parseISO(event.endDate))

  if (cellDate < itemStart || cellDate > itemEnd) return null

  let position: "first" | "middle" | "last" | "none" | undefined

  if (propPosition) {
    position = propPosition
  } else if (eventCurrentDay && eventTotalDays) {
    position = "none"
  } else if (isSameDay(itemStart, itemEnd)) {
    position = "none"
  } else if (isSameDay(cellDate, itemStart)) {
    position = "first"
  } else if (isSameDay(cellDate, itemEnd)) {
    position = "last"
  } else {
    position = "middle"
  }

  const renderBadgeText = ["first", "none"].includes(position)

  const color = (
    badgeVariant === "dot" ? `${event.color}-dot` : event.color
  ) as VariantProps<typeof eventBadgeVariants>["color"]

  const eventBadgeClasses = cn(
    eventBadgeVariants({ color, multiDayPosition: position, className })
  )

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault()
      if (e.currentTarget instanceof HTMLElement) e.currentTarget.click()
    }
  }

  const hasContextMenu = onEventView || onEventUpdate || onEventDelete

  const badgeContent = (
    <DraggableEvent event={event} segmentId={segmentId}>
      <div
        role="button"
        tabIndex={0}
        className={eventBadgeClasses}
        onKeyDown={handleKeyDown}
        onClick={(e) => {
          e.stopPropagation()
          onEventClick?.(event)
        }}
      >
        <div className="flex items-center gap-1.5 truncate">
          {!["middle", "last"].includes(position) &&
            ["mixed", "dot"].includes(badgeVariant) && (
              <svg
                width="8"
                height="8"
                viewBox="0 0 8 8"
                className="event-dot shrink-0"
              >
                <circle cx="4" cy="4" r="4" />
              </svg>
            )}

          {renderBadgeText && (
            <p className="flex-1 truncate font-semibold">
              {eventCurrentDay && (
                <span className="text-xs">
                  Day {eventCurrentDay} of {eventTotalDays} •{" "}
                </span>
              )}
              {event.title}
            </p>
          )}
        </div>

        {renderBadgeText && (
          <span>{format(new Date(event.startDate), "h:mm a")}</span>
        )}
      </div>
    </DraggableEvent>
  )

  if (!hasContextMenu) {
    return badgeContent
  }

  return (
    <ContextMenu>
      <ContextMenuTrigger>{badgeContent}</ContextMenuTrigger>
      <ContextMenuContent className="w-52">
        {onEventView && (
          <ContextMenuItem onClick={() => onEventView(event)}>
            View Details
          </ContextMenuItem>
        )}
        {onEventUpdate && (
          <ContextMenuItem onClick={() => onEventUpdate(event)}>
            Edit Details
          </ContextMenuItem>
        )}
        {(onEventView || onEventUpdate) && onEventDelete && (
          <ContextMenuSeparator />
        )}
        {onEventDelete && (
          <ContextMenuItem
            variant="destructive"
            onClick={() => onEventDelete(event)}
          >
            Delete Event
          </ContextMenuItem>
        )}
      </ContextMenuContent>
    </ContextMenu>
  )
}

const eventBulletVariants = cva("size-2 rounded-full", {
  variants: {
    color: {
      blue: "bg-blue-600 dark:bg-blue-500",
      green: "bg-green-600 dark:bg-green-500",
      red: "bg-red-600 dark:bg-red-500",
      yellow: "bg-yellow-600 dark:bg-yellow-500",
      purple: "bg-purple-600 dark:bg-purple-500",
      gray: "bg-neutral-600 dark:bg-neutral-500",
      orange: "bg-orange-600 dark:bg-orange-500",
    },
  },
  defaultVariants: {
    color: "blue",
  },
})

function EventBullet({
  color,
  className,
}: {
  color: TEventColor
  className: string
}) {
  return <div className={cn(eventBulletVariants({ color, className }))} />
}

function DayCell({
  cell,
  events,
  eventPositions,
}: {
  cell: ICalendarCell
  events: IEvent[]
  eventPositions: Record<string, number>
}) {
  const { setSelectedDate, onViewUpdate, onAddEvent } = useEventCalendar()

  const { day, currentMonth, date } = cell

  const cellEvents = useMemo(
    () => getMonthCellEvents(date, events, eventPositions),
    [date, events, eventPositions]
  )
  const isSunday = date.getDay() === 0

  const handleClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    setSelectedDate(date)
    onViewUpdate?.("day")
  }

  return (
    <DroppableDayCell cell={cell}>
      <div
        className={cn(
          "flex h-full flex-col gap-1 border-t border-l py-1.5 lg:pt-1 lg:pb-2",
          isSunday && "border-l-0",
          onAddEvent && "cursor-pointer transition-colors hover:bg-accent/30"
        )}
        onClick={
          onAddEvent
            ? () => onAddEvent({ startDate: date, hour: 0, minute: 0 })
            : undefined
        }
      >
        <button
          onClick={handleClick}
          className={cn(
            "flex size-6 translate-x-1 items-center justify-center rounded-full text-xs font-semibold hover:bg-accent focus-visible:ring-1 focus-visible:ring-ring focus-visible:outline-none lg:px-2",
            !currentMonth && "opacity-20",
            isToday(date) &&
              "bg-primary font-bold text-primary-foreground hover:bg-primary"
          )}
        >
          {day}
        </button>

        <div
          className={cn(
            "flex h-6 gap-1 px-2 lg:h-[94px] lg:flex-col lg:gap-2 lg:px-0",
            !currentMonth && "opacity-50"
          )}
        >
          {[0, 1, 2].map((position) => {
            const event = cellEvents.find((e) => e.position === position)
            const eventKey = event
              ? `event-${event.id}-${position}`
              : `empty-${position}`

            return (
              <div key={eventKey} className="lg:flex-1">
                {event && (
                  <>
                    <EventBullet className="lg:hidden" color={event.color} />
                    <MonthEventBadge
                      className="hidden lg:flex"
                      event={event}
                      cellDate={startOfDay(date)}
                      segmentId={date.toISOString()}
                    />
                  </>
                )}
              </div>
            )
          })}
        </div>

        {cellEvents.length > MAX_VISIBLE_EVENTS && (
          <p
            className={cn(
              "h-4.5 px-1.5 text-xs font-semibold text-muted-foreground",
              !currentMonth && "opacity-50"
            )}
            onClick={(e) => e.stopPropagation()}
          >
            <span className="sm:hidden">
              +{cellEvents.length - MAX_VISIBLE_EVENTS}
            </span>
            <span className="hidden sm:inline">
              {" "}
              {cellEvents.length - MAX_VISIBLE_EVENTS} more...
            </span>
          </p>
        )}
      </div>
    </DroppableDayCell>
  )
}

export function EventCalendarMonthView() {
  const { selectedDate, multiDayEvents, singleDayEvents, view } =
    useEventCalendar()

  const allEvents = [...multiDayEvents, ...singleDayEvents]

  const cells = useMemo(() => getCalendarCells(selectedDate), [selectedDate])

  const eventPositions = useMemo(
    () =>
      calculateMonthEventPositions(
        multiDayEvents,
        singleDayEvents,
        selectedDate
      ),
    [multiDayEvents, singleDayEvents, selectedDate]
  )

  if (view !== "month") return null

  return (
    <>
      <div className="sticky top-0 z-20 grid grid-cols-7">
        {WEEK_DAYS.map((day, index) => (
          <div
            key={day}
            className={cn(
              "flex items-center justify-center bg-background py-2",
              index !== 0 && "border-l"
            )}
          >
            <span className="text-xs font-medium text-muted-foreground">
              {day}
            </span>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-7 overflow-hidden">
        {cells.map((cell) => (
          <DayCell
            key={cell.date.toISOString()}
            cell={cell}
            events={allEvents}
            eventPositions={eventPositions}
          />
        ))}
      </div>
    </>
  )
}

function CalendarTimeline({
  firstVisibleHour,
  lastVisibleHour,
}: {
  firstVisibleHour: number
  lastVisibleHour: number
}) {
  const [currentTime, setCurrentTime] = useState(new Date())

  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(new Date()), 60 * 1000)
    return () => clearInterval(timer)
  }, [])

  const getCurrentTimePosition = () => {
    const minutes = currentTime.getHours() * 60 + currentTime.getMinutes()

    const visibleStartMinutes = firstVisibleHour * 60
    const visibleEndMinutes = lastVisibleHour * 60
    const visibleRangeMinutes = visibleEndMinutes - visibleStartMinutes

    return ((minutes - visibleStartMinutes) / visibleRangeMinutes) * 100
  }

  const formatCurrentTime = () => {
    return format(currentTime, "h:mm a")
  }

  const currentHour = currentTime.getHours()
  if (currentHour < firstVisibleHour || currentHour >= lastVisibleHour)
    return null

  return (
    <div
      className="pointer-events-none absolute inset-x-0 z-50 border-t border-primary"
      style={{ top: `${getCurrentTimePosition()}%` }}
    >
      <div className="absolute top-0 left-0 size-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary"></div>
      <div className="absolute -left-18 flex w-16 -translate-y-1/2 justify-end bg-background pr-1 text-xs font-medium text-primary">
        {formatCurrentTime()}
      </div>
    </div>
  )
}

const calendarWeekEventCardVariants = cva(
  "flex flex-col gap-0.5 truncate rounded-md border px-2 py-1.5 text-xs whitespace-nowrap select-none focus-visible:ring-1 focus-visible:ring-ring focus-visible:outline-none",
  {
    variants: {
      color: {
        blue: "border-blue-200 bg-blue-50 text-blue-700 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-300 [&_.event-dot]:fill-blue-600",
        green:
          "border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-300 [&_.event-dot]:fill-green-600",
        red: "border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-300 [&_.event-dot]:fill-red-600",
        yellow:
          "border-yellow-200 bg-yellow-50 text-yellow-700 dark:border-yellow-800 dark:bg-yellow-950 dark:text-yellow-300 [&_.event-dot]:fill-yellow-600",
        purple:
          "border-purple-200 bg-purple-50 text-purple-700 dark:border-purple-800 dark:bg-purple-950 dark:text-purple-300 [&_.event-dot]:fill-purple-600",
        orange:
          "border-orange-200 bg-orange-50 text-orange-700 dark:border-orange-800 dark:bg-orange-950 dark:text-orange-300 [&_.event-dot]:fill-orange-600",
        gray: "border-neutral-200 bg-neutral-50 text-neutral-700 dark:border-neutral-700 dark:bg-neutral-900 dark:text-neutral-300 [&_.event-dot]:fill-neutral-600",
        "blue-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-blue-600",
        "green-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-green-600",
        "red-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-red-600",
        "orange-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-orange-600",
        "purple-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-purple-600",
        "yellow-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-yellow-600",
        "gray-dot":
          "bg-neutral-50 dark:bg-neutral-900 [&_.event-dot]:fill-neutral-600",
      },
    },
    defaultVariants: {
      color: "blue-dot",
    },
  }
)

function EventBlock({
  event,
  className,
  segmentId,
}: {
  event: IEvent
  segmentId: string
} & (HTMLAttributes<HTMLDivElement> &
  Omit<VariantProps<typeof calendarWeekEventCardVariants>, "color">)) {
  const {
    badgeVariant,
    onEventClick,
    onEventView,
    onEventUpdate,
    onEventDelete,
  } = useEventCalendar()

  const start = parseISO(event.startDate)
  const end = parseISO(event.endDate)
  const durationInMinutes = differenceInMinutes(end, start)
  const heightInPixels = (durationInMinutes / 60) * 96 - 8

  const color = (
    badgeVariant === "dot" ? `${event.color}-dot` : event.color
  ) as VariantProps<typeof calendarWeekEventCardVariants>["color"]

  const calendarWeekEventCardClasses = cn(
    calendarWeekEventCardVariants({ color, className }),
    durationInMinutes < 35 && "justify-center py-0"
  )

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault()
      if (e.currentTarget instanceof HTMLElement) e.currentTarget.click()
    }
  }

  const hasContextMenu = onEventView || onEventUpdate || onEventDelete

  const blockContent = (
    <DraggableEvent event={event} segmentId={segmentId}>
      <div
        role="button"
        tabIndex={0}
        className={calendarWeekEventCardClasses}
        style={{ height: `${heightInPixels}px` }}
        onKeyDown={handleKeyDown}
        onClick={() => onEventClick?.(event)}
      >
        <div className="flex items-center gap-1.5 truncate">
          {["mixed", "dot"].includes(badgeVariant) && (
            <svg
              width="8"
              height="8"
              viewBox="0 0 8 8"
              className="event-dot shrink-0"
            >
              <circle cx="4" cy="4" r="4" />
            </svg>
          )}

          <p className="truncate font-semibold">{event.title}</p>
        </div>

        {durationInMinutes > 25 && (
          <p>
            {format(start, "h:mm a")} - {format(end, "h:mm a")}
          </p>
        )}
      </div>
    </DraggableEvent>
  )

  if (!hasContextMenu) {
    return blockContent
  }

  return (
    <ContextMenu>
      <ContextMenuTrigger>{blockContent}</ContextMenuTrigger>
      <ContextMenuContent className="w-52">
        {onEventView && (
          <ContextMenuItem onClick={() => onEventView(event)}>
            View Details
          </ContextMenuItem>
        )}
        {onEventUpdate && (
          <ContextMenuItem onClick={() => onEventUpdate(event)}>
            Edit Details
          </ContextMenuItem>
        )}
        {(onEventView || onEventUpdate) && onEventDelete && (
          <ContextMenuSeparator />
        )}
        {onEventDelete && (
          <ContextMenuItem
            variant="destructive"
            onClick={() => onEventDelete(event)}
          >
            Delete Event
          </ContextMenuItem>
        )}
      </ContextMenuContent>
    </ContextMenu>
  )
}

function DayViewMultiDayEventsRow({
  selectedDate,
  multiDayEvents,
}: {
  selectedDate: Date
  multiDayEvents: IEvent[]
}) {
  const dayStart = startOfDay(selectedDate)
  const dayEnd = endOfDay(selectedDate)

  const multiDayEventsInDay = multiDayEvents
    .filter((event) => {
      const eventStart = parseISO(event.startDate)
      const eventEnd = parseISO(event.endDate)

      const isOverlapping =
        isWithinInterval(dayStart, { start: eventStart, end: eventEnd }) ||
        isWithinInterval(dayEnd, { start: eventStart, end: eventEnd }) ||
        (eventStart <= dayStart && eventEnd >= dayEnd)

      return isOverlapping
    })
    .sort((a, b) => {
      const durationA = differenceInDays(
        parseISO(a.endDate),
        parseISO(a.startDate)
      )
      const durationB = differenceInDays(
        parseISO(b.endDate),
        parseISO(b.startDate)
      )
      return durationB - durationA
    })

  if (multiDayEventsInDay.length === 0) return null

  return (
    <div className="flex border-b">
      <div className="w-18"></div>
      <ScrollArea className="h-20 flex-1">
        <div className="flex flex-col gap-1 border-l py-1">
          {multiDayEventsInDay.map((event) => {
            const eventStart = startOfDay(parseISO(event.startDate))
            const eventEnd = startOfDay(parseISO(event.endDate))
            const currentDate = startOfDay(selectedDate)

            const eventTotalDays = differenceInDays(eventEnd, eventStart) + 1
            const eventCurrentDay =
              differenceInDays(currentDate, eventStart) + 1

            return (
              <MonthEventBadge
                key={event.id}
                event={event}
                cellDate={selectedDate}
                eventCurrentDay={eventCurrentDay}
                eventTotalDays={eventTotalDays}
                segmentId={selectedDate.toISOString()}
              />
            )
          })}
        </div>
      </ScrollArea>
    </div>
  )
}

export function EventCalendarWeekView() {
  const {
    selectedDate,
    workingHours,
    visibleHours,
    singleDayEvents,
    multiDayEvents,
    view,
    onAddEvent,
  } = useEventCalendar()

  if (view !== "week") return null

  const { hours, earliestEventHour, latestEventHour } = getVisibleHours(
    visibleHours,
    singleDayEvents
  )

  const weekStart = startOfWeek(selectedDate)
  const weekDays = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i))

  return (
    <>
      <div className="flex flex-col items-center justify-center border-b py-4 text-sm text-muted-foreground sm:hidden">
        <p>Weekly view is not available on smaller devices.</p>
        <p>Please switch to daily or monthly view.</p>
      </div>

      <div className="hidden flex-col sm:flex">
        <div>
          <WeekViewMultiDayEventsRow
            selectedDate={selectedDate}
            multiDayEvents={multiDayEvents}
          />

          <div className="relative z-20 flex border-b">
            <div className="w-18"></div>
            <div className="grid flex-1 grid-cols-7 divide-x border-l">
              {weekDays.map((day, index) => (
                <span
                  key={index}
                  className="py-2 text-center text-xs font-medium text-muted-foreground"
                >
                  {format(day, "EE")}{" "}
                  <span className="ml-1 font-semibold text-foreground">
                    {format(day, "d")}
                  </span>
                </span>
              ))}
            </div>
          </div>
        </div>

        <ScrollArea className="h-[calc(100svh-295px)]">
          <div className="flex overflow-hidden">
            <div className="relative w-18">
              {hours.map((hour, index) => (
                <div key={hour} className="relative" style={{ height: "96px" }}>
                  <div className="absolute -top-3 right-2 flex h-6 items-center">
                    {index !== 0 && (
                      <span className="text-xs text-muted-foreground">
                        {format(new Date().setHours(hour, 0, 0, 0), "hh a")}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>

            <div className="relative flex-1 border-l">
              <div className="grid grid-cols-7 divide-x">
                {weekDays.map((day, dayIndex) => {
                  const dayEvents = singleDayEvents.filter(
                    (event) =>
                      isSameDay(parseISO(event.startDate), day) ||
                      isSameDay(parseISO(event.endDate), day)
                  )
                  const groupedEvents = groupEvents(dayEvents)

                  return (
                    <div key={dayIndex} className="relative">
                      {hours.map((hour, index) => {
                        const isDisabled = !isWorkingHour(
                          day,
                          hour,
                          workingHours
                        )

                        return (
                          <div
                            key={hour}
                            className={cn(
                              "relative",
                              isDisabled && "bg-muted/30"
                            )}
                            style={{ height: "96px" }}
                          >
                            {index !== 0 && (
                              <div className="pointer-events-none absolute inset-x-0 top-0 border-b"></div>
                            )}

                            <DroppableTimeBlock
                              date={day}
                              hour={hour}
                              minute={0}
                            >
                              <div
                                className="absolute inset-x-0 top-0 h-[24px] cursor-pointer transition-colors hover:bg-accent"
                                onClick={() =>
                                  onAddEvent?.({
                                    startDate: day,
                                    hour,
                                    minute: 0,
                                  })
                                }
                              />
                            </DroppableTimeBlock>

                            <DroppableTimeBlock
                              date={day}
                              hour={hour}
                              minute={15}
                            >
                              <div
                                className="absolute inset-x-0 top-[24px] h-[24px] cursor-pointer transition-colors hover:bg-accent"
                                onClick={() =>
                                  onAddEvent?.({
                                    startDate: day,
                                    hour,
                                    minute: 15,
                                  })
                                }
                              />
                            </DroppableTimeBlock>

                            <div className="pointer-events-none absolute inset-x-0 top-1/2 border-b border-dashed"></div>

                            <DroppableTimeBlock
                              date={day}
                              hour={hour}
                              minute={30}
                            >
                              <div
                                className="absolute inset-x-0 top-[48px] h-[24px] cursor-pointer transition-colors hover:bg-accent"
                                onClick={() =>
                                  onAddEvent?.({
                                    startDate: day,
                                    hour,
                                    minute: 30,
                                  })
                                }
                              />
                            </DroppableTimeBlock>

                            <DroppableTimeBlock
                              date={day}
                              hour={hour}
                              minute={45}
                            >
                              <div
                                className="absolute inset-x-0 top-[72px] h-[24px] cursor-pointer transition-colors hover:bg-accent"
                                onClick={() =>
                                  onAddEvent?.({
                                    startDate: day,
                                    hour,
                                    minute: 45,
                                  })
                                }
                              />
                            </DroppableTimeBlock>
                          </div>
                        )
                      })}

                      {groupedEvents.map((group, groupIndex) =>
                        group.map((event) => {
                          let style = getEventBlockStyle(
                            event,
                            day,
                            groupIndex,
                            groupedEvents.length,
                            { from: earliestEventHour, to: latestEventHour }
                          )
                          const hasOverlap = groupedEvents.some(
                            (otherGroup, otherIndex) =>
                              otherIndex !== groupIndex &&
                              otherGroup.some((otherEvent) =>
                                areIntervalsOverlapping(
                                  {
                                    start: parseISO(event.startDate),
                                    end: parseISO(event.endDate),
                                  },
                                  {
                                    start: parseISO(otherEvent.startDate),
                                    end: parseISO(otherEvent.endDate),
                                  }
                                )
                              )
                          )

                          if (!hasOverlap)
                            style = { ...style, width: "100%", left: "0%" }

                          return (
                            <div
                              key={event.id}
                              className="absolute p-1"
                              style={style}
                            >
                              <EventBlock
                                event={event}
                                segmentId={day.toISOString()}
                              />
                            </div>
                          )
                        })
                      )}
                    </div>
                  )
                })}
              </div>

              <CalendarTimeline
                firstVisibleHour={earliestEventHour}
                lastVisibleHour={latestEventHour}
              />
            </div>
          </div>
        </ScrollArea>
      </div>
    </>
  )
}

function WeekViewMultiDayEventsRow({
  selectedDate,
  multiDayEvents,
}: {
  selectedDate: Date
  multiDayEvents: IEvent[]
}) {
  const weekStart = useMemo(() => startOfWeek(selectedDate), [selectedDate])
  const weekEnd = useMemo(() => endOfWeek(selectedDate), [selectedDate])
  const weekDays = useMemo(
    () => Array.from({ length: 7 }, (_, i) => addDays(weekStart, i)),
    [weekStart]
  )

  const processedEvents = useMemo(() => {
    return multiDayEvents
      .map((event) => {
        const start = parseISO(event.startDate)
        const end = parseISO(event.endDate)
        const adjustedStart = isBefore(start, weekStart) ? weekStart : start
        const adjustedEnd = isAfter(end, weekEnd) ? weekEnd : end
        const startIndex = differenceInDays(adjustedStart, weekStart)
        const endIndex = differenceInDays(adjustedEnd, weekStart)

        return {
          ...event,
          adjustedStart,
          adjustedEnd,
          startIndex,
          endIndex,
        }
      })
      .sort((a, b) => {
        const startDiff = a.adjustedStart.getTime() - b.adjustedStart.getTime()
        if (startDiff !== 0) return startDiff
        return b.endIndex - b.startIndex - (a.endIndex - a.startIndex)
      })
  }, [multiDayEvents, weekStart, weekEnd])

  const eventRows = useMemo(() => {
    const rows: (typeof processedEvents)[] = []

    processedEvents.forEach((event) => {
      let rowIndex = rows.findIndex((row) =>
        row.every(
          (e) => e.endIndex < event.startIndex || e.startIndex > event.endIndex
        )
      )

      if (rowIndex === -1) {
        rowIndex = rows.length
        rows.push([])
      }

      rows[rowIndex].push(event)
    })

    return rows
  }, [processedEvents])

  const hasEventsInWeek = useMemo(() => {
    return multiDayEvents.some((event) => {
      const start = parseISO(event.startDate)
      const end = parseISO(event.endDate)

      return (
        (start >= weekStart && start <= weekEnd) ||
        (end >= weekStart && end <= weekEnd) ||
        (start <= weekStart && end >= weekEnd)
      )
    })
  }, [multiDayEvents, weekStart, weekEnd])

  if (!hasEventsInWeek) {
    return null
  }

  return (
    <div className="hidden overflow-hidden sm:flex">
      <div className="w-18 border-b"></div>
      <ScrollArea className="h-20 flex-1">
        <div className="grid grid-cols-7 divide-x border-b border-l">
          {weekDays.map((day, dayIndex) => (
            <div
              key={day.toISOString()}
              className="flex h-full flex-col gap-1 py-1"
            >
              {eventRows.map((row, rowIndex) => {
                const event = row.find(
                  (e) => e.startIndex <= dayIndex && e.endIndex >= dayIndex
                )

                if (!event) {
                  return (
                    <div key={`${rowIndex}-${dayIndex}`} className="h-6.5" />
                  )
                }

                let position: "first" | "middle" | "last" | "none" = "none"

                if (
                  dayIndex === event.startIndex &&
                  dayIndex === event.endIndex
                ) {
                  position = "none"
                } else if (dayIndex === event.startIndex) {
                  position = "first"
                } else if (dayIndex === event.endIndex) {
                  position = "last"
                } else {
                  position = "middle"
                }

                const segmentId = day.toISOString()

                return (
                  <MonthEventBadge
                    key={`${event.id}-${dayIndex}-${segmentId}`}
                    event={event}
                    cellDate={startOfDay(day)}
                    position={position}
                    segmentId={day.toISOString()}
                  />
                )
              })}
            </div>
          ))}
        </div>
      </ScrollArea>
    </div>
  )
}

export function EventCalendarDayView() {
  const {
    selectedDate,
    setSelectedDate,
    singleDayEvents,
    multiDayEvents,
    visibleHours,
    workingHours,
    view,
    onAddEvent,
  } = useEventCalendar()

  if (view !== "day") return null

  const { hours, earliestEventHour, latestEventHour } = getVisibleHours(
    visibleHours,
    singleDayEvents
  )

  const currentEvents = getCurrentEvents(singleDayEvents)

  const dayEvents = singleDayEvents.filter((event) => {
    const eventDate = parseISO(event.startDate)
    return (
      eventDate.getDate() === selectedDate.getDate() &&
      eventDate.getMonth() === selectedDate.getMonth() &&
      eventDate.getFullYear() === selectedDate.getFullYear()
    )
  })

  const groupedEvents = groupEvents(dayEvents)

  return (
    <div className="flex">
      <div className="flex flex-1 flex-col">
        <div>
          <DayViewMultiDayEventsRow
            selectedDate={selectedDate}
            multiDayEvents={multiDayEvents}
          />

          <div className="relative z-20 flex border-b">
            <div className="w-18"></div>
            <span className="flex-1 border-l py-2 text-center text-xs font-medium text-muted-foreground">
              {format(selectedDate, "EE")}{" "}
              <span className="font-semibold text-foreground">
                {format(selectedDate, "d")}
              </span>
            </span>
          </div>
        </div>

        <ScrollArea className="h-[calc(100svh-295px)]">
          <div className="flex">
            <div className="relative w-18">
              {hours.map((hour, index) => (
                <div key={hour} className="relative" style={{ height: "96px" }}>
                  <div className="absolute -top-3 right-2 flex h-6 items-center">
                    {index !== 0 && (
                      <span className="text-xs text-muted-foreground">
                        {format(new Date().setHours(hour, 0, 0, 0), "hh a")}
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>

            <div className="relative flex-1 border-l">
              <div className="relative">
                {hours.map((hour, index) => {
                  const isDisabled = !isWorkingHour(
                    selectedDate,
                    hour,
                    workingHours
                  )

                  return (
                    <div
                      key={hour}
                      className={cn("relative", isDisabled && "bg-muted/30")}
                      style={{ height: "96px" }}
                    >
                      {index !== 0 && (
                        <div className="pointer-events-none absolute inset-x-0 top-0 border-b"></div>
                      )}

                      <DroppableTimeBlock
                        date={selectedDate}
                        hour={hour}
                        minute={0}
                      >
                        <div
                          className="absolute inset-x-0 top-0 h-[24px] cursor-pointer transition-colors hover:bg-accent"
                          onClick={() =>
                            onAddEvent?.({
                              startDate: selectedDate,
                              hour,
                              minute: 0,
                            })
                          }
                        />
                      </DroppableTimeBlock>

                      <DroppableTimeBlock
                        date={selectedDate}
                        hour={hour}
                        minute={15}
                      >
                        <div
                          className="absolute inset-x-0 top-[24px] h-[24px] cursor-pointer transition-colors hover:bg-accent"
                          onClick={() =>
                            onAddEvent?.({
                              startDate: selectedDate,
                              hour,
                              minute: 15,
                            })
                          }
                        />
                      </DroppableTimeBlock>

                      <div className="pointer-events-none absolute inset-x-0 top-1/2 border-b border-dashed"></div>

                      <DroppableTimeBlock
                        date={selectedDate}
                        hour={hour}
                        minute={30}
                      >
                        <div
                          className="absolute inset-x-0 top-[48px] h-[24px] cursor-pointer transition-colors hover:bg-accent"
                          onClick={() =>
                            onAddEvent?.({
                              startDate: selectedDate,
                              hour,
                              minute: 30,
                            })
                          }
                        />
                      </DroppableTimeBlock>

                      <DroppableTimeBlock
                        date={selectedDate}
                        hour={hour}
                        minute={45}
                      >
                        <div
                          className="absolute inset-x-0 top-[72px] h-[24px] cursor-pointer transition-colors hover:bg-accent"
                          onClick={() =>
                            onAddEvent?.({
                              startDate: selectedDate,
                              hour,
                              minute: 45,
                            })
                          }
                        />
                      </DroppableTimeBlock>
                    </div>
                  )
                })}

                {groupedEvents.map((group, groupIndex) =>
                  group.map((event) => {
                    let style = getEventBlockStyle(
                      event,
                      selectedDate,
                      groupIndex,
                      groupedEvents.length,
                      { from: earliestEventHour, to: latestEventHour }
                    )
                    const hasOverlap = groupedEvents.some(
                      (otherGroup, otherIndex) =>
                        otherIndex !== groupIndex &&
                        otherGroup.some((otherEvent) =>
                          areIntervalsOverlapping(
                            {
                              start: parseISO(event.startDate),
                              end: parseISO(event.endDate),
                            },
                            {
                              start: parseISO(otherEvent.startDate),
                              end: parseISO(otherEvent.endDate),
                            }
                          )
                        )
                    )

                    if (!hasOverlap)
                      style = { ...style, width: "100%", left: "0%" }

                    return (
                      <div
                        key={event.id}
                        className="absolute p-1"
                        style={style}
                      >
                        <EventBlock
                          event={event}
                          segmentId={selectedDate.toISOString()}
                        />
                      </div>
                    )
                  })
                )}
              </div>

              <CalendarTimeline
                firstVisibleHour={earliestEventHour}
                lastVisibleHour={latestEventHour}
              />
            </div>
          </div>
        </ScrollArea>
      </div>

      <div className="hidden w-64 divide-y border-l md:block">
        <Calendar
          className="mx-auto w-fit"
          mode="single"
          selected={selectedDate}
          onSelect={setSelectedDate}
          autoFocus
        />

        <div className="flex-1 space-y-3">
          {currentEvents.length > 0 ? (
            <div className="flex items-start gap-2 px-4 pt-4">
              <span className="relative mt-[5px] flex size-2.5">
                <span className="absolute inline-flex size-full animate-ping rounded-full bg-green-400 opacity-75"></span>
                <span className="relative inline-flex size-2.5 rounded-full bg-green-600"></span>
              </span>

              <p className="text-sm font-semibold text-foreground">
                Happening now
              </p>
            </div>
          ) : (
            <p className="p-4 text-center text-sm text-muted-foreground italic">
              No appointments or consultations at the moment
            </p>
          )}

          {currentEvents.length > 0 && (
            <ScrollArea className="h-[422px] px-4">
              <div className="space-y-6 pb-4">
                {currentEvents.map((event) => {
                  return (
                    <div key={event.id} className="space-y-1.5">
                      <p className="line-clamp-2 text-sm font-semibold">
                        {event.title}
                      </p>

                      <div className="flex items-center gap-1.5 text-muted-foreground">
                        <CalendarIcon className="size-3.5" />
                        <span className="text-sm">
                          {format(new Date(), "MMM d, yyyy")}
                        </span>
                      </div>

                      <div className="flex items-center gap-1.5 text-muted-foreground">
                        <Clock className="size-3.5" />
                        <span className="text-sm">
                          {format(parseISO(event.startDate), "h:mm a")} -{" "}
                          {format(parseISO(event.endDate), "h:mm a")}
                        </span>
                      </div>
                    </div>
                  )
                })}
              </div>
            </ScrollArea>
          )}
        </div>
      </div>
    </div>
  )
}
