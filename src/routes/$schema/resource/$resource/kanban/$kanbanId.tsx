import {
  Link,
  Outlet,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type {
  ErrorComponentProps,
  SearchSchemaInput,
} from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import type { ColumnFiltersState } from "@tanstack/react-table"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceActions } from "#/components/resource/resource-actions"
import { ResourceKanban } from "#/components/resource/resource-kanban"
import type {
  KanbanBoardMode,
  KanbanViewData,
  KanbanViewReducedData,
} from "#/components/resource/resource-kanban"
import { ResourceViewSwitcher } from "#/components/resource/resource-view-switcher"
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
import type { KanbanLayout, TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { getEnumBadgeMetaMap, getEnumValues } from "#/lib/fields"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceDataQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute(
  "/$schema/resource/$resource/kanban/$kanbanId"
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
  validateSearch: (
    search: {
      layout?: string
      filters?: ColumnFiltersState
    } & SearchSchemaInput
  ) => {
    let filters: ColumnFiltersState = []
    try {
      const f = search.filters
      if (Array.isArray(f)) filters = f
    } catch {}
    return {
      layout: (["board", "list"].includes(search.layout as string)
        ? search.layout
        : "board") as KanbanBoardMode,
      filters,
    }
  },
  loaderDeps: ({ search: { layout, filters } }) => ({ layout, filters }),
  loader: async ({ context, params, deps: { filters } }) => {
    const { schema, resource, kanbanId } = params

    const meta = JSON.parse(
      context.resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const kanbanView = meta.views?.find(
      (item): item is KanbanLayout =>
        item.id === kanbanId && item.type === "kanban"
    )
    if (!kanbanView) throw notFound()

    context.queryClient.ensureQueryData(
      resourceDataQueryOptions(
        schema,
        resource,
        meta.query,
        undefined,
        undefined,
        undefined,
        undefined,
        filters
      )
    )

    return { kanbanView }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Kanban | ${formatTitle(params.resource)}`) }],
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
            { title: "Kanban" },
          ]}
        />
        <div className="flex flex-1 flex-col gap-2 px-4 py-4">
          {/* Layout toggle */}
          <div className="flex justify-end gap-1">
            <Skeleton className="h-8 w-8" />
            <Skeleton className="h-8 w-8" />
          </div>
          {/* Kanban columns */}
          <div className="flex gap-4 overflow-x-auto">
            {Array.from({ length: 4 }).map((_, col) => (
              <div key={col} className="flex min-w-xs flex-col gap-2">
                {/* Column header */}
                <div className="flex items-center gap-2">
                  <Skeleton className="h-4 w-24" />
                  <Skeleton className="h-5 w-6 rounded-sm" />
                </div>
                {/* Cards */}
                {Array.from({
                  length: col === 0 ? 4 : col === 1 ? 3 : col === 2 ? 5 : 2,
                }).map((__, row) => (
                  <div
                    key={row}
                    className="flex flex-col gap-2 rounded-lg bg-card p-3 shadow-xs ring-1 ring-foreground/10"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <Skeleton className="h-4 w-3/4" />
                      <Skeleton className="h-5 w-12 rounded-sm" />
                    </div>
                    <Skeleton className="h-3 w-1/2" />
                  </div>
                ))}
              </div>
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
            { title: "Kanban" },
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
            { title: "Kanban" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Kanban view not found</EmptyTitle>
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
  const { layout, filters } = Route.useSearch()
  const { kanbanView } = Route.useLoaderData()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const meta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  const { data: resourceData } = useSuspenseQuery(
    resourceDataQueryOptions(
      schema,
      resource,
      meta.query,
      undefined,
      undefined,
      undefined,
      undefined,
      filters
    )
  )

  const titleField = kanbanView.title
  const groupByField = kanbanView.group
  const descriptionField = kanbanView.description
  const badgeField = kanbanView.badge
  const dateField = kanbanView.date

  const badgeColumn = columnsSchema?.find((col) => col.name === badgeField)
  const badgeMeta = getEnumBadgeMetaMap(badgeColumn)

  const data: KanbanViewReducedData = {}
  for (const row of resourceData?.result ?? []) {
    const groupValue =
      groupByField && row[groupByField] != null
        ? String(row[groupByField])
        : "Uncategorized"

    if (!data[groupValue]) data[groupValue] = []

    const badge =
      badgeField && row[badgeField] != null ? String(row[badgeField]) : null

    const item: KanbanViewData = {
      title:
        titleField && row[titleField] != null ? String(row[titleField]) : null,
      description:
        descriptionField && row[descriptionField] != null
          ? String(row[descriptionField])
          : null,
      badge,
      badgeIcon: badge ? badgeMeta[badge]?.icon : undefined,
      badgeVariant: badge ? badgeMeta[badge]?.variant : undefined,
      date: dateField && row[dateField] != null ? String(row[dateField]) : null,
      data: row,
    }

    data[groupValue].push(item)
  }

  const groupByColumn = columnsSchema?.find((col) => col.name === groupByField)
  const groupValues = getEnumValues(groupByColumn)

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
          { title: formatTitle(kanbanView.id) },
        ]}
      >
        <ResourceViewSwitcher
          schema={schema}
          resource={resource}
          meta={meta}
          currentViewId={kanbanView.id}
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
      <div className="flex flex-1 flex-col px-4 py-4">
        <ResourceKanban
          data={data}
          resourceSchema={resourceSchema}
          groupBy={groupByField ?? ""}
          groupValues={groupValues}
          layout={layout}
          filterPresets={meta.filter_presets ?? []}
          currentFilters={filters}
        />
      </div>
      <Outlet />
    </>
  )
}
