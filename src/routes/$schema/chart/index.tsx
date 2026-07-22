import { Suspense } from "react"

import { createFileRoute, useRouter } from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, BarChartIcon } from "lucide-react"

import { ChartSkeleton, ChartWidget } from "#/components/chart/chart-widget"
import { DefaultHeader } from "#/components/layouts/default-header"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { chartsQueryOptions } from "#/lib/supabase/data/chart"

export const Route = createFileRoute("/$schema/chart/")({
  loader: async ({ context, params }) => {
    const charts = await context.queryClient.ensureQueryData(
      chartsQueryOptions(params.schema)
    )
    return { charts }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Charts | ${formatTitle(params.schema)}`) }],
  }),
  pendingComponent: () => (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Chart" }]} />
      <div className="mx-auto grid max-w-6xl gap-2.5 p-4 md:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <ChartSkeleton key={i} />
        ))}
      </div>
    </div>
  ),
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema } = Route.useParams()
    const router = useRouter()
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Chart" }]} />
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
  const { charts = [] } = Route.useLoaderData()

  if (charts.length === 0) {
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Chart" }]} />
        <div className="flex min-h-[calc(100svh-183px)] items-center justify-center">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <BarChartIcon />
              </EmptyMedia>
              <EmptyTitle>No Charts Found</EmptyTitle>
              <EmptyDescription>
                There are no charts available for this schema yet.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Chart" }]} />
      <div className="mx-auto grid max-w-6xl gap-2.5 p-4 md:grid-cols-2 lg:grid-cols-4">
        {charts.map((chart) => (
          <Suspense key={chart.view_name} fallback={<ChartSkeleton />}>
            <ChartWidget chart={chart} />
          </Suspense>
        ))}
      </div>
    </div>
  )
}
