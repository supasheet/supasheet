import { createFileRoute, getRouteApi, notFound } from "@tanstack/react-router"

import { useQuery, useSuspenseQuery } from "@tanstack/react-query"

import { addEmbedKeys } from "#/components/resource/detail/add-embed-keys"
import { classifyRelationships } from "#/components/resource/detail/classify-relationships"
import { ResourceDetailTab } from "#/components/resource/detail/resource-detail-tab"
import { useHasPermission } from "#/hooks/use-permissions"
import type { TableMetadata } from "#/lib/database-meta.types"
import {
  columnsSchemaQueryOptions,
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
    const tableMeta = JSON.parse(
      context.tableSchema?.comment ?? "{}"
    ) as TableMetadata
    const metaJoins = tableMeta.query?.join

    const allowedTabs = tableMeta.tabs
    if (allowedTabs && !allowedTabs.includes(tab)) throw notFound()

    const embeddedTables = addEmbedKeys(
      schema,
      resource,
      relatedTablesSchema,
      metaJoins
    )
    const activeTable = embeddedTables.find((t) => t.__embedKey === tab)
    if (!activeTable) throw notFound()

    const columnsSchema = await context.queryClient.ensureQueryData(
      columnsSchemaQueryOptions(activeTable.schema, activeTable.name)
    )
    const classification = classifyRelationships(
      schema,
      resource,
      activeTable,
      columnsSchema
    )

    const oneToOne = classification.oneToOne
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
      return classification
    }

    const many = classification.oneToMany ?? classification.manyToMany
    if (!many) throw notFound()

    const primaryKeys = context.tableSchema?.primary_keys ?? []
    const pkName = primaryKeys[0]?.name ?? "id"
    const pk = { [pkName]: resourceId }
    await context.queryClient.ensureQueryData(
      singleResourceDataQueryOptions(schema, resource, pk)
    )

    return classification
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { schema, resource, resourceId } = Route.useParams()
  const { oneToOne, oneToMany, manyToMany } = Route.useLoaderData()
  const { pkName } = parentRoute.useLoaderData()

  const pk = { [pkName]: resourceId }

  const many = oneToMany ?? manyToMany

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
