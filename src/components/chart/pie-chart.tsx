import { Pie, PieChart } from "recharts"

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

export function PieChartWidget({
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
  const labelKey = allKeys[0]
  const valueKey = allKeys[1] ?? allKeys[0]

  const chartConfig: ChartConfig = {}
  const chartData = data.map((item, index) => {
    const label = String(item[labelKey])
    const value = Number(item[valueKey]) || 0
    chartConfig[label] = {
      label,
      color: CHART_COLORS[index % CHART_COLORS.length],
    }
    return { name: label, value, fill: `var(--color-${label})` }
  })

  return (
    <Card className="col-span-2">
      <CardHeader>
        <CardTitle>{chartMeta.name}</CardTitle>
        {chartMeta.description && (
          <CardDescription>{chartMeta.description}</CardDescription>
        )}
      </CardHeader>
      <CardContent className="flex-1 pb-0">
        <ChartContainer
          config={chartConfig}
          className="mx-auto aspect-square max-h-[250px]"
        >
          <PieChart>
            <ChartTooltip
              cursor={false}
              content={<ChartTooltipContent hideLabel />}
            />
            <Pie
              data={chartData}
              dataKey="value"
              nameKey="name"
              innerRadius={60}
              strokeWidth={5}
            />
          </PieChart>
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
