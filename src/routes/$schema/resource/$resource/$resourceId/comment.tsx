import { Suspense } from "react"

import { createFileRoute, notFound } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { MessageSquareIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceComments } from "#/components/resource/comments/resource-comments"
import { Skeleton } from "#/components/ui/skeleton"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceCommentsQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute(
  "/$schema/resource/$resource/$resourceId/comment"
)({
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasComment = context.permissions?.some(
      (p) => p.permission === `${schema}.${resource}:select`
    )
    if (!hasComment) throw notFound()
    const tableSchema = isTableSchema(context.resourceSchema)
      ? context.resourceSchema
      : null
    if (!tableSchema) throw notFound()
    return { tableSchema }
  },
  loader: async ({ context, params: { schema, resource, resourceId } }) => {
    context.queryClient.ensureQueryData(
      resourceCommentsQueryOptions(schema, resource, resourceId)
    )
  },
  head: ({ params }) => ({
    meta: [
      {
        title: pageTitle(`Comments | ${formatTitle(params.resource)}`),
      },
    ],
  }),
  pendingComponent: PendingComponent,
  component: RouteComponent,
})

function PendingComponent() {
  const { schema, resource, resourceId } = Route.useParams()

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: formatTitle(resource),
            url: `/${schema}/resource/${resource}/table`,
          },
          {
            title: resourceId.slice(0, 8) + "…",
            url: `/${schema}/resource/${resource}/${resourceId}/detail`,
          },
          { title: "Comments" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col p-4">
          <div className="mx-auto w-full max-w-2xl space-y-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="flex gap-3">
                <Skeleton className="mt-0.5 h-7 w-7 shrink-0 rounded-full" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-3 w-32" />
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-4 w-3/4" />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  )
}

function CommentsBody() {
  const { schema, resource, resourceId } = Route.useParams()

  const { data: comments } = useSuspenseQuery(
    resourceCommentsQueryOptions(schema, resource, resourceId)
  )

  return (
    <ResourceComments
      schema={schema}
      resource={resource}
      recordId={resourceId}
      comments={comments}
    />
  )
}

function RouteComponent() {
  const { schema, resource, resourceId } = Route.useParams()
  const { tableSchema } = Route.useRouteContext()
  const resourceTitle = tableSchema?.comment
    ? (() => {
        try {
          const meta = JSON.parse(tableSchema.comment)
          return meta.label ?? formatTitle(resource)
        } catch {
          return formatTitle(resource)
        }
      })()
    : formatTitle(resource)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: resourceTitle,
            url: `/${schema}/resource/${resource}/table`,
          },
          {
            title: resourceId.slice(0, 8) + "…",
            url: `/${schema}/resource/${resource}/${resourceId}/detail`,
          },
          { title: "Comments" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col p-4">
          <div className="mx-auto w-full max-w-2xl">
            <div className="mb-4 flex items-center gap-2">
              <MessageSquareIcon className="h-4 w-4 text-muted-foreground" />
              <h2 className="text-sm font-medium text-muted-foreground">
                {`Comments on record ${resourceId.slice(0, 8)}…`}
              </h2>
            </div>
            <Suspense fallback={null}>
              <CommentsBody />
            </Suspense>
          </div>
        </div>
      </div>
    </>
  )
}
