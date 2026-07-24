import {
  Link,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceDefinition } from "#/components/resource/resource-definition"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import { hasResourcePermission } from "#/hooks/use-permissions"
import type { TableMetadata } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/$schema/resource/$resource/definition")({
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
  head: ({ params }) => ({
    meta: [
      {
        title: pageTitle(
          `About · ${formatTitle(params.resource)} | ${formatTitle(params.schema)}`
        ),
      },
    ],
  }),
  pendingComponent: () => {
    const { resource } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[{ title: formatTitle(resource) }, { title: "About" }]}
        />
        <div className="flex flex-col gap-4 p-4">
          <Skeleton className="h-32 w-full" />
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
        <DefaultHeader
          breadcrumbs={[{ title: formatTitle(resource) }, { title: "About" }]}
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
          breadcrumbs={[{ title: formatTitle(resource) }, { title: "About" }]}
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
  component: RouteComponent,
})

function RouteComponent() {
  const { schema, resource } = Route.useParams()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()
  const meta = (
    resourceSchema?.comment ? JSON.parse(resourceSchema.comment) : {}
  ) as TableMetadata
  const friendlyName = meta.name ?? formatTitle(resourceSchema.name ?? resource)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: friendlyName,
            url: `/${schema}/resource/${resource}`,
          },
          { title: "About" },
        ]}
      />
      <ResourceDefinition
        resource={resource}
        resourceSchema={resourceSchema}
        columnsSchema={columnsSchema}
      />
    </>
  )
}
