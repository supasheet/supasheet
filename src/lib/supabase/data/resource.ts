import { mutationOptions, queryOptions } from "@tanstack/react-query"
import type { QueryClient } from "@tanstack/react-query"

import type { ColumnFiltersState } from "@tanstack/react-table"

import { SYSTEM_SCHEMAS } from "#/config/database.config"
import type {
  ColumnSchema,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  TableMetadata,
  TableSchema,
  UpdatableViewMetadata,
  ViewMetadata,
  ViewSchema,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"
import { applyFilters } from "#/lib/supabase/filter"

export async function resolveResourceSchema(
  queryClient: QueryClient,
  schema: DatabaseSchemas,
  resource: string
): Promise<{
  resourceSchema: TableSchema | ViewSchema | null
  columnsSchema: ColumnSchema[] | null
}> {
  const r = resource as DatabaseTables<typeof schema>

  let [resolvedTableSchema, columnsSchema] = await Promise.all([
    queryClient.ensureQueryData(tableSchemaQueryOptions(schema, r)),
    queryClient.ensureQueryData(columnsSchemaQueryOptions(schema, r)),
  ])

  const viewSchema = !resolvedTableSchema
    ? await queryClient.ensureQueryData(viewSchemaQueryOptions(schema, r))
    : null

  if (viewSchema) {
    const viewMetadata = JSON.parse(
      viewSchema.comment ?? "{}"
    ) as UpdatableViewMetadata
    if (viewMetadata.based_on) {
      const [tableSchema, resolvedColumnsSchema] = await Promise.all([
        queryClient.ensureQueryData(
          tableSchemaQueryOptions(schema, viewMetadata.based_on)
        ),
        queryClient.ensureQueryData(
          columnsSchemaQueryOptions(schema, viewMetadata.based_on)
        ),
      ])
      if (tableSchema) {
        const resolvedPrimaryKeys = tableSchema.primary_keys

        if (resolvedPrimaryKeys?.length === 1) {
          const pkExposed = columnsSchema?.some(
            (c) => c.name === resolvedPrimaryKeys[0].name
          )
          if (!pkExposed) {
            return { resourceSchema: null, columnsSchema: null }
          }
          resolvedTableSchema = {
            ...tableSchema,
            name: viewSchema.name,
            comment: viewSchema.comment ?? null,
            primary_keys: resolvedPrimaryKeys,
          }
        }

        if (resolvedColumnsSchema && columnsSchema) {
          const resourceColumnNames = new Set(columnsSchema.map((c) => c.name))
          columnsSchema = resolvedColumnsSchema.filter((c) =>
            resourceColumnNames.has(c.name)
          )
        }
      }
    }
  }

  return {
    resourceSchema: resolvedTableSchema ?? viewSchema,
    columnsSchema,
  }
}

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
          meta: (resource.comment
            ? JSON.parse(resource.comment)
            : {}) as TableMetadata,
        }))
        .filter((resource) => resource.meta.display !== "none")

      const viewResources = (viewSchema.data ?? [])
        .map((resource) => ({
          name: resource.name as DatabaseViews<typeof schema>,
          id: resource.name as DatabaseViews<typeof schema>,
          schema: resource.schema as typeof schema,
          type: "view" as const,
          meta: (resource.comment
            ? JSON.parse(resource.comment)
            : {}) as ViewMetadata,
        }))
        .filter((resource) => resource.meta.display === "block")

      const matViewResources = (matViewSchema.data ?? [])
        .map((resource) => ({
          name: resource.name as DatabaseViews<typeof schema>,
          id: resource.name as DatabaseViews<typeof schema>,
          schema: resource.schema as typeof schema,
          type: "view" as const,
          meta: (resource.comment
            ? JSON.parse(resource.comment)
            : {}) as ViewMetadata,
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
  id: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "columns", schema, id],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_columns", { schema_name: schema, table_name: id })
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

export const resourceDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>,
  defaultQuery: TableMetadata["query"],
  page?: number,
  pageSize?: number,
  sortId?: string,
  sortDesc?: boolean,
  filters: ColumnFiltersState = []
) =>
  queryOptions({
    queryKey: [
      "supasheet",
      "resource-data",
      schema,
      resource,
      page,
      pageSize,
      sortId,
      sortDesc,
      filters,
    ],
    queryFn: async () => {
      const joins =
        defaultQuery?.join?.map(
          (j) =>
            `,${j.alias ? `${j.alias}:` : ""}${j.table}!${j.on}(${j.columns.join(",")})`
        ) || []

      let query = supabase
        .schema(schema)
        .from(resource)
        .select((defaultQuery?.select?.join(",") ?? "*") + joins.join(""), {
          count: "exact",
        })

      if (page && pageSize) {
        query = query.range((page - 1) * pageSize, page * pageSize - 1)
      }

      if (sortId) {
        query = query.order(sortId, { ascending: !sortDesc })
      } else if (defaultQuery?.sort?.length) {
        for (const s of defaultQuery.sort) {
          query = query.order(s.id, { ascending: !s.desc })
        }
      }

      const metaFilters: ColumnFiltersState =
        defaultQuery?.filter?.map((f) => ({
          id: f.id,
          value: `${f.operator}.${Array.isArray(f.value) ? f.value.join(",") : f.value}`,
        })) ?? []
      query = applyFilters(query, [...metaFilters, ...filters])

      const { data, count, error } = await query
      if (error) throw error

      return {
        result: (data ?? []) as unknown as Record<string, unknown>[],
        count: count,
      }
    },
    staleTime: 1000 * 60 * 2,
  })

export const foreignTableDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>,
  parentResource: DatabaseTables<S> | DatabaseViews<S>,
  parentColumn: string,
  parentValue: unknown,
  defaultQuery?: TableMetadata["query"],
  selectClause?: string,
  page?: number,
  pageSize?: number,
  sortId?: string,
  sortDesc?: boolean,
  filters: ColumnFiltersState = []
) =>
  queryOptions({
    queryKey: [
      "supasheet",
      "resource-data",
      schema,
      resource,
      "foreign",
      parentResource,
      parentColumn,
      parentValue,
      defaultQuery,
      selectClause,
      page,
      pageSize,
      sortId,
      sortDesc,
      filters,
    ],
    queryFn: async () => {
      const joins =
        defaultQuery?.join?.map(
          (j) =>
            `,${j.alias ? `${j.alias}:` : ""}${j.table}!${j.on}(${j.columns.join(",")})`
        ) || []

      const baseSelect = selectClause ?? defaultQuery?.select?.join(",") ?? "*"

      let query = supabase
        .schema(schema)
        .from(resource)
        .select(baseSelect + joins.join(""), { count: "exact" })
        .eq(parentColumn as never, parentValue as never)

      if (page && pageSize) {
        query = query.range((page - 1) * pageSize, page * pageSize - 1)
      }

      if (sortId) {
        query = query.order(sortId, { ascending: !sortDesc })
      } else if (defaultQuery?.sort?.length) {
        for (const s of defaultQuery.sort) {
          query = query.order(s.id, { ascending: !s.desc })
        }
      }

      const metaFilters: ColumnFiltersState =
        defaultQuery?.filter?.map((f) => ({
          id: f.id,
          value: `${f.operator}.${Array.isArray(f.value) ? f.value.join(",") : f.value}`,
        })) ?? []
      query = applyFilters(query, [...metaFilters, ...filters])

      const { data, count, error } = await query
      if (error) throw error

      return {
        result: (data ?? []) as unknown as Record<string, unknown>[],
        count: count,
      }
    },
    staleTime: 1000 * 60 * 2,
  })

export const singleResourceDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>,
  pk: Record<string, unknown>,
  defaultQuery?: TableMetadata["query"]
) =>
  queryOptions({
    queryKey: [
      "supasheet",
      "resource-data",
      schema,
      resource,
      "single",
      pk,
      defaultQuery?.join ?? null,
    ],
    queryFn: async () => {
      const joins =
        defaultQuery?.join?.map(
          (j) =>
            `,${j.alias ? `${j.alias}:` : ""}${j.table}!${j.on}(${j.columns.join(",")})`
        ) || []

      let query = supabase
        .schema(schema)
        .from(resource)
        .select("*" + joins.join(""))
      for (const [col, val] of Object.entries(pk)) {
        query = query.eq(col as never, val as never)
      }
      const { data, error } = await query.maybeSingle()
      if (error) throw error

      return data ?? (null as Record<string, unknown> | null)
    },
    staleTime: 0,
  })

export const singleForeignTableDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>,
  match: Record<string, unknown>
) =>
  queryOptions({
    queryKey: [
      "supasheet",
      "resource-data",
      schema,
      resource,
      "single-foreign",
      match,
    ],
    queryFn: async () => {
      let query = supabase.schema(schema).from(resource).select("*")
      for (const [col, val] of Object.entries(match)) {
        query = query.eq(col as never, val as never)
      }
      const { data, error } = await query.maybeSingle()
      if (error) throw error

      return data ?? (null as Record<string, unknown> | null)
    },
    staleTime: 0,
  })

export const insertResourceMutationOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  mutationOptions({
    mutationFn: async (row: Record<string, unknown>) => {
      const { data, error } = await supabase
        .schema(schema)
        .from(resource)
        .insert(row as never)
        .select()
        .single()
      if (error) throw error
      return data as Record<string, unknown> | null
    },
  })

export const insertBulkResourceMutationOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  mutationOptions({
    mutationFn: async (rows: Record<string, unknown>[]) => {
      const { error } = await supabase
        .schema(schema)
        .from(resource)
        .insert(rows as never)
      if (error) throw error
    },
  })

export const updateResourceMutationOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  mutationOptions({
    mutationFn: async ({
      pk,
      data,
    }: {
      pk: Record<string, unknown>
      data: Record<string, unknown>
    }) => {
      let query = supabase
        .schema(schema)
        .from(resource)
        .update(data as never)
        .select()
      for (const [col, val] of Object.entries(pk)) {
        query = query.eq(col as never, val as never)
      }
      const { data: updated, error } = await query
      if (error) throw error
      if (!updated || updated.length === 0) {
        throw new Error(
          "Update failed: you may not have permission to modify this record"
        )
      }
    },
  })

export const deleteResourceMutationOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  mutationOptions({
    mutationFn: async (pk: Record<string, unknown>) => {
      let query = supabase.schema(schema).from(resource).delete()
      for (const [col, val] of Object.entries(pk)) {
        query = query.eq(col as never, val as never)
      }
      const { error } = await query
      if (error) throw error

      // Verify the delete (hard or soft) actually took effect by checking
      // whether the row is still visible. If it is, RLS denied the operation.
      let checkQuery = supabase
        .schema(schema)
        .from(resource)
        .select("*", { head: true, count: "exact" })
      for (const [col, val] of Object.entries(pk)) {
        checkQuery = checkQuery.eq(col as never, val as never)
      }
      const { count, error: checkError } = await checkQuery
      if (checkError) throw checkError
      if (count && count > 0) {
        throw new Error(
          "Delete failed: you may not have permission to delete this record"
        )
      }
    },
  })

const toPostgrestLiteral = (val: unknown): string => {
  if (typeof val === "string") {
    return `"${val.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
  }
  return String(val)
}

export const deleteBulkResourceMutationOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  mutationOptions({
    mutationFn: async (pks: Record<string, unknown>[]) => {
      if (pks.length === 0) return
      const keys = Object.keys(pks[0])

      let query = supabase.schema(schema).from(resource).delete()
      let checkQuery = supabase
        .schema(schema)
        .from(resource)
        .select("*", { head: true, count: "exact" })

      if (keys.length === 1) {
        const col = keys[0]
        const values = pks.map((pk) => pk[col])
        query = query.in(col as never, values)
        checkQuery = checkQuery.in(col as never, values)
      } else {
        const orFilter = pks
          .map(
            (pk) =>
              `and(${keys
                .map((col) => `${col}.eq.${toPostgrestLiteral(pk[col])}`)
                .join(",")})`
          )
          .join(",")
        query = query.or(orFilter)
        checkQuery = checkQuery.or(orFilter)
      }

      const { error } = await query
      if (error) throw error

      const { count, error: checkError } = await checkQuery
      if (checkError) throw checkError
      if (count && count > 0) {
        throw new Error(
          "Delete failed: you may not have permission to delete some records"
        )
      }
    },
  })

export type ResourceAuditLog = {
  id: string
  created_at: string
  operation: string
  schema_name: string
  table_name: string
  record_id: string | null
  created_by: string | null
  role: string | null
  user_type: string
  metadata: Record<string, unknown> | null
  old_data: Record<string, unknown> | null
  new_data: Record<string, unknown> | null
  changed_fields: string[] | null
  is_error: boolean
  error_message: string | null
  error_code: string | null
  created_by_name: string | null
  created_by_email: string | null
  created_by_picture_url: string | null
}

export const resourceAuditLogsQueryOptions = (
  schema: string,
  resource: string,
  recordId?: string
) =>
  queryOptions({
    queryKey: ["supasheet", "resource-audit-logs", schema, resource, recordId],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_audit_logs", {
          p_schema: schema,
          p_table: resource,
          p_record_id: recordId ?? undefined,
        })
      if (error) throw error
      return (data ?? []) as ResourceAuditLog[]
    },
  })

export type ResourceComment = {
  id: string
  created_at: string
  updated_at: string
  schema_name: string
  table_name: string
  record_id: string
  content: string
  created_by: string | null
  created_by_name: string | null
  created_by_email: string | null
  created_by_picture_url: string | null
}

export const resourceCommentsQueryOptions = (
  schema: string,
  resource: string,
  recordId: string
) =>
  queryOptions({
    queryKey: ["supasheet", "resource-comments", schema, resource, recordId],
    queryFn: async () => {
      const { data, error } = await supabase.schema("supasheet").rpc(
        "get_comments" as never,
        {
          p_schema: schema,
          p_table: resource,
          p_record_id: recordId,
        } as never
      )
      if (error) throw error
      return data ?? []
    },
  })

export const insertCommentMutationOptions = () =>
  mutationOptions({
    mutationFn: async (payload: {
      schema_name: string
      table_name: string
      record_id: string
      content: string
      created_by: string
    }) => {
      const { error } = await supabase
        .schema("supasheet")
        .from("comments" as never)
        .insert(payload as never)
      if (error) throw error
    },
  })

export const updateCommentMutationOptions = () =>
  mutationOptions({
    mutationFn: async ({ id, content }: { id: string; content: string }) => {
      const { error } = await supabase
        .schema("supasheet")
        .from("comments" as never)
        .update({ content, updated_at: new Date().toISOString() } as never)
        .eq("id", id)
      if (error) throw error
    },
  })

export const deleteCommentMutationOptions = () =>
  mutationOptions({
    mutationFn: async (id: string) => {
      const { error } = await supabase
        .schema("supasheet")
        .from("comments" as never)
        .delete()
        .eq("id", id)
      if (error) throw error
    },
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
      return data as unknown as (TableSchema & { columns: ColumnSchema[] })[]
    },
    staleTime: 1000 * 60 * 5,
  })
