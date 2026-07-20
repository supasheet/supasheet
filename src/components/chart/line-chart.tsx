import { CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts"

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
import type { ChartMeta } from "#/lib/database-meta.types"

const CHART_COLORS = [
  "var(--chart-1)",
  "var(--chart-2)",
  "var(--chart-3)",
  "var(--chart-4)",
  "var(--chart-5)",
]

export function LineChartWidget({
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
  const xAxisKey = allKeys[0]
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
    const processed: Record<string, unknown> = { [xAxisKey]: item[xAxisKey] }
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
      <CardContent>
        <ChartContainer config={chartConfig}>
          <LineChart
            accessibilityLayer
            data={chartData}
            margin={{ left: 12, right: 12 }}
          >
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey={xAxisKey}
              tickLine={false}
              axisLine={false}
              tickMargin={8}
            />
            <YAxis tickLine={false} axisLine={false} tickMargin={8} />
            <ChartTooltip cursor={false} content={<ChartTooltipContent />} />
            {keys.map((key) => (
              <Line
                key={key}
                dataKey={key}
                type="monotone"
                stroke={`var(--color-${key})`}
                strokeWidth={2}
                dot={false}
              />
            ))}
          </LineChart>
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
