import { createFileRoute } from "@tanstack/react-router"
import type { SearchSchemaInput } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import type { ColumnFiltersState, SortingState } from "@tanstack/react-table"

import { AuditLogTable } from "#/components/audit-logs/audit-logs-table"
import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { pageTitle } from "#/lib/page-title"
import { auditLogsQueryOptions } from "#/lib/supabase/data/core"
import { columnsSchemaQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/core/audit_logs/")({
  head: () => ({ meta: [{ title: pageTitle("Audit Logs") }] }),
  validateSearch: (
    search: {
      sortId?: string
      sortDesc?: boolean
      page?: number
      pageSize?: number
      filters?: ColumnFiltersState
    } & SearchSchemaInput
  ) => ({
    sortId: search.sortId,
    sortDesc: search.sortDesc ?? true,
    page: search.page ?? 1,
    pageSize: search.pageSize ?? 20,
    filters: search.filters ?? [],
  }),
  loaderDeps: ({ search: { sortId, sortDesc, page, pageSize, filters } }) => ({
    sortId,
    sortDesc,
    page,
    pageSize,
    filters,
  }),
  loader: async ({
    context,
    deps: { sortId, sortDesc, page, pageSize, filters },
  }) => {
    context.queryClient.ensureQueryData(
      auditLogsQueryOptions(page, pageSize, sortId, sortDesc, filters)
    )
    const columnsSchema = await context.queryClient.ensureQueryData(
      columnsSchemaQueryOptions("supasheet", "audit_logs")
    )

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
          <div className="flex flex-col gap-4 px-4 py-4">
            <DataTableSkeleton columnCount={8} />
          </div>
        </div>
      </div>
    </>
  )
}

function RouteComponent() {
  const { sortId, sortDesc, page, pageSize, filters } = Route.useSearch()
  const { columnsSchema } = Route.useLoaderData()

  const { data } = useSuspenseQuery(
    auditLogsQueryOptions(page, pageSize, sortId, sortDesc, filters)
  )

  const sorting = (
    sortId ? [{ id: sortId, desc: sortDesc }] : []
  ) as SortingState
  const pagination = { pageIndex: page - 1, pageSize }
  const pageCount = Math.ceil((data?.count ?? 0) / pageSize)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[{ title: "Audit Log", url: "/core/audit-logs" }]}
      />
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="flex flex-col gap-4 px-4 py-4">
            <AuditLogTable
              data={data.result}
              columnsSchema={columnsSchema}
              sorting={sorting}
              pagination={pagination}
              columnFilters={filters}
              pageCount={pageCount}
            />
          </div>
        </div>
      </div>
    </>
  )
}
