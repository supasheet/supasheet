import { Link } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { ArrowRight } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Empty, EmptyHeader, EmptyTitle } from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { widgetDataQueryOptions } from "#/lib/supabase/data/dashboard"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

import { ActorAvatar } from "./list-3"

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

export function List4Skeleton() {
  return (
    <Card className="col-span-1 md:col-span-2">
      <CardHeader>
        <div className="space-y-1">
          <Skeleton className="h-5 w-32" />
          <Skeleton className="h-4 w-48" />
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex items-center gap-3">
              <Skeleton className="size-8 shrink-0 rounded-full" />
              <Skeleton className="h-8 flex-1" />
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

export function List4Widget<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )

  if (!data || data.length === 0) {
    return (
      <Card className="col-span-1 md:col-span-2">
        <CardHeader>
          <CardTitle>{widget.name}</CardTitle>
          <CardDescription>{widget.description}</CardDescription>
        </CardHeader>
        <CardContent>
          <Empty>
            <EmptyHeader>
              <EmptyTitle>No data to display</EmptyTitle>
            </EmptyHeader>
          </Empty>
        </CardContent>
      </Card>
    )
  }

  const rows = data
  const max = Math.max(...rows.map((row) => Number(row.value) || 0), 1)

  return (
    <Card className="col-span-1 md:col-span-2">
      <CardHeader>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-1">
            <CardTitle>{widget.name}</CardTitle>
            <CardDescription>{widget.description}</CardDescription>
          </div>
          {widget.link && (
            <Button
              variant="outline"
              size="sm"
              nativeButton={false}
              render={<Link to={widget.link as never} />}
              className="shrink-0"
            >
              View All
              <ArrowRight />
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-3">
          {rows.map((row, index) => {
            const percent = ((Number(row.value) || 0) / max) * 100
            const content = (
              <>
                <ActorAvatar name={row.name} />
                <div className="min-w-0 flex-1 space-y-1.5">
                  <div className="flex items-center justify-between gap-2">
                    <p className="truncate text-sm font-medium">{row.name}</p>
                    <span className="shrink-0 text-sm font-semibold tabular-nums">
                      {row.value}
                    </span>
                  </div>
                  {row.label !== undefined && row.label !== null && (
                    <p className="truncate text-xs text-muted-foreground">
                      {row.label}
                    </p>
                  )}
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
                    <div
                      className={`h-full rounded-full ${barColor(row.variant)}`}
                      style={{ width: `${percent}%` }}
                    />
                  </div>
                </div>
              </>
            )
            const className =
              "flex items-center gap-3" +
              (row.link
                ? " -mx-2 rounded-lg px-2 py-1.5 transition-colors hover:bg-muted/50"
                : "")

            return row.link ? (
              <Link key={index} to={row.link as never} className={className}>
                {content}
              </Link>
            ) : (
              <div key={index} className={className}>
                {content}
              </div>
            )
          })}
        </div>
        {widget.caption && (
          <p className="mt-2 text-xs text-muted-foreground">{widget.caption}</p>
        )}
      </CardContent>
    </Card>
  )
}
