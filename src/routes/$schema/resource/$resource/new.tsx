import {
  Link,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type {
  ErrorComponentProps,
  SearchSchemaInput,
} from "@tanstack/react-router"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceNewForm } from "#/components/resource/resource-new-form"
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
import { isTableSchema } from "#/lib/database-meta.types"
import type { TableMetadata } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/$schema/resource/$resource/new")({
  validateSearch: (
    search: {
      defaults?: string | Record<string, string>
    } & SearchSchemaInput
  ) => {
    const raw = search.defaults
    let defaults: Record<string, string> | undefined
    let source: Record<string, unknown> | undefined
    if (raw && typeof raw === "object" && !Array.isArray(raw)) {
      source = raw
    } else if (typeof raw === "string") {
      try {
        const parsed = JSON.parse(raw)
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
          source = parsed as Record<string, unknown>
        }
      } catch {}
    }
    if (source) {
      defaults = Object.fromEntries(
        Object.entries(source).filter(([, v]) => typeof v === "string")
      ) as Record<string, string>
    }
    return {
      defaults,
    }
  },
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasPermission = context.permissions?.some(
      (p) => p.permission === `${schema}.${resource}:insert`
    )
    const hasPrivilege = context.privileges?.includes("insert")
    const canInsert = context.authUser
      ? hasPermission && hasPrivilege
      : hasPrivilege
    if (!canInsert) throw notFound()
  },
  loader: async ({ context }) => {
    const { resourceSchema, columnsSchema } = context
    if (!isTableSchema(resourceSchema)) throw notFound()

    return { columnsSchema, tableSchema: resourceSchema }
  },
  head: ({ params }) => ({
    meta: [
      { title: pageTitle(`New Record | ${formatTitle(params.resource)}`) },
    ],
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
            { title: "New record" },
          ]}
        />
        <div className="flex flex-1 flex-col">
          <div className="mx-auto w-full max-w-5xl px-4 py-4">
            <div className="space-y-4">
              {Array.from({ length: 2 }).map((_outer, i) => (
                <Card key={i}>
                  <CardHeader>
                    <Skeleton className="h-5 w-24" />
                  </CardHeader>
                  <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
                    {Array.from({ length: 4 }).map((_inner, j) => (
                      <div
                        key={j}
                        className={
                          j === 3 ? "space-y-1.5 md:col-span-2" : "space-y-1.5"
                        }
                      >
                        <Skeleton className="h-4 w-28" />
                        <Skeleton className="h-9 w-full" />
                      </div>
                    ))}
                  </CardContent>
                </Card>
              ))}
            </div>
            <div className="flex justify-end gap-2 pt-4">
              <Skeleton className="h-9 w-20" />
              <Skeleton className="h-9 w-16" />
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
            { title: "New record" },
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
            { title: "New record" },
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
  const { defaults } = Route.useSearch()

  const { columnsSchema, tableSchema } = Route.useLoaderData()
  const resourceDisplayName =
    (JSON.parse(tableSchema.comment ?? "{}") as TableMetadata).name ??
    formatTitle(tableSchema.name)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: resourceDisplayName,
            url: `/${schema}/resource/${resource}`,
          },
          { title: "New record" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="mx-auto w-full max-w-7xl px-4 py-4">
          <ResourceNewForm
            columnsSchema={columnsSchema}
            tableSchema={tableSchema}
            defaults={defaults}
          />
        </div>
      </div>
    </>
  )
}
