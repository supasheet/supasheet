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
  ResourceGantt,
  buildGanttData,
} from "#/components/resource/resource-gantt"
import { ResourceViewSwitcher } from "#/components/resource/resource-view-switcher"
import type { GanttScale } from "#/components/reui/gantt/gantt-types"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import {
  hasResourcePermission,
  useHasPermission,
} from "#/hooks/use-permissions"
import type { GanttLayout, TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceDataQueryOptions } from "#/lib/supabase/data/resource"

const GANTT_SCALES: GanttScale[] = ["day", "week", "month", "quarter", "year"]

export const Route = createFileRoute(
  "/$schema/resource/$resource/gantt/$ganttId"
)({
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasPermission = hasResourcePermission(context.permissions, {
      schema,
      resource,
      action: "select",
    })
    const hasPrivilege = context.privileges?.includes("select")
    const canSelect = context.authUser
      ? hasPermission && hasPrivilege
      : hasPrivilege
    if (!canSelect) throw notFound()
  },
  validateSearch: (search: { scale?: string }) => ({
    scale: (GANTT_SCALES.includes(search.scale as GanttScale)
      ? search.scale
      : "month") as GanttScale,
  }),
  loaderDeps: ({ search: { scale } }) => ({ scale }),
  loader: async ({ context, params }) => {
    const { schema, resource, ganttId } = params

    const meta = JSON.parse(
      context.resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const ganttView = meta.views?.find(
      (item): item is GanttLayout =>
        item.id === ganttId && item.type === "gantt"
    )
    if (!ganttView) throw notFound()

    context.queryClient.ensureQueryData(
      resourceDataQueryOptions(schema, resource, meta.query)
    )

    return { ganttView }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Gantt | ${formatTitle(params.resource)}`) }],
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
            { title: "Gantt" },
          ]}
        />
        <div className="flex flex-1 flex-col gap-2 px-4 py-4">
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
          <div className="flex flex-1 gap-2">
            <Skeleton className="h-full w-64 shrink-0" />
            <div className="flex flex-1 flex-col gap-1">
              {Array.from({ length: 8 }).map((_, i) => (
                <Skeleton key={i} className="h-8" />
              ))}
            </div>
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
            { title: "Gantt" },
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
            { title: "Gantt" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Gantt view not found</EmptyTitle>
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
  const { scale } = Route.useSearch()
  const { ganttView } = Route.useLoaderData()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const meta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  const { data: resourceData } = useSuspenseQuery(
    resourceDataQueryOptions(schema, resource, meta.query)
  )

  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const { resources, events, rowIds } = buildGanttData(
    resourceData?.result ?? [],
    primaryKeys,
    ganttView
  )

  const isTable = isTableSchema(resourceSchema)
  const canInsert = useHasPermission({ schema, resource, action: "insert" })

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: meta.name ?? formatTitle(resource),
            url: `/${schema}/resource/${resource}`,
          },
          { title: formatTitle(ganttView.id) },
        ]}
      >
        <ResourceViewSwitcher
          schema={schema}
          resource={resource}
          meta={meta}
          currentViewId={ganttView.id}
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
        <ResourceGantt
          scale={scale}
          resources={resources}
          events={events}
          rowIds={rowIds}
          resourceSchema={resourceSchema}
          currentView={ganttView}
          columnsSchema={columnsSchema ?? []}
        />
      </div>
      <Outlet />
    </>
  )
}
