import { createFileRoute, notFound } from "@tanstack/react-router"

import { AuditLogDetail } from "#/components/audit-logs/audit-log-detail"
import { DefaultHeader } from "#/components/layouts/default-header"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
} from "#/components/ui/card"
import { Separator } from "#/components/ui/separator"
import { Skeleton } from "#/components/ui/skeleton"
import type { Tables } from "#/lib/database.types"
import { pageTitle } from "#/lib/page-title"
import { auditLogQueryOptions } from "#/lib/supabase/data/core"

type AuditLogRow = Tables<{ schema: "supasheet" }, "audit_logs">

export const Route = createFileRoute("/core/audit_logs/$auditLogId")({
  loader: async ({
    context,
    params: { auditLogId },
  }): Promise<{ data: AuditLogRow }> => {
    if (!auditLogId) throw notFound()
    const auditLog = await context.queryClient.query({
      ...auditLogQueryOptions(auditLogId),
      staleTime: "static",
    })
    if (!auditLog) throw notFound()
    return { data: auditLog }
  },
  head: ({ params }) => ({
    meta: [
      { title: pageTitle(`${params.auditLogId.slice(0, 8)} | Audit Logs`) },
    ],
  }),
  pendingComponent: () => {
    const { auditLogId } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            { title: "Audit Logs", url: "/core/audit_logs" },
            { title: auditLogId.slice(0, 8) + "…" },
          ]}
        />
        <div className="flex flex-1 flex-col">
          <div className="@container/main flex flex-1 flex-col items-center p-4">
            <div className="mx-auto flex w-full max-w-2xl flex-col gap-4">
              <Card>
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <Skeleton className="h-7 w-44" />
                    <Skeleton className="h-6 w-20 rounded-full" />
                  </div>
                  <CardDescription>
                    <Skeleton className="h-4 w-52" />
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-4">
                  <div className="grid grid-cols-2 gap-4">
                    {Array.from({ length: 9 }).map((_, i) => (
                      <div key={i} className="space-y-1">
                        <Skeleton className="h-3 w-14" />
                        <Skeleton className="h-4 w-full max-w-[12rem]" />
                      </div>
                    ))}
                  </div>
                  <Separator />
                  <div className="flex flex-col gap-2">
                    <Skeleton className="h-4 w-28" />
                    <Skeleton className="h-16 w-full rounded-lg" />
                  </div>
                  <Separator />
                  <div className="flex flex-col gap-2">
                    <Skeleton className="h-4 w-24" />
                    <Skeleton className="h-24 w-full rounded-md border" />
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <Skeleton className="h-6 w-36" />
                  <CardDescription>
                    <Skeleton className="h-4 w-48" />
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex flex-col gap-4">
                    <div className="flex flex-col gap-2">
                      <Skeleton className="h-4 w-16" />
                      <Skeleton className="h-40 w-full rounded-md border" />
                    </div>
                    <div className="flex flex-col gap-2">
                      <Skeleton className="h-4 w-16" />
                      <Skeleton className="h-40 w-full rounded-md border" />
                    </div>
                  </div>
                </CardContent>
              </Card>
            </div>
          </div>
        </div>
      </>
    )
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { auditLogId } = Route.useParams()
  const { data } = Route.useLoaderData()

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Audit Logs", url: "/core/audit_logs" },
          { title: auditLogId.slice(0, 8) + "…" },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col items-center p-4">
          <AuditLogDetail data={data} />
        </div>
      </div>
    </>
  )
}
