import { useDeferredValue, useMemo } from "react"

import { useSuspenseQuery } from "@tanstack/react-query"
import { createFileRoute } from "@tanstack/react-router"

import { AuditLogTable } from "#/components/audit-logs/audit-logs-table"
import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { getFilterVariants } from "#/lib/columns"
import { getTableQuery, validateTableSearch } from "#/lib/data-table-search"
import { pageTitle } from "#/lib/page-title"
import { auditLogsQueryOptions } from "#/lib/supabase/data/core"
import { columnsSchemaQueryOptions } from "#/lib/supabase/data/meta"

export const Route = createFileRoute("/core/audit_logs/")({
  head: () => ({ meta: [{ title: pageTitle("Audit Logs") }] }),
  validateSearch: validateTableSearch,
  loaderDeps: ({ search }) => ({ search }),
  loader: async ({ context, deps: { search } }) => {
    const columnsSchema = await context.queryClient.query({
      ...columnsSchemaQueryOptions("supasheet", "audit_logs"),
      staleTime: "static",
    })
    context.queryClient.query({
      ...auditLogsQueryOptions(
        getTableQuery(search, getFilterVariants(null, columnsSchema))
      ),
      staleTime: "static",
    })

    return { columnsSchema }
  },
  pendingComponent: PendingComponent,
  component: RouteComponent,
})

function PendingComponent() {
  return (
    <>
      <DefaultHeader
        breadcrumbs={[{ title: "Audit Log", url: "/core/audit-logs" }]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="flex flex-col gap-4 p-2">
            <DataTableSkeleton columnCount={8} />
          </div>
        </div>
      </div>
    </>
  )
}

function RouteComponent() {
  const search = Route.useSearch()
  const { columnsSchema } = Route.useLoaderData()

  const liveTableQuery = useMemo(
    () => getTableQuery(search, getFilterVariants(null, columnsSchema)),
    [search, columnsSchema]
  )
  const tableQuery = useDeferredValue(liveTableQuery)
  const { data } = useSuspenseQuery(auditLogsQueryOptions(tableQuery))

  const pageCount = Math.ceil((data?.count ?? 0) / tableQuery.perPage)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[{ title: "Audit Log", url: "/core/audit-logs" }]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="flex flex-col gap-4 p-2">
            <AuditLogTable
              data={data.result}
              columnsSchema={columnsSchema}
              pageCount={pageCount}
            />
          </div>
        </div>
      </div>
    </>
  )
}
