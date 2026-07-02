import { useSuspenseQuery } from "@tanstack/react-query"

import { Skeleton } from "#/components/ui/skeleton"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { chartDataQueryOptions } from "#/lib/supabase/data/chart"
import type { ChartMeta, ChartSchema } from "#/lib/supabase/data/chart"

import { AreaChartWidget } from "./area-chart"
import { BarChartWidget } from "./bar-chart"
import { LineChartWidget } from "./line-chart"
import { PieChartWidget } from "./pie-chart"
import { RadarChartWidget } from "./radar-chart"

export function ChartSkeleton() {
  return (
    <div className="col-span-2 rounded-xl border bg-card p-6">
      <div className="mb-4 flex items-center justify-between">
        <Skeleton className="h-5 w-24" />
      </div>
      <Skeleton className="mb-2 h-4 w-40" />
      <div className="mt-4">
        <Skeleton className="h-40 w-full" />
      </div>
    </div>
  )
}

export function ChartWidget<S extends DatabaseSchemas>({
  chart,
}: {
  chart: ChartSchema<S>
}) {
  const { data } = useSuspenseQuery(
    chartDataQueryOptions(chart.schema, chart.view_name)
  )

  const chartMeta: ChartMeta = {
    name: chart.name,
    description: chart.description,
    caption: chart.caption,
    type: chart.type,
    chart_type: chart.chart_type,
  }

  switch (chart.chart_type) {
    case "area":
      return <AreaChartWidget chartMeta={chartMeta} data={data ?? null} />
    case "bar":
      return <BarChartWidget chartMeta={chartMeta} data={data ?? null} />
    case "line":
      return <LineChartWidget chartMeta={chartMeta} data={data ?? null} />
    case "pie":
      return <PieChartWidget chartMeta={chartMeta} data={data ?? null} />
    case "radar":
      return <RadarChartWidget chartMeta={chartMeta} data={data ?? null} />
    default:
      return null
  }
}
