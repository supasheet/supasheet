import { useSuspenseQuery } from "@tanstack/react-query"

import { TrendingDown, TrendingUpIcon } from "lucide-react"

import { Badge } from "#/components/ui/badge"
import {
  Card,
  CardAction,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { widgetDataQueryOptions } from "#/lib/supabase/data/dashboard"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

export function Card3Skeleton() {
  return (
    <Card className="@container/card">
      <CardHeader>
        <Skeleton className="h-3 w-28" />
        <Skeleton className="h-8 w-24" />
        <CardAction>
          <Skeleton className="h-6 w-16 rounded-full" />
        </CardAction>
      </CardHeader>
      <CardFooter className="flex-col items-start text-sm">
        <Skeleton className="mb-1 h-4 w-32" />
        <Skeleton className="h-3 w-40" />
      </CardFooter>
    </Card>
  )
}

export function Card3<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )

  const widgetData = data?.[0]
  if (!widgetData) return null

  return (
    <Card className="@container/card">
      <CardHeader>
        <CardDescription>{widget.caption}</CardDescription>
        <CardTitle className="text-2xl font-semibold tabular-nums @[250px]/card:text-3xl">
          {widgetData.value}
        </CardTitle>
        <CardAction>
          <Badge variant="outline">
            {widgetData.percent >= 0 ? (
              <TrendingUpIcon className="size-4" />
            ) : (
              <TrendingDown className="size-4" />
            )}
            {widgetData.percent > 0 ? "+" : ""}
            {widgetData.percent}%
          </Badge>
        </CardAction>
      </CardHeader>
      <CardFooter className="flex-col items-start text-sm flex-1">
        <div className="line-clamp-1 flex gap-2 font-medium">{widget.name}</div>
        <div className="text-muted-foreground">{widget.description}</div>
      </CardFooter>
    </Card>
  )
}
