import { PolarAngleAxis, PolarGrid, Radar, RadarChart } from "recharts"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
} from "#/components/ui/chart"
import type { ChartConfig } from "#/components/ui/chart"
import type { ChartMeta } from "#/lib/supabase/data/chart"

const CHART_COLORS = [
  "var(--chart-1)",
  "var(--chart-2)",
  "var(--chart-3)",
  "var(--chart-4)",
  "var(--chart-5)",
]

export function RadarChartWidget({
  chartMeta,
  data,
}: {
  chartMeta: ChartMeta
  data: Record<string, unknown>[] | null
}) {
  if (!data || data.length === 0) {
    return (
      <Card className="col-span-2">
        <CardHeader>
          <CardTitle>{chartMeta.name}</CardTitle>
          {chartMeta.description && (
            <CardDescription>{chartMeta.description}</CardDescription>
          )}
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">No data available</p>
        </CardContent>
      </Card>
    )
  }

  const firstItem = data[0]
  const allKeys = Object.keys(firstItem)
  const axisKey = allKeys[0]
  const keys = allKeys.slice(1).filter((k) => !isNaN(Number(firstItem[k])))

  if (keys.length === 0) {
    return (
      <Card className="col-span-2">
        <CardHeader>
          <CardTitle>{chartMeta.name}</CardTitle>
          {chartMeta.description && (
            <CardDescription>{chartMeta.description}</CardDescription>
          )}
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">No numeric data found</p>
        </CardContent>
      </Card>
    )
  }

  const chartConfig: ChartConfig = {}
  keys.forEach((key, index) => {
    chartConfig[key] = {
      label: key.charAt(0).toUpperCase() + key.slice(1).replace(/_/g, " "),
      color: CHART_COLORS[index % CHART_COLORS.length],
    }
  })

  const chartData = data.map((item) => {
    const processed: Record<string, unknown> = { [axisKey]: item[axisKey] }
    keys.forEach((key) => {
      processed[key] = Number(item[key]) || 0
    })
    return processed
  })

  return (
    <Card className="col-span-2">
      <CardHeader>
        <CardTitle>{chartMeta.name}</CardTitle>
        {chartMeta.description && (
          <CardDescription>{chartMeta.description}</CardDescription>
        )}
      </CardHeader>
      <CardContent className="pb-0">
        <ChartContainer
          config={chartConfig}
          className="mx-auto aspect-square max-h-[250px]"
        >
          <RadarChart data={chartData}>
            <ChartTooltip cursor={false} content={<ChartTooltipContent />} />
            <PolarAngleAxis dataKey={axisKey} />
            <PolarGrid />
            {keys.map((key) => (
              <Radar
                key={key}
                dataKey={key}
                fill={`var(--color-${key})`}
                fillOpacity={0.6}
              />
            ))}
          </RadarChart>
        </ChartContainer>
        {chartMeta.caption && (
          <p className="mt-2 text-xs text-muted-foreground">
            {chartMeta.caption}
          </p>
        )}
      </CardContent>
    </Card>
  )
}
