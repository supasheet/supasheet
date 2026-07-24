import { useMemo } from "react"

import {
  Link,
  createFileRoute,
  notFound,
  redirect,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceActions } from "#/components/resource/resource-actions"
import { ResourceOverview } from "#/components/resource/resource-overview"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import { useHasPermission } from "#/hooks/use-permissions"
import type { TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resolvePrimaryViewTarget } from "#/lib/resource-view"
import { chartsQueryOptions } from "#/lib/supabase/data/chart"
import { dashboardWidgetsQueryOptions } from "#/lib/supabase/data/dashboard"

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

  const { widgets, charts } = Route.useLoaderData()

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
      <ResourceOverview
        schema={schema}
        resource={resource}
        meta={meta}
        friendlyName={friendlyName}
        widgets={widgets}
        charts={charts}
      />
    </>
  )
}
