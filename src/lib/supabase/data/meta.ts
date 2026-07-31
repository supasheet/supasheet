import { queryOptions } from "@tanstack/react-query"

import { SYSTEM_SCHEMAS } from "#/config/database.config"
import type {
  ColumnSchema,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  TableMetadata,
  TableSchema,
  ViewMetadata,
  ViewSchema,
} from "#/lib/database-meta.types"
import { parseComment } from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"

export const navItemsQueryOptions = (schema: DatabaseSchemas) =>
  queryOptions({
    queryKey: ["supasheet", "nav-items", schema],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_nav_items", { schema_name: schema })
      if (error) throw error
      return data ?? []
    },
    staleTime: 1000 * 60 * 5,
  })

export const schemasQueryOptions = queryOptions({
  queryKey: ["supasheet", "schema", "schemas"],
  queryFn: async () => {
    const { data, error } = await supabase
      .schema("supasheet")
      .rpc("get_schemas")
    if (error) throw error
    return [
      ...data.filter((s) => !SYSTEM_SCHEMAS.includes(s.schema)),
      { schema: "core" },
    ] as { schema: DatabaseSchemas }[]
  },
  staleTime: 1000 * 60 * 5,
})

export const resourcesQueryOptions = (schema: DatabaseSchemas) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "resources", schema],
    queryFn: async () => {
      const [tableSchema, viewSchema, matViewSchema] = await Promise.all([
        supabase.schema("supasheet").rpc("get_tables", { schema_name: schema }),
        supabase.schema("supasheet").rpc("get_views", { schema_name: schema }),
        supabase
          .schema("supasheet")
          .rpc("get_materialized_views", { schema_name: schema }),
      ])

      const tableResources = (tableSchema.data ?? [])
        .map((resource) => ({
          name: resource.name as DatabaseTables<typeof schema>,
          id: resource.name as DatabaseTables<typeof schema>,
          schema: resource.schema as typeof schema,
          type: "table" as const,
          meta: parseComment<TableMetadata>(resource.comment, {}),
        }))
        .filter((resource) => resource.meta.display !== "none")

      const viewResources = (viewSchema.data ?? [])
        .map((resource) => ({
          name: resource.name as DatabaseViews<typeof schema>,
          id: resource.name as DatabaseViews<typeof schema>,
          schema: resource.schema as typeof schema,
          type: "view" as const,
          meta: parseComment<ViewMetadata>(resource.comment, {}),
        }))
        .filter((resource) => resource.meta.display === "block")

      const matViewResources = (matViewSchema.data ?? [])
        .map((resource) => ({
          name: resource.name as DatabaseViews<typeof schema>,
          id: resource.name as DatabaseViews<typeof schema>,
          schema: resource.schema as typeof schema,
          type: "view" as const,
          meta: parseComment<ViewMetadata>(resource.comment, {}),
        }))
        .filter((resource) => resource.meta.display === "block")

      return [...tableResources, ...viewResources, ...matViewResources]
    },
    staleTime: 1000 * 60 * 5,
  })

export type ResourcePrivilege = "select" | "insert" | "update" | "delete"

export const resourcePrivilegesQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "privileges", schema, resource],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_privileges", {
          schema_name: schema,
          resource_name: resource,
        })
      if (error) throw error
      const rows = (data as unknown as { privilege: string }[] | null) ?? []
      return rows.map((d) => d.privilege as ResourcePrivilege)
    },
    staleTime: 1000 * 60 * 5,
  })

export const columnsSchemaQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  id: DatabaseTables<S> | DatabaseViews<S>,
  action: ResourcePrivilege = "select"
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "columns", schema, id, action],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_columns", { schema_name: schema, table_name: id, action })
      if (error) throw error
      return (data as unknown as ColumnSchema<S>[]) ?? []
    },
    staleTime: 1000 * 60 * 5,
  })

export const tableSchemaQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  id: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "table", schema, id],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_tables", { schema_name: schema, table_name: id })

      if (error) throw error
      return (data[0] ?? null) as unknown as TableSchema<S> | null
    },
    staleTime: 1000 * 60 * 5,
  })

export const viewSchemaQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  id: DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "view", schema, id],
    queryFn: async () => {
      const { data: viewData, error: viewError } = await supabase
        .schema("supasheet")
        .rpc("get_views", { schema_name: schema, view_name: id })

      if (viewError) return null

      if (viewData.length === 0) {
        const { data: matViewData, error: matViewError } = await supabase
          .schema("supasheet")
          .rpc("get_materialized_views", {
            schema_name: schema,
            view_name: id,
          })
        if (matViewError) return null
        return (matViewData[0] ?? null) as unknown as ViewSchema<S> | null
      }

      return (viewData[0] ?? null) as unknown as ViewSchema<S> | null
    },
    staleTime: 1000 * 60 * 5,
  })

export const relatedTablesSchemaQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  id: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "related_tables", schema, id],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_related_tables", {
          schema_name: schema,
          table_name: id,
        })
      if (error) throw error
      return data as unknown as TableSchema[]
    },
    staleTime: 1000 * 60 * 5,
  })
