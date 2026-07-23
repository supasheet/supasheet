import { createFileRoute, useRouter } from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, LayoutDashboardIcon } from "lucide-react"

import { DashboardWidget } from "#/components/dashboard/dashboard-widget"
import { DefaultHeader } from "#/components/layouts/default-header"
import { Button } from "#/components/ui/button"
import { Card, CardContent, CardHeader } from "#/components/ui/card"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { dashboardWidgetsQueryOptions } from "#/lib/supabase/data/dashboard"

const TABLE_WIDGET_ORDER = [
  "list_1",
  "list_3",
  "list_4",
  "table_1",
  "list_2",
  "table_2",
]

export const Route = createFileRoute("/$schema/dashboard/")({
  loader: async ({ context, params }) => {
    const widgets = await context.queryClient.ensureQueryData(
      dashboardWidgetsQueryOptions(params.schema)
    )
    return { widgets }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Dashboard | ${formatTitle(params.schema)}`) }],
  }),
  pendingComponent: () => (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Dashboard" }]} />
      <div className="mx-auto grid max-w-6xl grid-cols-1 gap-2.5 p-4 md:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Card key={i}>
            <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2">
              <div className="space-y-1">
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-3 w-32" />
              </div>
              <Skeleton className="h-4 w-4 rounded-md" />
            </CardHeader>
            <CardContent>
              <Skeleton className="mb-1 h-8 w-20" />
              <Skeleton className="h-3 w-28" />
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  ),
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema } = Route.useParams()
    const router = useRouter()
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Dashboard" }]} />
        <div className="flex min-h-[calc(100svh-183px)] items-center justify-center">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <AlertCircleIcon />
              </EmptyMedia>
              <EmptyTitle>Something went wrong</EmptyTitle>
              <EmptyDescription>
                {error?.message ?? "An unexpected error occurred."}
              </EmptyDescription>
            </EmptyHeader>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() => router.navigate({ to: `/${schema}` })}
              >
                Go Back
              </Button>
            </div>
          </Empty>
        </div>
      </div>
    )
  },
  component: RouteComponent,
})

function RouteComponent() {
  const { widgets = [] } = Route.useLoaderData()

  if (widgets.length === 0) {
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Dashboard" }]} />
        <div className="flex min-h-[calc(100svh-183px)] items-center justify-center">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <LayoutDashboardIcon />
              </EmptyMedia>
              <EmptyTitle>No Widgets Found</EmptyTitle>
              <EmptyDescription>
                There are no dashboard widgets available for this schema yet.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </div>
    )
  }

  const cardWidgets = widgets.filter((w) => w.widget_type.startsWith("card_"))
  const tableWidgets = widgets.filter(
    (w) =>
      w.widget_type.startsWith("table_") || w.widget_type.startsWith("list_")
  )

  return (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Dashboard" }]} />
      <div className="mx-auto max-w-6xl space-y-2.5 p-4">
        {cardWidgets.length > 0 && (
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
            {cardWidgets.map((widget) => (
              <DashboardWidget key={widget.view_name} widget={widget} />
            ))}
          </div>
        )}
        {tableWidgets.length > 0 && (
          <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
            {tableWidgets
              .slice()
              .sort(
                (a, b) =>
                  TABLE_WIDGET_ORDER.indexOf(a.widget_type) -
                  TABLE_WIDGET_ORDER.indexOf(b.widget_type)
              )
              .map((widget) => (
                <DashboardWidget key={widget.view_name} widget={widget} />
              ))}
          </div>
        )}
      </div>
    </div>
  )
}
