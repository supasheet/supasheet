import { createFileRoute, getRouteApi, notFound } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { ResourceFullDetail } from "#/components/resource/detail/resource-full-detail"
import { ResourceUpdateForm } from "#/components/resource/resource-update-form"
import { useHasPermission } from "#/hooks/use-permissions"
import {
  columnsSchemaQueryOptions,
  singleResourceDataQueryOptions,
} from "#/lib/supabase/data/resource"

const parentRoute = getRouteApi(
  "/$schema/resource/$resource/$resourceId/detail"
)

export const Route = createFileRoute(
  "/$schema/resource/$resource/$resourceId/detail/"
)({
  loader: async ({ context, params }) => {
    const { schema, resource, resourceId } = params

    const primaryKeys = context.tableSchema?.primary_keys ?? []
    const pkName = primaryKeys[0]?.name ?? "id"
    const pk = { [pkName]: resourceId }
    const record = await context.queryClient.ensureQueryData(
      singleResourceDataQueryOptions(schema, resource, pk)
    )
    if (!record) throw notFound()

    const updateColumnsSchema = await context.queryClient.ensureQueryData(
      columnsSchemaQueryOptions(schema, resource, "update")
    )

    return { updateColumnsSchema }
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { schema, resource, resourceId } = Route.useParams()
  const { pkName, primaryKeys } = parentRoute.useLoaderData()
  const { updateColumnsSchema } = Route.useLoaderData()
  const { tableSchema, columnsSchema } = Route.useRouteContext()

  const pk = { [pkName]: resourceId }
  const { data: record } = useSuspenseQuery(
    singleResourceDataQueryOptions(schema, resource, pk)
  )

  const { authUser, privileges } = Route.useRouteContext()
  const hasUpdatePermission = useHasPermission(`${schema}.${resource}:update`)
  const hasUpdatePrivilege = !!privileges?.includes("update")
  const canUpdate = authUser
    ? hasUpdatePermission && hasUpdatePrivilege
    : hasUpdatePrivilege

  if (!record) return null

  const canEdit = !!tableSchema && primaryKeys.length > 0 && canUpdate

  if (canEdit) {
    return (
      <ResourceUpdateForm
        columnsSchema={updateColumnsSchema}
        primaryKeys={primaryKeys}
        record={record}
        tableSchema={tableSchema}
        saveOnly
      />
    )
  }

  return (
    <ResourceFullDetail
      resourceSchema={tableSchema}
      columnsSchema={columnsSchema}
      record={record}
    />
  )
}
