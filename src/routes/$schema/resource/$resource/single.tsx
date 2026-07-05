import {
  Link,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceNewForm } from "#/components/resource/resource-new-form"
import { ResourceSingle } from "#/components/resource/resource-single"
import { ResourceUpdateForm } from "#/components/resource/resource-update-form"
import { Button } from "#/components/ui/button"
import { Card, CardContent, CardHeader } from "#/components/ui/card"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import type { ViewMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceDataQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/$schema/resource/$resource/single")({
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
  loader: async ({ context, params: { schema, resource } }) => {
    context.queryClient.ensureQueryData(
      resourceDataQueryOptions(schema, resource, undefined, 1, 1)
    )
    return { resourceSchema: context.resourceSchema }
  },
  head: ({ params, loaderData }) => {
    const meta = loaderData
      ? (JSON.parse(
          (loaderData.resourceSchema as { comment?: string }).comment ?? "{}"
        ) as ViewMetadata)
      : {}
    const name = meta.name ?? formatTitle(params.resource)
    return { meta: [{ title: pageTitle(`${name}`) }] }
  },
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
          ]}
        />
        <div className="flex flex-1 flex-col">
          <div className="mx-auto w-full max-w-7xl px-4 py-4">
            <div className="columns-1 gap-4 lg:columns-2">
              {Array.from({ length: 2 }).map((_outer, i) => (
                <div key={i} className="mb-4 break-inside-avoid">
                  <Card>
                    <CardHeader>
                      <Skeleton className="h-5 w-24" />
                    </CardHeader>
                    <CardContent className="space-y-4 py-4">
                      {Array.from({ length: 3 }).map((_inner, j) => (
                        <div key={j} className="space-y-1.5">
                          <Skeleton className="h-4 w-28" />
                          <Skeleton className="h-9 w-full" />
                        </div>
                      ))}
                    </CardContent>
                  </Card>
                </div>
              ))}
            </div>
            <div className="flex justify-end gap-2 pt-4">
              <Skeleton className="h-9 w-20" />
              <Skeleton className="h-9 w-28" />
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
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const resourceDisplayName =
    (JSON.parse(resourceSchema?.comment ?? "{}") as ViewMetadata).name ??
    formatTitle(resource)

  const tableSchema = isTableSchema(resourceSchema) ? resourceSchema : null

  const primaryKeys = tableSchema?.primary_keys ?? []

  const { data } = useSuspenseQuery(
    resourceDataQueryOptions(schema, resource, undefined, 1, 1)
  )
  const record = data?.result[0]

  return (
    <>
      <DefaultHeader breadcrumbs={[{ title: resourceDisplayName }]} />
      <div className="flex flex-1 flex-col">
        <div className="mx-auto w-full max-w-7xl px-4 py-4">
          {tableSchema ? (
            record ? (
              <ResourceUpdateForm
                columnsSchema={columnsSchema}
                primaryKeys={primaryKeys}
                record={record}
                tableSchema={tableSchema}
                saveOnly
              />
            ) : (
              <ResourceNewForm
                columnsSchema={columnsSchema}
                tableSchema={tableSchema}
                saveOnly
              />
            )
          ) : (
            <ResourceSingle
              resourceSchema={resourceSchema}
              columnsSchema={columnsSchema}
              record={record}
            />
          )}
        </div>
      </div>
    </>
  )
}
