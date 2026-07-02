import { useSuspenseQuery } from "@tanstack/react-query"

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

export function Card1Skeleton() {
  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2">
        <div className="space-y-1">
          <Skeleton className="h-4 w-24" />
          <Skeleton className="h-3 w-32" />
        </div>
        <Skeleton className="h-4 w-4 rounded" />
      </CardHeader>
      <CardContent>
        <Skeleton className="mb-1 h-8 w-20" />
        <Skeleton className="h-3 w-28" />
      </CardContent>
    </Card>
  )
}

export function Card1<S extends DatabaseSchemas>({
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
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2">
        <div>
          <CardTitle className="text-sm font-medium">{widget.name}</CardTitle>
          <CardDescription>{widget.description}</CardDescription>
        </div>
        <DynamicIcon
          name={widgetData.icon as never}
          className="relative z-10 h-4 w-4 text-muted-foreground"
        />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{widgetData.value}</div>
        <p className="text-xs text-muted-foreground">{widgetData.label}</p>
      </CardContent>
    </Card>
  )
}
