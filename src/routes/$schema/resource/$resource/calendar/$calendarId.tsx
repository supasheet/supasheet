import {
  Link,
  Outlet,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceActions } from "#/components/resource/resource-actions"
import {
  ResourceCalendar,
  colorFromString,
} from "#/components/resource/resource-calendar"
import { ResourceViewSwitcher } from "#/components/resource/resource-view-switcher"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import type { IEvent, TCalendarView } from "#/components/ui/event-calendar"
import { Skeleton } from "#/components/ui/skeleton"
import { useHasPermission } from "#/hooks/use-permissions"
import type { CalendarLayout, TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceDataQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute(
  "/$schema/resource/$resource/calendar/$calendarId"
)({
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasPermission = context.permissions?.some(
      (p) => p.permission === `${schema}.${resource}:select`
    )
    const hasPrivilege = context.privileges?.includes("select")
    const canSelect = context.authUser
      ? hasPermission && hasPrivilege
      : hasPrivilege
    if (!canSelect) throw notFound()
  },
  validateSearch: (search: { view?: string }) => ({
    view: (["month", "week", "day", "year", "agenda"].includes(
      search.view as string
    )
      ? search.view
      : "month") as TCalendarView,
  }),
  loaderDeps: ({ search: { view } }) => ({ view }),
  loader: async ({ context, params }) => {
    const { schema, resource, calendarId } = params

    const meta = JSON.parse(
      context.resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const calendarView = meta.views?.find(
      (item): item is CalendarLayout =>
        item.id === calendarId && item.type === "calendar"
    )
    if (!calendarView) throw notFound()

    context.queryClient.ensureQueryData(
      resourceDataQueryOptions(schema, resource, meta.query)
    )

    return { calendarView }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Calendar | ${formatTitle(params.resource)}`) }],
  }),
  pendingComponent: () => {
    const { schema, resource } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            {
              title: formatTitle(resource),
              url: `/${schema}/resource/${resource}`,
            },
            { title: "Calendar" },
          ]}
        />
        <div className="flex flex-1 flex-col gap-2 px-4 py-4">
          {/* Calendar header: prev/next + title + view switcher */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Skeleton className="h-8 w-8" />
              <Skeleton className="h-8 w-8" />
              <Skeleton className="h-6 w-32" />
            </div>
            <div className="flex items-center gap-1">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-8" />
              ))}
            </div>
          </div>
          {/* Day-of-week header row */}
          <div className="grid grid-cols-7 gap-1">
            {Array.from({ length: 7 }).map((_, i) => (
              <Skeleton key={i} className="h-6" />
            ))}
          </div>
          {/* Calendar grid: 6 weeks × 7 days */}
          <div className="grid flex-1 grid-cols-7 grid-rows-6 gap-1">
            {Array.from({ length: 42 }).map((_, i) => (
              <Skeleton key={i} className="min-h-[80px] rounded-md" />
            ))}
          </div>
        </div>
      </>
    )
  },
  component: RouteComponent,
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema, resource } = Route.useParams()
    const router = useRouter()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            {
              title: formatTitle(resource),
              url: `/${schema}/resource/${resource}`,
            },
            { title: "Calendar" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <AlertCircleIcon />
              </EmptyMedia>
              <EmptyTitle>Something went wrong</EmptyTitle>
              <EmptyDescription>
                {error?.message ?? "An unexpected error occurred."}
              </EmptyDescription>
            </EmptyHeader>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() =>
                  router.navigate({ to: `/${schema}/resource/${resource}` })
                }
              >
                Go Back
              </Button>
            </div>
          </Empty>
        </div>
      </>
    )
  },
  notFoundComponent: () => {
    const { schema, resource } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            {
              title: formatTitle(resource),
              url: `/${schema}/resource/${resource}`,
            },
            { title: "Calendar" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Calendar view not found</EmptyTitle>
              <EmptyDescription>
                <Link
                  to="/$schema/resource/$resource"
                  params={{ schema, resource }}
                >
                  Back to {formatTitle(resource)}
                </Link>
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </>
    )
  },
})

function RouteComponent() {
  const { schema, resource } = Route.useParams()
  const { view } = Route.useSearch()
  const { calendarView } = Route.useLoaderData()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const meta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  const { data: resourceData } = useSuspenseQuery(
    resourceDataQueryOptions(schema, resource, meta.query)
  )

  const titleField = calendarView.title
  const startDateField = calendarView.start_date
  const endDateField = calendarView.end_date
  const badgeField = calendarView.badge

  const data: IEvent[] = startDateField
    ? (resourceData?.result ?? [])
        .filter((row) => row[startDateField])
        .map((row, i) => ({
          id: String(i),
          title: titleField ? String(row[titleField] ?? "") : "",
          color: colorFromString(
            badgeField ? String(row[badgeField] ?? "") : null
          ),
          startDate: String(row[startDateField]),
          endDate:
            endDateField && row[endDateField]
              ? String(row[endDateField])
              : String(row[startDateField]),
          data: row,
        }))
    : []

  const metaItems = meta.views ?? []
  const isTable = isTableSchema(resourceSchema)
  const canInsert = useHasPermission(`${schema}.${resource}:insert`)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: meta.name ?? formatTitle(resource),
            url: `/${schema}/resource/${resource}`,
          },
          { title: formatTitle(calendarView.id) },
        ]}
      >
        <ResourceViewSwitcher
          schema={schema}
          resource={resource}
          metaItems={metaItems}
          currentViewId={calendarView.id}
        />
        {isTable && canInsert && (
          <ResourceActions
            schema={schema}
            resource={resource}
            columnsSchema={columnsSchema ?? []}
            tableSchema={resourceSchema}
          />
        )}
      </DefaultHeader>
      <div className="flex flex-1 flex-col px-4 py-4" style={{ minHeight: 0 }}>
        <ResourceCalendar
          view={view}
          data={data}
          resourceSchema={resourceSchema}
          currentView={calendarView}
          columnsSchema={columnsSchema ?? []}
        />
      </div>
      <Outlet />
    </>
  )
}
