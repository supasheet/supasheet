import { useDeferredValue, useMemo } from "react"

import { useSuspenseQuery } from "@tanstack/react-query"
import { Link, createFileRoute } from "@tanstack/react-router"

import { MailPlusIcon, PlusIcon } from "lucide-react"

import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { Button } from "#/components/ui/button"
import { UsersTable } from "#/components/users/users-table"
import { useHasRole } from "#/hooks/use-permissions"
import { getFilterVariants } from "#/lib/columns"
import { getTableQuery, validateTableSearch } from "#/lib/data-table-search"
import { pageTitle } from "#/lib/page-title"
import { usersQueryOptions } from "#/lib/supabase/data/core"
import { columnsSchemaQueryOptions } from "#/lib/supabase/data/meta"

export const Route = createFileRoute("/core/users/")({
  head: () => ({ meta: [{ title: pageTitle("Users") }] }),
  validateSearch: validateTableSearch,
  loaderDeps: ({ search }) => ({ search }),
  loader: async ({ context, deps: { search } }) => {
    const columnsSchema = await context.queryClient.query({
      ...columnsSchemaQueryOptions("supasheet", "users"),
      staleTime: "static",
    })
    context.queryClient.query({
      ...usersQueryOptions(
        getTableQuery(search, getFilterVariants(null, columnsSchema))
      ),
      staleTime: "static",
    })

    return { columnsSchema }
  },
  pendingComponent: PendingComponent,
  component: RouteComponent,
})

function HeaderActions() {
  const canInvite = useHasRole("x-admin")
  const canInsert = useHasRole("x-admin")
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
  const search = Route.useSearch()
  const { columnsSchema } = Route.useLoaderData()

  const liveTableQuery = useMemo(
    () => getTableQuery(search, getFilterVariants(null, columnsSchema)),
    [search, columnsSchema]
  )
  const tableQuery = useDeferredValue(liveTableQuery)
  const { data } = useSuspenseQuery(usersQueryOptions(tableQuery))

  const pageCount = Math.ceil((data?.count ?? 0) / tableQuery.perPage)

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
              pageCount={pageCount}
            />
          </div>
        </div>
      </div>
    </>
  )
}
