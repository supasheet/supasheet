import { mutationOptions, queryOptions } from "@tanstack/react-query"

import type { ColumnFiltersState } from "@tanstack/react-table"

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
  page: number,
  pageSize: number,
  sortId?: string,
  sortDesc?: boolean,
  filters: ColumnFiltersState = []
) =>
  queryOptions({
    queryKey: [
      "supasheet",
      "template-data",
      schema,
      viewName,
      page,
      pageSize,
      sortId,
      sortDesc,
      filters,
    ],
    queryFn: async () => {
      let query = supabase
        .schema(schema)
        .from(viewName)
        .select("*", { count: "exact" })
        .range((page - 1) * pageSize, page * pageSize - 1)

      if (sortId) {
        query = query.order(sortId, { ascending: !sortDesc })
      }

      query = applyFilters(query, filters)

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
