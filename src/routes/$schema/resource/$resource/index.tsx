import { Suspense, useMemo } from "react"

import {
  Link,
  createFileRoute,
  notFound,
  redirect,
  useNavigate,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import type { ColumnFiltersState } from "@tanstack/react-table"

import {
  AlertCircleIcon,
  ArrowRightIcon,
  FileXIcon,
  FilterIcon,
  Grid3X3Icon,
  ImageIcon,
  LayoutGridIcon,
  ListIcon,
  ListTreeIcon,
  SquareKanbanIcon,
  TableIcon,
} from "lucide-react"

import { ChartSkeleton, ChartWidget } from "#/components/chart/chart-widget"
import { DashboardWidget } from "#/components/dashboard/dashboard-widget"
import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceActions } from "#/components/resource/resource-actions"
import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import { useHasPermission } from "#/hooks/use-permissions"
import { encodeFilterValue } from "#/lib/data-table"
import type {
  DatabaseSchemas,
  DatabaseTables,
  TableMetadata,
  ViewLayout,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { chartsQueryOptions } from "#/lib/supabase/data/chart"
import { dashboardWidgetsQueryOptions } from "#/lib/supabase/data/dashboard"
import type { FilterOperator } from "#/types/data-table"

type MetaItem = ViewLayout

const VIEW_TYPE_ICON: Record<MetaItem["type"], typeof TableIcon> = {
  kanban: SquareKanbanIcon,
  calendar: Grid3X3Icon,
  gallery: ImageIcon,
  list: ListIcon,
  tree: ListTreeIcon,
}

function resolvePrimaryViewTarget<S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S>,
  meta: TableMetadata
) {
  const primary = meta.primary_view
  const primaryView = primary
    ? (meta.views ?? []).find((v) => v.id === primary)
    : undefined

  if (primaryView?.type === "kanban") {
    return {
      to: "/$schema/resource/$resource/kanban/$kanbanId" as const,
      params: () => ({ schema, resource, kanbanId: primaryView.id }),
      search: { layout: "board" },
    }
  }
  if (primaryView?.type === "calendar") {
    return {
      to: "/$schema/resource/$resource/calendar/$calendarId" as const,
      params: () => ({ schema, resource, calendarId: primaryView.id }),
      search: { view: "month" },
    }
  }
  if (primaryView?.type === "gallery") {
    return {
      to: "/$schema/resource/$resource/gallery/$galleryId" as const,
      params: () => ({ schema, resource, galleryId: primaryView.id }),
    }
  }
  if (primaryView?.type === "list") {
    return {
      to: "/$schema/resource/$resource/list/$listId" as const,
      params: () => ({ schema, resource, listId: primaryView.id }),
    }
  }
  if (primaryView?.type === "tree") {
    return {
      to: "/$schema/resource/$resource/tree/$treeId" as const,
      params: () => ({ schema, resource, treeId: primaryView.id }),
    }
  }
  if (primary === "grid") {
    return {
      to: "/$schema/resource/$resource/grid" as const,
      params: { schema, resource },
    }
  }
  return {
    to: "/$schema/resource/$resource/table" as const,
    params: { schema, resource },
  }
}

function getPrimaryViewIcon(meta: TableMetadata) {
  const primary = meta.primary_view
  const primaryView = primary
    ? (meta.views ?? []).find((v) => v.id === primary)
    : undefined

  if (primaryView) return VIEW_TYPE_ICON[primaryView.type]
  if (primary === "grid") return LayoutGridIcon
  return TableIcon
}

export const Route = createFileRoute("/$schema/resource/$resource/")({
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasPermission = context.permissions?.some(
      (p) => p.permission === `${schema}.${resource}:select`
    )
    const hasPrivilege = context.privileges?.includes("select")
    const canSelect = context.authUser
      ? hasPermission && hasPrivilege
      : hasPrivilege
    if (!canSelect) throw notFound()

    const meta = JSON.parse(
      context.resourceSchema?.comment ?? "{}"
    ) as TableMetadata
    if (meta.singleton) {
      throw redirect({
        to: "/$schema/resource/$resource/single",
        params: { schema, resource },
      })
    }
  },
  loader: async ({ context, params: { schema, resource } }) => {
    const [widgets, charts] = await Promise.all([
      context.queryClient.ensureQueryData(
        dashboardWidgetsQueryOptions(schema, resource)
      ),
      context.queryClient.ensureQueryData(chartsQueryOptions(schema, resource)),
    ])

    const meta = JSON.parse(
      context.resourceSchema?.comment ?? "{}"
    ) as TableMetadata
    const hasFilterPresets = (meta.filter_presets?.length ?? 0) > 0
    if (!hasFilterPresets && widgets.length === 0 && charts.length === 0) {
      throw redirect(resolvePrimaryViewTarget(schema, resource, meta))
    }

    return { widgets, charts }
  },
  head: ({ params }) => ({
    meta: [
      {
        title: pageTitle(
          `${formatTitle(params.resource)} | ${formatTitle(params.schema)}`
        ),
      },
    ],
  }),
  pendingComponent: () => {
    const { resource } = Route.useParams()
    return (
      <>
        <DefaultHeader breadcrumbs={[{ title: formatTitle(resource) }]} />
        <div className="mx-auto w-full max-w-6xl space-y-4 p-4">
          <Skeleton className="h-24 w-full" />
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-24 w-full" />
            ))}
          </div>
          <Skeleton className="h-64 w-full" />
        </div>
      </>
    )
  },
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema, resource } = Route.useParams()
    const router = useRouter()
    return (
      <>
        <DefaultHeader breadcrumbs={[{ title: formatTitle(resource) }]} />
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
                onClick={() => router.navigate({ to: `/${schema}` })}
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
        <DefaultHeader breadcrumbs={[{ title: formatTitle(resource) }]} />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Resource not found</EmptyTitle>
              <EmptyDescription>
                <Link to="/$schema" params={{ schema }}>
                  Back to {formatTitle(schema)}
                </Link>
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </>
    )
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { schema, resource } = Route.useParams()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()
  const navigate = useNavigate()

  const meta = useMemo(
    () =>
      (resourceSchema?.comment
        ? JSON.parse(resourceSchema.comment)
        : {}) as TableMetadata,
    [resourceSchema?.comment]
  )
  const friendlyName =
    meta.name ?? formatTitle(resourceSchema?.name ?? resource)
  const isTable = isTableSchema(resourceSchema)
  const canInsert = useHasPermission(`${schema}.${resource}:insert`)

  const PrimaryViewIcon = useMemo(() => getPrimaryViewIcon(meta), [meta])
  function openPrimaryView() {
    navigate(resolvePrimaryViewTarget(schema, resource, meta))
  }

  function openTableWithFilters(filters: ColumnFiltersState) {
    navigate({
      to: "/$schema/resource/$resource/table",
      params: { schema, resource },
      search: { filters, page: 1 },
    })
  }

  const { widgets, charts } = Route.useLoaderData()
  const cardWidgets = widgets.filter((w) => w.widget_type.startsWith("card_"))
  const tableWidgets = widgets.filter((w) => w.widget_type.startsWith("table_"))

  const filterPresets = meta.filter_presets ?? []

  return (
    <>
      <DefaultHeader breadcrumbs={[{ title: friendlyName }]}>
        {isTable && canInsert && (
          <ResourceActions
            schema={schema}
            resource={resource}
            columnsSchema={columnsSchema ?? []}
            tableSchema={resourceSchema}
          />
        )}
      </DefaultHeader>
      <div className="mx-auto w-full max-w-6xl space-y-4 p-4">
        <section className="flex flex-col gap-3 rounded-lg border bg-card p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <DynamicIcon
                iconName={meta.icon}
                className="size-5 shrink-0 text-muted-foreground"
              />
              <h2 className="text-base font-medium">{friendlyName}</h2>
            </div>
            {meta.description && (
              <p className="text-sm text-muted-foreground">
                {meta.description}
              </p>
            )}
          </div>
          <Button size="sm" variant="outline" onClick={openPrimaryView}>
            <PrimaryViewIcon className="size-3.5" />
            Open view
          </Button>
        </section>

        {filterPresets.length > 0 && (
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-3">
            {filterPresets.map((preset) => (
              <Card
                key={preset.id}
                size="sm"
                className="h-full cursor-pointer transition-colors hover:bg-muted/50"
                onClick={() =>
                  openTableWithFilters(
                    preset.filters.map((f) => ({
                      id: f.id,
                      value: encodeFilterValue(
                        f.operator as FilterOperator,
                        f.value
                      ),
                    }))
                  )
                }
              >
                <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0">
                  <div className="flex min-w-0 items-center gap-2">
                    {preset.icon ? (
                      <DynamicIcon
                        iconName={preset.icon}
                        className="size-4 shrink-0 text-muted-foreground"
                      />
                    ) : (
                      <FilterIcon className="size-4 shrink-0 text-muted-foreground" />
                    )}
                    <CardTitle className="truncate">{preset.name}</CardTitle>
                  </div>
                  <ArrowRightIcon className="size-3.5 shrink-0 text-muted-foreground" />
                </CardHeader>
                {preset.description && (
                  <CardContent>
                    <CardDescription>{preset.description}</CardDescription>
                  </CardContent>
                )}
              </Card>
            ))}
          </div>
        )}

        {cardWidgets.length > 0 && (
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
            {cardWidgets.map((widget) => (
              <DashboardWidget key={widget.view_name} widget={widget} />
            ))}
          </div>
        )}

        {tableWidgets.length > 0 && (
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
            {tableWidgets
              .sort((a, b) => a.widget_type.localeCompare(b.widget_type))
              .map((widget) => (
                <DashboardWidget key={widget.view_name} widget={widget} />
              ))}
          </div>
        )}

        {charts.length > 0 && (
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
            {charts.map((chart) => (
              <Suspense key={chart.view_name} fallback={<ChartSkeleton />}>
                <ChartWidget chart={chart} />
              </Suspense>
            ))}
          </div>
        )}
      </div>
    </>
  )
}
