import { Link } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { ArrowRight, ChevronRightIcon } from "lucide-react"
import { DynamicIcon } from "lucide-react/dynamic"

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

export const LIST_ITEM_VARIANT_CLASSES: Record<string, string> = {
  default: "text-foreground",
  secondary: "text-muted-foreground",
  success: "text-emerald-600 dark:text-emerald-500",
  warning: "text-amber-600 dark:text-amber-500",
  destructive: "text-destructive",
  info: "text-blue-600 dark:text-blue-500",
}

export function ListItemIcon({
  icon,
  variant,
}: {
  icon?: string
  variant?: string
}) {
  if (!icon) return null
  return (
    <DynamicIcon
      name={icon as never}
      className={`size-4 shrink-0 ${
        LIST_ITEM_VARIANT_CLASSES[variant ?? "default"] ??
        LIST_ITEM_VARIANT_CLASSES.default
      }`}
    />
  )
}

export function List1Skeleton() {
  return (
    <Card className="col-span-1 md:col-span-2">
      <CardHeader>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-1">
            <Skeleton className="h-5 w-32" />
            <Skeleton className="h-4 w-48" />
          </div>
          <Skeleton className="h-7 w-24" />
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-14 w-full rounded-lg" />
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

export function List1Widget<S extends DatabaseSchemas>({
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

  return (
    <Card className="col-span-1 md:col-span-2">
      <CardHeader>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="space-y-1">
            <CardTitle>{widget.name}</CardTitle>
            <CardDescription>{widget.description}</CardDescription>
          </div>
          {widget.url && (
            <Button
              variant="outline"
              size="sm"
              nativeButton={false}
              render={<Link to={widget.url as never} />}
              className="shrink-0"
            >
              View All
              <ArrowRight />
            </Button>
          )}
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          {data.map((row, index) => {
            const content = (
              <>
                <ListItemIcon icon={row.icon} variant={row.variant} />
                <div className="min-w-0 flex-1 space-y-0.5">
                  <p className="truncate text-sm font-medium">{row.title}</p>
                  {row.description && (
                    <p className="truncate text-xs text-muted-foreground">
                      {row.description}
                    </p>
                  )}
                </div>
                {row.link && (
                  <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />
                )}
              </>
            )
            const className =
              "flex items-center gap-3 rounded-lg border p-3" +
              (row.link ? " hover:bg-muted/50 transition-colors" : "")

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
