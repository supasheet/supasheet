import { useDeferredValue, useMemo } from "react"

import { useSuspenseQuery } from "@tanstack/react-query"
import {
  Link,
  Outlet,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceList } from "#/components/resource/list/resource-list"
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
import {
  hasResourcePermission,
  useHasPermission,
} from "#/hooks/use-permissions"
import { getFilterVariants } from "#/lib/columns"
import { getTableQuery, validateTableSearch } from "#/lib/data-table-search"
import type { ListLayout, TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceDataQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute(
  "/$schema/resource/$resource/list/$listId"
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
  validateSearch: validateTableSearch,
  loaderDeps: ({ search }) => ({ search }),
  loader: async ({ context, params, deps: { search } }) => {
    const { schema, resource, listId } = params

    const meta = JSON.parse(
      context.resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const listView = meta.views?.find(
      (item): item is ListLayout => item.id === listId && item.type === "list"
    )
    if (!listView) throw notFound()

    context.queryClient.query({
      ...resourceDataQueryOptions(
        schema,
        resource,
        meta.query,
        getTableQuery(
          search,
          getFilterVariants(
            isTableSchema(context.resourceSchema)
              ? context.resourceSchema
              : null,
            context.columnsSchema
          )
        )
      ),
      staleTime: "static",
    })

    return { listView }
  },
  head: ({ params }) => ({
    meta: [
      {
        title: pageTitle(`List | ${formatTitle(params.resource)}`),
      },
    ],
  }),
  pendingComponent: () => {
    const { resource } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[{ title: formatTitle(resource) }, { title: "List" }]}
        />
        <div className="flex flex-1 flex-col">
          <div className="flex flex-col gap-4 px-4 py-4">
            <DataTableSkeleton columnCount={3} />
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
            { title: "List" },
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
                {(error as Error)?.message ?? "An unexpected error occurred."}
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
            { title: "List" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>List view not found</EmptyTitle>
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
  const search = Route.useSearch()
  const { listView } = Route.useLoaderData()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const meta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  const isTable = isTableSchema(resourceSchema)
  const canInsert = useHasPermission({ schema, resource, action: "insert" })

  const liveTableQuery = useMemo(
    () =>
      getTableQuery(
        search,
        getFilterVariants(isTable ? resourceSchema : null, columnsSchema)
      ),
    [search, isTable, resourceSchema, columnsSchema]
  )
  const tableQuery = useDeferredValue(liveTableQuery)

  const { data: resourceData } = useSuspenseQuery(
    resourceDataQueryOptions(schema, resource, meta.query, tableQuery)
  )

  const pageCount = Math.ceil((resourceData?.count ?? 0) / tableQuery.perPage)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: meta.name ?? formatTitle(resource),
            url: `/${schema}/resource/${resource}`,
          },
          { title: formatTitle(listView.id) },
        ]}
      >
        <ResourceViewSwitcher
          schema={schema}
          resource={resource}
          meta={meta}
          currentViewId={listView.id}
        />
        {isTable && canInsert && (
          <ResourceActions
            schema={schema}
            resource={resource}
            columnsSchema={columnsSchema}
          />
        )}
      </DefaultHeader>
      <div className="p-4">
        <ResourceList
          data={resourceData?.result ?? []}
          columnsSchema={columnsSchema ?? []}
          resourceSchema={resourceSchema}
          listView={listView}
          pageCount={pageCount}
          filterPresets={meta.filter_presets ?? []}
        />
      </div>
      <Outlet />
    </>
  )
}
