import { Link, createFileRoute } from "@tanstack/react-router"
import type { SearchSchemaInput } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import type { ColumnFiltersState, SortingState } from "@tanstack/react-table"

import { MailPlusIcon, PlusIcon } from "lucide-react"

import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { Button } from "#/components/ui/button"
import { UsersTable } from "#/components/users/users-table"
import { useHasPermission } from "#/hooks/use-permissions"
import { pageTitle } from "#/lib/page-title"
import { usersQueryOptions } from "#/lib/supabase/data/core"
import { columnsSchemaQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/core/users/")({
  head: () => ({ meta: [{ title: pageTitle("Users") }] }),
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
    sortDesc: search.sortDesc ?? false,
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
      usersQueryOptions(page, pageSize, sortId, sortDesc, filters)
    )
    const columnsSchema = await context.queryClient.ensureQueryData(
      columnsSchemaQueryOptions("supasheet", "users")
    )

    return { columnsSchema }
  },
  pendingComponent: PendingComponent,
  component: RouteComponent,
})

function HeaderActions() {
  const canInvite = useHasPermission("supasheet.users:invite")
  const canInsert = useHasPermission("supasheet.users:insert")
  return (
    <>
      {canInvite && (
        <Button
          variant="outline"
          size="sm"
          nativeButton={false}
          render={<Link to="/core/users/invite" />}
        >
          <MailPlusIcon className="mr-1.5 size-4" />
          Invite
        </Button>
      )}
      {canInsert && (
        <Button
          size="sm"
          nativeButton={false}
          render={<Link to="/core/users/new" />}
        >
          <PlusIcon className="size-4" />
          Add New
        </Button>
      )}
    </>
  )
}

function PendingComponent() {
  return (
    <>
      <DefaultHeader breadcrumbs={[{ title: "Users", url: "/core/users" }]}>
        <HeaderActions />
      </DefaultHeader>
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="flex flex-col gap-4 px-4 py-4">
            <DataTableSkeleton columnCount={6} />
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
    usersQueryOptions(page, pageSize, sortId, sortDesc, filters)
  )

  const sorting = (
    sortId ? [{ id: sortId, desc: sortDesc }] : []
  ) as SortingState
  const pagination = { pageIndex: page - 1, pageSize }
  const pageCount = Math.ceil((data?.count ?? 0) / pageSize)

  return (
    <>
      <DefaultHeader breadcrumbs={[{ title: "Users", url: "/core/users" }]}>
        <HeaderActions />
      </DefaultHeader>
      <div className="flex flex-1 flex-col">
        <div className="@container/main flex flex-1 flex-col gap-2">
          <div className="flex flex-col gap-4 px-4 py-4">
            <UsersTable
              data={data?.result ?? []}
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
