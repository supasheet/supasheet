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

import type { ColumnFiltersState, SortingState } from "@tanstack/react-table"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceGrid } from "#/components/resource/grid/resource-grid"
import { ResourceActions } from "#/components/resource/resource-actions"
import { ResourceViewSwitcher } from "#/components/resource/resource-view-switcher"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { useHasPermission } from "#/hooks/use-permissions"
import type { TableMetadata } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import {
  resourceDataQueryOptions,
} from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/$schema/resource/$resource/grid")({
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
  validateSearch: (
    search: {
      sortId?: string
      sortDesc?: boolean
      page?: number
      pageSize?: number
      filters?: ColumnFiltersState
    } & SearchSchemaInput
  ) => {
    let filters: ColumnFiltersState = []
    try {
      const f = search.filters
      if (Array.isArray(f)) filters = f
    } catch {}
    return {
      sortId: search.sortId,
      sortDesc: search.sortDesc ?? false,
      page: search.page ?? 1,
      pageSize: search.pageSize ?? 20,
      filters,
    }
  },
  loaderDeps: ({ search: { sortId, sortDesc, page, pageSize, filters } }) => ({
    sortId,
    sortDesc,
    page,
    pageSize,
    filters,
  }),
  loader: async ({
    context,
    params,
    deps: { sortId, sortDesc, page, pageSize, filters },
  }) => {
    const { schema, resource } = params

    const metaData = JSON.parse(context.resourceSchema.comment ?? "{}") as TableMetadata
    context.queryClient.ensureQueryData(
      resourceDataQueryOptions(
        schema,
        resource,
        metaData.query,
        page,
        pageSize,
        sortId,
        sortDesc,
        filters
      )
    )
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
        <div className="flex flex-1 flex-col">
          <div className="flex flex-col gap-4 px-4 py-4">
            <DataTableSkeleton columnCount={5} />
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
                onClick={() => {
                  router.navigate({ to: `/${schema}/resource/${resource}` })
                }}
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
            { title: "Grid" },
          ]}
        />
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
})

function RouteComponent() {
  const { schema, resource } = Route.useParams()
  const { sortId, sortDesc, page, pageSize, filters } = Route.useSearch()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const meta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  const metaItems = meta.views ?? []
  const canInsert = useHasPermission(`${schema}.${resource}:insert`)

  const { data: resourceData } = useSuspenseQuery(
    resourceDataQueryOptions(
      schema,
      resource,
      meta.query,
      page,
      pageSize,
      sortId,
      sortDesc,
      filters
    )
  )

  const sorting = (
    sortId ? [{ id: sortId, desc: sortDesc }] : []
  ) as SortingState
  const pagination = { pageIndex: page - 1, pageSize }
  const pageCount = Math.ceil((resourceData?.count ?? 0) / pageSize)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: meta.name ?? formatTitle(resource),
            url: `/${schema}/resource/${resource}`,
          },
          { title: "Grid" },
        ]}
      >
        <ResourceViewSwitcher
          schema={schema}
          resource={resource}
          metaItems={metaItems}
          currentViewId="grid"
        />
        {canInsert && (
          <ResourceActions
            schema={schema}
            resource={resource}
            columnsSchema={columnsSchema}
            tableSchema={resourceSchema}
          />
        )}
      </DefaultHeader>
      <div className="p-4">
        <ResourceGrid
          data={resourceData?.result ?? []}
          columnsSchema={columnsSchema ?? []}
          resourceSchema={resourceSchema}
          sorting={sorting}
          pagination={pagination}
          columnFilters={filters}
          pageCount={pageCount}
          filterPresets={meta.filter_presets ?? []}
        />
      </div>
      <Outlet />
    </>
  )
}
