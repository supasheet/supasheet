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

type BreakdownItem = {
  label: string
  value: number
  variant?: string
}

const BAR_VARIANT_COLORS: Record<string, string> = {
  default: "bg-primary",
  secondary: "bg-muted-foreground/40",
  success: "bg-emerald-500",
  warning: "bg-amber-500",
  destructive: "bg-destructive",
  info: "bg-blue-500",
}

function barColor(variant?: string) {
  return (variant && BAR_VARIANT_COLORS[variant]) ?? BAR_VARIANT_COLORS.default
}

export function Card5Skeleton() {
  return (
    <Card className="col-span-1 md:col-span-2">
      <CardHeader>
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-3 w-48" />
      </CardHeader>
      <CardContent>
        <div className="flex flex-col gap-6 @md/stats:flex-row @md/stats:items-center">
          <div className="space-y-2 @md/stats:w-32 @md/stats:shrink-0">
            <Skeleton className="h-3 w-20" />
            <Skeleton className="h-8 w-16" />
          </div>
          <div className="flex-1 space-y-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-6 w-full" />
            ))}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function Card5<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )

  const widgetData = data?.[0]
  const breakdown = (widgetData?.breakdown ?? []) as BreakdownItem[]
  const total = breakdown.reduce((sum, item) => sum + (item.value || 0), 0)
  const hasHeadline =
    widgetData?.value !== undefined && widgetData?.value !== null
  if (!hasHeadline && breakdown.length === 0) return null

  return (
    <Card className="col-span-1 @container/stats md:col-span-2">
      <CardHeader>
        <CardTitle>{widget.name}</CardTitle>
        <CardDescription>{widget.description}</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="flex flex-col gap-6 @md/stats:flex-row @md/stats:items-center">
          {hasHeadline && (
            <div className="flex shrink-0 flex-col gap-1 @md/stats:w-32">
              <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                {widgetData.icon && (
                  <DynamicIcon
                    name={widgetData.icon as never}
                    className="size-3.5"
                  />
                )}
                {widgetData.label}
              </div>
              <span className="text-3xl font-semibold tabular-nums">
                {widgetData.value}
              </span>
            </div>
          )}
          {breakdown.length > 0 && (
            <div className="flex-1 space-y-2.5">
              {breakdown.map((item, index) => {
                const percent = total > 0 ? (item.value / total) * 100 : 0
                return (
                  <div key={index}>
                    <div className="flex items-center justify-between gap-2 text-xs">
                      <span className="truncate text-foreground">
                        {item.label}
                      </span>
                      <span className="shrink-0 font-medium tabular-nums text-foreground">
                        {item.value}
                      </span>
                    </div>
                    <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-muted">
                      <div
                        className={`h-full rounded-full ${barColor(item.variant)}`}
                        style={{ width: `${percent}%` }}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
        {widget.caption && (
          <p className="mt-4 text-xs text-muted-foreground">{widget.caption}</p>
        )}
      </CardContent>
    </Card>
  )
}
