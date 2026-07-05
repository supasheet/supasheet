import { createFileRoute, getRouteApi, notFound } from "@tanstack/react-router"

import { useQuery, useSuspenseQuery } from "@tanstack/react-query"

import { classifyRelationships } from "#/components/resource/detail/classify-relationships"
import { ResourceDetailTab } from "#/components/resource/detail/resource-detail-tab"
import { useHasPermission } from "#/hooks/use-permissions"
import type { TableMetadata } from "#/lib/database-meta.types"
import {
  relatedTablesSchemaQueryOptions,
  resourcePrivilegesQueryOptions,
  singleForeignTableDataQueryOptions,
  singleResourceDataQueryOptions,
} from "#/lib/supabase/data/resource"

const parentRoute = getRouteApi(
  "/$schema/resource/$resource/$resourceId/detail"
)

export const Route = createFileRoute(
  "/$schema/resource/$resource/$resourceId/detail/$tab"
)({
  loader: async ({ context, params }) => {
    const { schema, resource, resourceId, tab } = params
    const relatedTablesSchema = await context.queryClient.ensureQueryData(
      relatedTablesSchemaQueryOptions(schema, resource)
    )
    const metaJoins = (
      JSON.parse(context.tableSchema?.comment ?? "{}") as TableMetadata
    ).query?.join
    const classification = classifyRelationships(
      schema,
      resource,
      relatedTablesSchema,
      metaJoins
    )

    const allowedTabs = (
      JSON.parse(context.tableSchema?.comment ?? "{}") as TableMetadata
    ).tabs
    if (allowedTabs && !allowedTabs.includes(tab)) throw notFound()

    const oneToOne = classification.oneToOneRelationships.find(
      (r) => r.__embedKey === tab
    )
    if (oneToOne) {
      const primaryKeys = context.tableSchema?.primary_keys ?? []
      const pkName = primaryKeys[0]?.name ?? "id"
      const pk = { [pkName]: resourceId }
      const parent = await context.queryClient.ensureQueryData(
        singleResourceDataQueryOptions(schema, resource, pk)
      )
      const matchValue = parent?.[oneToOne.__parentMatchColumn]
      if (matchValue != null) {
        await context.queryClient.ensureQueryData(
          singleForeignTableDataQueryOptions(oneToOne.schema, oneToOne.name, {
            [oneToOne.__foreignMatchColumn]: matchValue,
          })
        )
      }
      return
    }

    const many =
      classification.oneToManyRelationships.find((r) => r.name === tab) ??
      classification.manyToManyRelationships.find((r) => r.name === tab)
    if (!many) throw notFound()

    const primaryKeys = context.tableSchema?.primary_keys ?? []
    const pkName = primaryKeys[0]?.name ?? "id"
    const pk = { [pkName]: resourceId }
    await context.queryClient.ensureQueryData(
      singleResourceDataQueryOptions(schema, resource, pk)
    )
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { schema, resource, resourceId, tab } = Route.useParams()
  const {
    oneToOneRelationships,
    oneToManyRelationships,
    manyToManyRelationships,
    pkName,
  } = parentRoute.useLoaderData()

  const pk = { [pkName]: resourceId }

  const oneToOne = oneToOneRelationships.find((r) => r.__embedKey === tab)
  const many =
    oneToManyRelationships.find((r) => r.name === tab) ??
    manyToManyRelationships.find((r) => r.name === tab)

  const { data: record } = useSuspenseQuery(
    singleResourceDataQueryOptions(schema, resource, pk)
  )

  const { authUser, privileges } = Route.useRouteContext()

  const hasParentUpdatePermission = useHasPermission(
    `${schema}.${resource}:update`
  )
  const parentUpdatePrivilege = !!privileges?.includes("update")
  const canUpdateParent = authUser
    ? hasParentUpdatePermission && parentUpdatePrivilege
    : parentUpdatePrivilege

  const hasOneToOneUpdatePermission = useHasPermission(
    oneToOne ? `${oneToOne.schema}.${oneToOne.name}:update` : undefined
  )
  const { data: oneToOnePrivileges } = useQuery({
    ...resourcePrivilegesQueryOptions(
      oneToOne?.schema ?? schema,
      oneToOne?.name ?? resource
    ),
    enabled: !!oneToOne,
  })
  const oneToOneUpdatePrivilege = !!oneToOnePrivileges?.includes("update")
  const canUpdateOneToOne = authUser
    ? hasOneToOneUpdatePermission && oneToOneUpdatePrivilege
    : oneToOneUpdatePrivilege

  return (
    <ResourceDetailTab
      schema={schema}
      resource={resource}
      resourceId={resourceId}
      parentRecord={record}
      oneToOne={oneToOne}
      many={many}
      canUpdateOneToOne={canUpdateOneToOne}
      canUpdateParent={canUpdateParent}
    />
  )
}
