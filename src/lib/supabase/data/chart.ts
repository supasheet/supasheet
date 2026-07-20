import { queryOptions } from "@tanstack/react-query"

import type {
  ChartMeta,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"

export type ChartSchema<S extends DatabaseSchemas> = {
  schema: S
  view_name: DatabaseViews<S>
} & ChartMeta

export const chartsQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource?: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "charts", schema, resource ?? null],
    queryFn: async () => {
      const args: { p_schema?: string; p_resource?: string } = {
        p_schema: schema,
        p_resource: resource,
      }
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_charts", args)
      if (error) throw error

      return data.map((chart) => {
        const meta = (
          chart.comment ? JSON.parse(chart.comment) : {}
        ) as ChartMeta
        return {
          view_name: chart.name,
          schema: chart.schema,
          ...meta,
        } as ChartSchema<typeof schema>
      })
    },
    staleTime: 1000 * 60 * 5,
  })

export const chartDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  viewName: DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "chart-data", schema, viewName],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema(schema)
        .from(viewName)
        .select("*")
      if (error) throw error

      return (data ?? []) as Record<string, unknown>[]
    },
    staleTime: 1000 * 60 * 5,
  })
