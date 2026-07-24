import { queryOptions } from "@tanstack/react-query"

import type { ColumnFiltersState } from "@tanstack/react-table"

import type {
  DatabaseSchemas,
  DatabaseViews,
  ReportMeta,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"
import { applyFilters } from "#/lib/supabase/filter"

export type ReportSchema<S extends DatabaseSchemas> = {
  schema: S
  view_name: DatabaseViews<S>
} & ReportMeta

export const reportsQueryOptions = (schema: DatabaseSchemas) =>
  queryOptions({
    queryKey: ["supasheet", "reports", schema],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_reports", { p_schema: schema })
      if (error) throw error

      return data.map((report) => {
        const meta = (
          report.comment ? JSON.parse(report.comment) : {}
        ) as ReportMeta
        return {
          view_name: report.name,
          schema: report.schema,
          ...meta,
        } as ReportSchema<typeof schema>
      })
    },
    staleTime: 1000 * 60 * 5,
  })

export const reportDataQueryOptions = <S extends DatabaseSchemas>(
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
      "report-data",
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
