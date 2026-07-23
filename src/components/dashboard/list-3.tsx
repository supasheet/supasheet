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

export function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .map((part) => part[0])
    .join("")
    .toUpperCase()
    .slice(0, 2)
}

export function ActorAvatar({ name }: { name: string }) {
  return (
    <div className="flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-medium text-muted-foreground">
      {initials(name) || "?"}
    </div>
  )
}

export function List3Skeleton() {
  return (
    <Card className="col-span-1 md:col-span-2">
      <CardHeader>
        <div className="space-y-1">
          <Skeleton className="h-5 w-32" />
          <Skeleton className="h-4 w-48" />
        </div>
      </CardHeader>
      <CardContent>
        <div className="divide-y">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="flex items-center gap-3 py-3">
              <Skeleton className="size-8 shrink-0 rounded-full" />
              <Skeleton className="h-4 flex-1" />
              <Skeleton className="h-4 w-16 shrink-0" />
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

export function List3Widget<S extends DatabaseSchemas>({
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
              <EmptyTitle>No recent activity</EmptyTitle>
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
        <div className="divide-y">
          {data.map((row, index) => {
            const content = (
              <>
                <ActorAvatar name={row.actor} />
                <p className="min-w-0 flex-1 truncate text-sm">
                  <span className="font-medium text-foreground">
                    {row.actor}
                  </span>{" "}
                  <span className="text-muted-foreground">{row.action}</span>{" "}
                  <span className="font-medium text-foreground">
                    {row.entity}
                  </span>
                </p>
                {row.date !== undefined && row.date !== null && (
                  <span className="shrink-0 text-xs whitespace-nowrap text-muted-foreground">
                    {row.date}
                  </span>
                )}
              </>
            )
            const className =
              "flex items-center gap-3 py-3" +
              (row.link
                ? " -mx-2 rounded-none px-2 transition-colors hover:bg-muted/50"
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
