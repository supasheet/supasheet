import { queryOptions } from "@tanstack/react-query"

import type {
  DashboardWidgetMeta,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"

export type DashboardWidgetSchema<S extends DatabaseSchemas> = {
  schema: S
  view_name: DatabaseViews<S>
} & DashboardWidgetMeta

export const dashboardWidgetsQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource?: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "dashboard-widgets", schema, resource ?? null],
    queryFn: async () => {
      const args: { p_schema?: string; p_resource?: string } = {
        p_schema: schema,
        p_resource: resource,
      }
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_widgets", args)
      if (error) throw error

      return data.map((widget) => {
        const meta = (
          widget.comment ? JSON.parse(widget.comment) : {}
        ) as DashboardWidgetMeta
        return {
          view_name: widget.name,
          schema: widget.schema,
          ...meta,
        } as DashboardWidgetSchema<typeof schema>
      })
    },
    staleTime: 1000 * 60 * 5,
  })

export const widgetDataQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  viewName: DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "widget-data", schema, viewName],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema(schema)
        .from(viewName)
        .select("*")
      if (error) throw error

      // Widget cards read typed fields (value/label/percent/icon) directly and
      // do arithmetic on them, so `any` is intentional here — unlike the
      // chart/report data paths whose consumers narrow via Number()/String().
      return (data ?? []) as Record<string, any>[]
    },
    staleTime: 1000 * 60 * 5,
  })
