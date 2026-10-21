import { mutationOptions, queryOptions } from "@tanstack/react-query"

import type { TableQuery } from "#/lib/data-table-search"
import type {
  DatabaseSchemas,
  DatabaseViews,
  TemplateMeta,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"
import { applyFilters } from "#/lib/supabase/filter"

export type TemplateSchema<S extends DatabaseSchemas> = {
  schema: S
  view_name: DatabaseViews<S>
} & TemplateMeta

export const templatesQueryOptions = (schema: DatabaseSchemas) =>
  queryOptions({
    queryKey: ["supasheet", "templates", schema],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_templates", { p_schema: schema })
      if (error) throw error

      return data.map((template) => {
        const meta = (
          template.comment ? JSON.parse(template.comment) : {}
        ) as TemplateMeta
        return {
          view_name: template.name,
          schema: template.schema,
          ...meta,
        } as TemplateSchema<typeof schema>
      })
    },
    staleTime: 1000 * 60 * 5,
  })

export const templateDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  viewName: DatabaseViews<S>,
  tableQuery: TableQuery
) =>
  queryOptions({
    queryKey: ["supasheet", "template-data", schema, viewName, tableQuery],
    queryFn: async () => {
      const { page, perPage, sorting, filters, joinOperator } = tableQuery
      let query = supabase
        .schema(schema)
        .from(viewName)
        .select("*", { count: "exact" })
        .range((page - 1) * perPage, page * perPage - 1)

      for (const sort of sorting) {
        query = query.order(sort.id, { ascending: !sort.desc })
      }

      query = applyFilters(query, filters, joinOperator)

      const { data, count, error } = await query
      if (error) throw error

      return {
        result: (data ?? []) as Record<string, unknown>[],
        count: count,
      }
    },
    staleTime: 1000 * 60 * 5,
  })

export const applyTemplateMutationOptions = mutationOptions({
  mutationFn: async ({
    schema,
    templateName,
    targetTable,
  }: {
    schema: string
    templateName: string
    targetTable: string
  }) => {
    const { data, error } = await supabase
      .schema("supasheet")
      .rpc("apply_template", {
        p_schema: schema,
        p_template_name: templateName,
        p_target_table: targetTable,
      })
    if (error) throw error
    return data
  },
})
