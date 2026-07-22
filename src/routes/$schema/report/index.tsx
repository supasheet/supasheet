import { Link, createFileRoute, useRouter } from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, FileTextIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
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
import { reportsQueryOptions } from "#/lib/supabase/data/report"

export const Route = createFileRoute("/$schema/report/")({
  loader: async ({ context, params }) => {
    const reports = await context.queryClient.ensureQueryData(
      reportsQueryOptions(params.schema)
    )
    return { reports }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Reports | ${formatTitle(params.schema)}`) }],
  }),
  component: RouteComponent,
  pendingComponent: () => {
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Report" }]} />
        <div className="mx-auto grid max-w-6xl grid-cols-1 gap-2.5 p-4 md:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Card key={i}>
              <CardHeader>
                <div className="flex items-center gap-3">
                  <Skeleton className="size-5 rounded-md" />
                  <Skeleton className="h-5 w-32" />
                  <Skeleton className="h-5 w-14 rounded-full" />
                </div>
                <Skeleton className="h-4 w-48" />
              </CardHeader>
            </Card>
          ))}
        </div>
      </div>
    )
  },
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema } = Route.useParams()
    const router = useRouter()
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Report" }]} />
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
})

function RouteComponent() {
  const params = Route.useParams()
  const { reports = [] } = Route.useLoaderData()

  if (reports.length === 0) {
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Report" }]} />
        <div className="flex min-h-[calc(100svh-183px)] items-center justify-center">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileTextIcon />
              </EmptyMedia>
              <EmptyTitle>No Reports Found</EmptyTitle>
              <EmptyDescription>
                There are no reports available for this schema yet.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Report" }]} />
      <div className="mx-auto grid max-w-6xl grid-cols-1 gap-2.5 p-4 md:grid-cols-2">
        {reports.map((report) => (
          <Link
            key={report.view_name}
            to="/$schema/report/$report"
            params={{ schema: params.schema, report: report.view_name }}
          >
            <Card>
              <CardHeader>
                <div className="flex items-center gap-3">
                  <FileTextIcon className="h-5 w-5" />
                  <CardTitle>{report.name}</CardTitle>
                  <Badge variant="secondary">Active</Badge>
                </div>
                {report.description && (
                  <CardDescription>{report.description}</CardDescription>
                )}
              </CardHeader>
              <CardContent>
                <div className="text-sm text-muted-foreground">
                  View: {report.view_name}
                </div>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  )
}
