import { Outlet, createFileRoute, notFound } from "@tanstack/react-router"

import z from "zod"

import type {
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  UpdatableViewMetadata,
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
    const [privileges, tableSchemaResult, columnsSchemaResult] =
      await Promise.all([
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

    let resolvedTableSchema = tableSchemaResult
    let columnsSchema = columnsSchemaResult

    const viewSchema = !resolvedTableSchema
      ? await context.queryClient.ensureQueryData(
          viewSchemaQueryOptions(schema, resource)
        )
      : null

    if (viewSchema) {
      const viewMetadata = JSON.parse(
        viewSchema.comment ?? "{}"
      ) as UpdatableViewMetadata
      if (viewMetadata.based_on) {
        const [tableSchema, resolvedColumnsSchema] = await Promise.all([
          context.queryClient.ensureQueryData(
            tableSchemaQueryOptions(schema, viewMetadata.based_on)
          ),
          context.queryClient.ensureQueryData(
            columnsSchemaQueryOptions(schema, viewMetadata.based_on)
          ),
        ])
        if (tableSchema) {
          const resolvedPrimaryKeys = tableSchema.primary_keys

          if (resolvedPrimaryKeys?.length === 1) {
            const pkExposed = columnsSchema?.some(
              (c) => c.name === resolvedPrimaryKeys[0].name
            )
            if (!pkExposed) throw notFound()
            resolvedTableSchema = {
              ...tableSchema,
              name: viewSchema.name,
              comment: viewSchema.comment ?? null,
              primary_keys: resolvedPrimaryKeys,
            }
          }

          if (resolvedColumnsSchema && columnsSchema) {
            const resourceColumnNames = new Set(
              columnsSchema.map((c) => c.name)
            )
            columnsSchema = resolvedColumnsSchema.filter((c) =>
              resourceColumnNames.has(c.name)
            )
          }
        }
      }
    }

    const resourceSchema = resolvedTableSchema ?? viewSchema
    if (!resourceSchema) throw notFound()
    if (!columnsSchema?.length) throw notFound()

    return { privileges, resourceSchema, columnsSchema }
  },
  component: RouteComponent,
})

function RouteComponent() {
  return <Outlet />
}
