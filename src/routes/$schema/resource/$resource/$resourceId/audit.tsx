import { Suspense } from "react"

import { createFileRoute, notFound } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { HistoryIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceAuditTimeline } from "#/components/resource/audit/resource-audit-timeline"
import { Skeleton } from "#/components/ui/skeleton"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import {
  resourceAuditLogsQueryOptions,
} from "#/lib/supabase/data/resource"
import { isTableSchema } from "#/lib/database-meta.types"

export const Route = createFileRoute(
  "/$schema/resource/$resource/$resourceId/audit"
)({
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasAudit = context.permissions?.some(
      (p) => p.permission === `${schema}.${resource}:audit`
    )
    if (!hasAudit) throw notFound()
    const tableSchema = isTableSchema(context.resourceSchema) ? context.resourceSchema : null;
    if(!tableSchema) throw notFound()
    return { tableSchema }
  },
  loader: async ({ context, params: { schema, resource, resourceId } }) => {
    context.queryClient.ensureQueryData(
      resourceAuditLogsQueryOptions(schema, resource, resourceId)
    )
  },
  head: ({ params }) => ({
    meta: [
      {
        title: pageTitle(`Audit | ${formatTitle(params.resource)}`),
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
          { title: "Audit Log" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col p-4">
          <div className="mx-auto w-full max-w-2xl space-y-4">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="flex gap-3">
                <Skeleton className="mt-1 h-3.5 w-3.5 shrink-0 rounded-full" />
                <div className="flex-1 space-y-2 rounded-lg border p-3">
                  <Skeleton className="h-3 w-24" />
                  <Skeleton className="h-4 w-32" />
                  <Skeleton className="h-3 w-48" />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  )
}

function AuditTimelineBody() {
  const { schema, resource, resourceId } = Route.useParams()

  const { data: logs } = useSuspenseQuery(
    resourceAuditLogsQueryOptions(schema, resource, resourceId)
  )

  return <ResourceAuditTimeline logs={logs} />
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
          { title: "Audit Log" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col p-4">
          <div className="mx-auto w-full max-w-2xl">
            <div className="mb-4 flex items-center gap-2">
              <HistoryIcon className="h-4 w-4 text-muted-foreground" />
              <h2 className="text-sm font-medium text-muted-foreground">
                {`Change history for record ${resourceId.slice(0, 8)}…`}
              </h2>
            </div>
            <Suspense fallback={null}>
              <AuditTimelineBody />
            </Suspense>
          </div>
        </div>
      </div>
    </>
  )
}
