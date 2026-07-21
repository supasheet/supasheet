import { Outlet, createFileRoute, notFound } from "@tanstack/react-router"

import z from "zod"

import type {
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
} from "#/lib/database-meta.types"
import {
  columnsSchemaQueryOptions,
  resourcePrivilegesQueryOptions,
  tableSchemaQueryOptions,
  viewSchemaQueryOptions,
} from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/$schema/resource/$resource")({
  params: z.object({
    schema: z.string<DatabaseSchemas>(),
    resource: z.string<
      DatabaseTables<DatabaseSchemas> | DatabaseViews<DatabaseSchemas>
    >(),
  }),
  beforeLoad: async ({ context, params: { schema, resource } }) => {
    const [privileges, tableSchema, columnsSchema] = await Promise.all([
      context.queryClient.ensureQueryData(
        resourcePrivilegesQueryOptions(schema, resource)
      ),
      context.queryClient.ensureQueryData(
        tableSchemaQueryOptions(schema, resource)
      ),
      context.queryClient.ensureQueryData(
        columnsSchemaQueryOptions(schema, resource)
      ),
    ])

    const viewSchema = !tableSchema
      ? await context.queryClient.ensureQueryData(
          viewSchemaQueryOptions(schema, resource)
        )
      : null

    const resourceSchema = tableSchema ?? viewSchema
    if (!resourceSchema) throw notFound()
    if (!columnsSchema?.length) throw notFound()

    return { privileges, resourceSchema, columnsSchema }
  },
  component: RouteComponent,
})

function RouteComponent() {
  return <Outlet />
}
