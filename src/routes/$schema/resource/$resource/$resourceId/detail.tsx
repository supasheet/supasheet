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

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { classifyRelationships } from "#/components/resource/detail/classify-relationships"
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
import type {
  TableMetadata,
  UpdatableViewMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { relatedTablesSchemaQueryOptions } from "#/lib/supabase/data/resource"

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
    const { schema, resource } = params
    const relatedTablesSchema = await context.queryClient.ensureQueryData(
      relatedTablesSchemaQueryOptions(schema, resource)
    )

    const primaryKeys = context.tableSchema.primary_keys ?? []
    if (primaryKeys?.length === 0) throw notFound()
    const pkName = primaryKeys[0].name

    const metaJoins = (
      JSON.parse(context.tableSchema.comment ?? "{}") as TableMetadata
    ).query?.join
    const classification = classifyRelationships(
      schema,
      resource,
      relatedTablesSchema,
      metaJoins
    )

    return {
      pkName,
      primaryKeys,
      ...classification,
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
  const {
    oneToOneRelationships,
    oneToManyRelationships,
    manyToManyRelationships,
  } = Route.useLoaderData()
  const { tableSchema } = Route.useRouteContext()
  const location = useLocation()
  const navigate = useNavigate()

  const tableMeta = JSON.parse(tableSchema.comment ?? "{}") as TableMetadata
  const actualResource =
    (tableMeta as UpdatableViewMetadata).based_on ?? resource
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
    ...oneToOneRelationships.map((r) => ({
      id: r.__embedKey,
      label: formatTitle(r.__embedKey),
      path: `${basePath}/${r.__embedKey}`,
    })),
    ...oneToManyRelationships.map((r) => ({
      id: r.name ?? "",
      label: formatTitle(r.name as string),
      path: `${basePath}/${r.name ?? ""}`,
    })),
    ...manyToManyRelationships.map((r) => ({
      id: r.name ?? "",
      label: formatTitle(r.name as string),
      path: `${basePath}/${r.name ?? ""}`,
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
          resource={actualResource}
          resourceId={resourceId}
        />
      </DefaultHeader>
      <div className="flex flex-1 flex-col">
        <div className="mx-auto w-full max-w-5xl px-4 py-4">
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
                <TabsList variant="line">
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
