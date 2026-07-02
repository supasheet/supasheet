import { useSuspenseQuery } from "@tanstack/react-query"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Progress } from "#/components/ui/progress"
import { Skeleton } from "#/components/ui/skeleton"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { widgetDataQueryOptions } from "#/lib/supabase/data/dashboard"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

export function Card4Skeleton() {
  return (
    <Card>
      <CardHeader>
        <Skeleton className="h-3 w-24" />
        <div className="flex items-baseline gap-2">
          <Skeleton className="h-9 w-16" />
          <Skeleton className="h-4 w-8" />
        </div>
      </CardHeader>
      <CardContent>
        <Skeleton className="h-2 w-full rounded-full" />
        <Skeleton className="mt-2 h-3 w-32" />
      </CardContent>
    </Card>
  )
}

export function Card4<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )

  const widgetData = data?.[0]
  if (!widgetData) return null

  const current = widgetData.current ?? widgetData.value ?? 0
  const total = widgetData.total ?? widgetData.max ?? 100
  const percentage = total > 0 ? Math.round((current / total) * 100) : 0

  return (
    <Card>
      <CardHeader>
        <CardDescription>{widget.name}</CardDescription>
        <div className="flex items-baseline gap-2">
          <CardTitle className="text-3xl font-bold">{current}</CardTitle>
          <span className="text-sm text-muted-foreground">/ {total}</span>
        </div>
      </CardHeader>
      <CardContent>
        <Progress value={percentage} className="h-2" />
        <p className="mt-2 text-xs text-muted-foreground">
          {percentage}% {widget.description}
        </p>
      </CardContent>
    </Card>
  )
}
