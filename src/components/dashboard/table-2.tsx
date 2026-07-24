import { Link, useNavigate } from "@tanstack/react-router"

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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import type { DatabaseSchemas } from "#/lib/database-meta.types"
import { widgetDataQueryOptions } from "#/lib/supabase/data/dashboard"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

export function Table2Skeleton() {
  return (
    <Card className="col-span-1 md:col-span-2 lg:col-span-4">
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
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

export function Table2Widget<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  const { data } = useSuspenseQuery(
    widgetDataQueryOptions(widget.schema, widget.view_name)
  )
  const navigate = useNavigate()

  if (!data || data.length === 0) {
    return (
      <Card className="col-span-1 md:col-span-2 lg:col-span-4">
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

  const columns = Object.keys(data[0]).filter((column) => column !== "link")
  const rows = data

  return (
    <Card className="col-span-1 md:col-span-2 lg:col-span-4">
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
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                {columns.map((column) => (
                  <TableHead key={column} className="font-medium">
                    {column.charAt(0).toUpperCase() +
                      column.slice(1).replace(/_/g, " ")}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row, index) => (
                <TableRow
                  key={index}
                  onClick={
                    row.link
                      ? () => navigate({ to: row.link as never })
                      : undefined
                  }
                  className={row.link ? "cursor-pointer" : undefined}
                >
                  {columns.map((column) => (
                    <TableCell key={column}>{row[column] || "-"}</TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
        {widget.caption && (
          <p className="mt-2 text-xs text-muted-foreground">{widget.caption}</p>
        )}
      </CardContent>
    </Card>
  )
}
