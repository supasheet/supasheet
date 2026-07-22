import { useSuspenseQuery } from "@tanstack/react-query"

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

export function Card2Skeleton() {
  return (
    <Card size="sm">
      <CardHeader>
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-3 w-32" />
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Skeleton className="h-3 w-16" />
            <Skeleton className="h-8 w-16" />
          </div>
          <div className="space-y-1 border-l pl-3">
            <Skeleton className="h-3 w-16" />
            <Skeleton className="h-8 w-16" />
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function Card2<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )

  const widgetData = data?.[0]
  if (!widgetData) return null

  const primaryValue =
    widgetData.primary ?? widgetData.value ?? widgetData.main ?? 0
  const secondaryValue =
    widgetData.secondary ?? widgetData.sub ?? widgetData.additional ?? 0
  const primaryLabel = widgetData.primary_label ?? "Primary"
  const secondaryLabel = widgetData.secondary_label ?? "Secondary"

  return (
    <Card size="sm">
      <CardHeader>
        <div>
          <CardTitle>{widget.name}</CardTitle>
          <CardDescription>{widget.description}</CardDescription>
        </div>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">{primaryLabel}</p>
            <p className="text-2xl font-bold">{primaryValue}</p>
          </div>
          <div className="space-y-1 border-l pl-3">
            <p className="text-xs text-muted-foreground">{secondaryLabel}</p>
            <p className="text-2xl font-bold">{secondaryValue}</p>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
