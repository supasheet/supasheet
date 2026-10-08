import { Link, createFileRoute, useRouter } from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, LayoutTemplateIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ApplyTemplateDialog } from "#/components/template/apply-template-dialog"
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
import { templatesQueryOptions } from "#/lib/supabase/data/template"

export const Route = createFileRoute("/$schema/template/")({
  loader: async ({ context, params }) => {
    const templates = await context.queryClient.ensureQueryData(
      templatesQueryOptions(params.schema)
    )
    return { templates }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Templates | ${formatTitle(params.schema)}`) }],
  }),
  component: RouteComponent,
  pendingComponent: () => {
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Template" }]} />
        <div className="mx-auto grid max-w-6xl grid-cols-1 gap-4 p-4 md:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="rounded-xl border bg-card p-6">
              <div className="mb-2 flex items-center gap-3">
                <Skeleton className="size-5 rounded" />
                <Skeleton className="h-5 w-32" />
                <Skeleton className="h-5 w-14 rounded-full" />
              </div>
              <Skeleton className="h-4 w-48" />
            </div>
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
        <DefaultHeader breadcrumbs={[{ title: "Template" }]} />
        <div className="flex min-h-[calc(100svh-183px)] items-center justify-center">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <AlertCircleIcon />
              </EmptyMedia>
              <EmptyTitle>Something went wrong</EmptyTitle>
              <EmptyDescription>
                {(error as Error)?.message ?? "An unexpected error occurred."}
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
  const { templates = [] } = Route.useLoaderData()

  if (templates.length === 0) {
    return (
      <div className="w-full flex-1">
        <DefaultHeader breadcrumbs={[{ title: "Template" }]} />
        <div className="flex min-h-[calc(100svh-183px)] items-center justify-center">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <LayoutTemplateIcon />
              </EmptyMedia>
              <EmptyTitle>No Templates Found</EmptyTitle>
              <EmptyDescription>
                There are no templates available for this schema yet.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </div>
    )
  }

  return (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Template" }]} />
      <div className="mx-auto grid max-w-6xl grid-cols-1 gap-4 p-4 md:grid-cols-2">
        {templates.map((template) => (
          <div key={template.view_name} className="relative">
            <Link
              to="/$schema/template/$template"
              params={{ schema: params.schema, template: template.view_name }}
            >
              <Card>
                <CardHeader>
                  <div className="flex items-center gap-3">
                    <LayoutTemplateIcon className="h-5 w-5" />
                    <CardTitle>{template.name}</CardTitle>
                    {template.target_table && (
                      <Badge variant="secondary">
                        {formatTitle(template.target_table)}
                      </Badge>
                    )}
                  </div>
                  {template.description && (
                    <CardDescription>{template.description}</CardDescription>
                  )}
                </CardHeader>
                <CardContent>
                  <div className="text-sm text-muted-foreground">
                    View: {template.view_name}
                  </div>
                </CardContent>
              </Card>
            </Link>
            <div
              className="absolute right-4 bottom-4"
              onClick={(e) => e.stopPropagation()}
            >
              <ApplyTemplateDialog
                schema={params.schema}
                templateName={template.view_name}
                defaultTargetTable={template.target_table}
                trigger={
                  <Button size="sm" variant="outline">
                    Apply
                  </Button>
                }
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
