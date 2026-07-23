import {
  Link,
  Outlet,
  createFileRoute,
  notFound,
  useLocation,
  useNavigate,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { addEmbedKeys } from "#/components/resource/detail/add-embed-keys"
import { ResourceDetailHeader } from "#/components/resource/detail/resource-detail-header"
import { ResourceRecordActions } from "#/components/resource/resource-record-actions"
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
import { Tabs, TabsList, TabsTrigger } from "#/components/ui/tabs"
import type { TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import {
  relatedTablesSchemaQueryOptions,
  resourceActionsQueryOptions,
  singleResourceDataQueryOptions,
} from "#/lib/supabase/data/resource"

export const Route = createFileRoute(
  "/$schema/resource/$resource/$resourceId/detail"
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
    const tableSchema = isTableSchema(context.resourceSchema)
      ? context.resourceSchema
      : null
    if (!tableSchema) throw notFound()
    return { tableSchema, resourceSchema: undefined }
  },
  loader: async ({ context, params }) => {
    const { schema, resource, resourceId } = params
    const relatedTablesSchema = await context.queryClient.ensureQueryData(
      relatedTablesSchemaQueryOptions(schema, resource)
    )

    const primaryKeys = context.tableSchema.primary_keys ?? []
    if (primaryKeys?.length === 0) throw notFound()
    const pkName = primaryKeys[0].name

    context.queryClient.ensureQueryData(
      singleResourceDataQueryOptions(schema, resource, {
        [pkName]: resourceId,
      })
    )
    context.queryClient.ensureQueryData(
      resourceActionsQueryOptions(schema, resource)
    )

    const metaJoins = (
      JSON.parse(context.tableSchema.comment ?? "{}") as TableMetadata
    ).query?.join
    const embeddedTables = addEmbedKeys(
      schema,
      resource,
      relatedTablesSchema,
      metaJoins
    )

    return {
      pkName,
      primaryKeys,
      embeddedTables,
    }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Detail | ${formatTitle(params.resource)}`) }],
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
            { title: "Detail" },
          ]}
        />
        <div className="flex flex-1 flex-col">
          <div className="mx-auto w-full max-w-5xl px-4 py-4">
            <div className="space-y-4">
              <Card>
                <CardHeader>
                  <Skeleton className="h-5 w-32" />
                  <Skeleton className="mt-1.5 h-4 w-52" />
                </CardHeader>
                <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
                  {Array.from({ length: 6 }).map((_, i) => (
                    <div
                      key={i}
                      className={
                        i === 5
                          ? "flex min-w-0 flex-col gap-1.5 md:col-span-2"
                          : "flex min-w-0 flex-col gap-1.5"
                      }
                    >
                      <Skeleton className="h-4 w-28" />
                      <Skeleton className="h-4 w-48" />
                    </div>
                  ))}
                </CardContent>
              </Card>
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
            { title: "Detail" },
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
            { title: "Detail" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Record not found</EmptyTitle>
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
  const { schema, resource, resourceId } = Route.useParams()
  const { embeddedTables, pkName } = Route.useLoaderData()
  const { tableSchema, columnsSchema } = Route.useRouteContext()
  const location = useLocation()
  const navigate = useNavigate()

  const { data: record } = useSuspenseQuery(
    singleResourceDataQueryOptions(schema, resource, { [pkName]: resourceId })
  )

  const tableMeta = JSON.parse(tableSchema.comment ?? "{}") as TableMetadata
  const resourceDisplayName = tableMeta.name ?? formatTitle(resource)
  const allowedTabs = tableMeta.tabs

  const basePath = `/${schema}/resource/${resource}/${resourceId}/detail`
  const MAIN_TAB = "__main__"
  const currentTab = (() => {
    const rest = location.pathname.slice(basePath.length)
    if (!rest || rest === "/") return MAIN_TAB
    const seg = rest.replace(/^\/+/, "").split("/")[0]
    if (!seg || seg === "sheet") return MAIN_TAB
    return seg
  })()

  const allTabs: { id: string; label: string; path: string }[] = [
    { id: MAIN_TAB, label: "Detail", path: basePath },
    ...embeddedTables.map((r) => ({
      id: r.__embedKey,
      label: formatTitle(r.__embedKey),
      path: `${basePath}/${r.__embedKey}`,
    })),
  ]

  const tabs = allowedTabs
    ? allTabs.filter((t) => t.id === MAIN_TAB || allowedTabs.includes(t.id))
    : allTabs

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: resourceDisplayName,
            url: `/${schema}/resource/${resource}`,
          },
          { title: "Detail" },
        ]}
      >
        <ResourceRecordActions
          schema={schema}
          resource={resource}
          resourceId={resourceId}
        />
      </DefaultHeader>
      <div className="flex flex-1 flex-col">
        <div className="mx-auto w-full max-w-5xl px-4 py-4">
          {record && (
            <ResourceDetailHeader
              resourceSchema={tableSchema}
              columnsSchema={columnsSchema ?? []}
              record={record}
              fallbackId={resourceId}
            />
          )}
          {tabs.length > 1 ? (
            <Tabs
              value={currentTab}
              onValueChange={(value) => {
                const target = tabs.find((t) => t.id === value)
                if (target) navigate({ to: target.path })
              }}
              className="mb-4"
            >
              <div className="w-full overflow-x-auto">
                <TabsList>
                  {tabs.map((t) => (
                    <TabsTrigger key={t.id} value={t.id}>
                      {t.label}
                    </TabsTrigger>
                  ))}
                </TabsList>
              </div>
            </Tabs>
          ) : null}
          <Outlet />
        </div>
      </div>
    </>
  )
}
