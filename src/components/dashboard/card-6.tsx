import { useSuspenseQuery } from "@tanstack/react-query"

import { TrendingDownIcon, TrendingUpIcon } from "lucide-react"
import { DynamicIcon } from "lucide-react/dynamic"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { widgetDataQueryOptions } from "#/lib/supabase/data/dashboard"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

type CardMetric = {
  label: string
  value: string | number
  trend?: number
  icon?: string
}

// Column count tracks the actual item count (capped at 6) so the grid always
// divides the row evenly instead of leaving trailing columns empty.
const METRIC_GRID_CLASSES: Record<number, string> = {
  1: "grid-cols-1",
  2: "grid-cols-2",
  3: "grid-cols-3",
  4: "grid-cols-2 @sm/stats:grid-cols-4",
  5: "grid-cols-2 @sm/stats:grid-cols-3 @lg/stats:grid-cols-5",
  6: "grid-cols-2 @sm/stats:grid-cols-3 @lg/stats:grid-cols-6",
}

function metricGridClass(count: number) {
  return METRIC_GRID_CLASSES[Math.min(count, 6)] ?? METRIC_GRID_CLASSES[6]
}

function CardMetricBlock({ metric }: { metric: CardMetric }) {
  return (
    <div className="space-y-1">
      <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {metric.icon && (
          <DynamicIcon name={metric.icon as never} className="size-3.5" />
        )}
        <span className="truncate">{metric.label}</span>
      </div>
      <div className="flex items-baseline gap-1.5">
        <span className="text-xl font-semibold tabular-nums">
          {metric.value}
        </span>
        {typeof metric.trend === "number" && (
          <span
            className={`flex items-center text-xs font-medium ${
              metric.trend >= 0
                ? "text-emerald-600 dark:text-emerald-500"
                : "text-destructive"
            }`}
          >
            {metric.trend >= 0 ? (
              <TrendingUpIcon className="size-3" />
            ) : (
              <TrendingDownIcon className="size-3" />
            )}
            {metric.trend > 0 ? "+" : ""}
            {metric.trend}%
          </span>
        )}
      </div>
    </div>
  )
}

export function Card6Skeleton() {
  return (
    <Card className="col-span-1 md:col-span-2 lg:col-span-4">
      <CardHeader>
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-3 w-48" />
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="space-y-2">
              <Skeleton className="h-3 w-16" />
              <Skeleton className="h-6 w-20" />
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

export function Card6<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )

  const widgetData = data?.[0]
  const metrics = (widgetData?.metrics ?? []) as CardMetric[]
  if (metrics.length === 0) return null

  return (
    <Card className="col-span-1 @container/stats md:col-span-2 lg:col-span-4">
      <CardHeader>
        <CardTitle>{widget.name}</CardTitle>
        <CardDescription>{widget.description}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className={`grid gap-4 ${metricGridClass(metrics.length)}`}>
          {metrics.map((metric, index) => (
            <CardMetricBlock key={index} metric={metric} />
          ))}
        </div>
      </CardContent>
    </Card>
  )
}
