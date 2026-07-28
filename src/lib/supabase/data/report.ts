import { queryOptions } from "@tanstack/react-query"

import type { ColumnFiltersState } from "@tanstack/react-table"

import type {
  DatabaseSchemas,
  DatabaseViews,
  ReportMeta,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"
import { applyFilters } from "#/lib/supabase/filter"

export const REPORT_TEMPLATES_BUCKET = "report-templates"

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

export const reportQueryOptions = (
  schema: DatabaseSchemas,
  viewName: DatabaseViews<DatabaseSchemas>
) =>
  queryOptions({
    queryKey: ["supasheet", "report", schema, viewName],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_reports", { p_schema: schema, p_view_name: viewName })
      if (error) throw error

      const report = data[0]
      if (!report) return null

      const meta = (
        report.comment ? JSON.parse(report.comment) : {}
      ) as ReportMeta
      return {
        view_name: report.name,
        schema: report.schema,
        ...meta,
      } as ReportSchema<typeof schema>
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

export const reportTemplateQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  viewName: DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "report-template", schema, viewName],
    queryFn: async () => {
      const { data, error } = await supabase.storage
        .from(REPORT_TEMPLATES_BUCKET)
        .download(`${schema}/${viewName}.hbs`)
      if (error) throw error

      return data.text()
    },
    staleTime: 1000 * 60 * 5,
  })
