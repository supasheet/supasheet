import { Link, createFileRoute } from "@tanstack/react-router"

import { useQuery } from "@tanstack/react-query"

import {
  ChartBarIcon,
  DatabaseIcon,
  FileChartColumnIcon,
  HomeIcon,
  LayoutTemplateIcon,
} from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceCardGrid } from "#/components/resource/resource-grid"
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import {
  navItemsQueryOptions,
  resourcesQueryOptions,
} from "#/lib/supabase/data/resource"

export const Route = createFileRoute("/$schema/")({
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`${formatTitle(params.schema)}`) }],
  }),
  component: RouteComponent,
})

const quickLinks = [
  {
    title: "Dashboard",
    description: "Overview widgets and key metrics",
    icon: <HomeIcon className="size-5" />,
    url: "dashboard" as const,
    type: "dashboard_widget",
  },
  {
    title: "Charts",
    description: "Visualize your data with charts",
    icon: <ChartBarIcon className="size-5" />,
    url: "chart" as const,
    type: "chart",
  },
  {
    title: "Reports",
    description: "Tabular reports from database views",
    icon: <FileChartColumnIcon className="size-5" />,
    url: "report" as const,
    type: "report",
  },
  {
    title: "Templates",
    description: "Bulk-insert rows from template views",
    icon: <LayoutTemplateIcon className="size-5" />,
    url: "template" as const,
    type: "template",
  },
]

function RouteComponent() {
  const params = Route.useParams()
  const { data: resources = [], isPending } = useQuery(
    resourcesQueryOptions(params.schema)
  )
  const { data: navItemGroups = [], isPending: navPending } = useQuery(
    navItemsQueryOptions(params.schema)
  )

  const tables = resources.filter((r) => r.type === "table")
  const views = resources.filter((r) => r.type === "view")
  const activeTypes = new Set(
    navItemGroups.filter((g) => g.count > 0).map((g) => g.type)
  )
  const visibleLinks = quickLinks.filter((l) => activeTypes.has(l.type))

  return (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: formatTitle(params.schema) }]} />
      <div className="mx-auto max-w-6xl space-y-8 p-6">
        {/* Schema title */}
        <div className="flex items-center gap-3">
          <DatabaseIcon className="size-6 text-muted-foreground" />
          <div>
            <h1 className="text-xl font-semibold tracking-tight">
              {formatTitle(params.schema)}
            </h1>
            <p className="text-sm text-muted-foreground">
              {isPending
                ? "Loading schema…"
                : `${tables.length} table${tables.length !== 1 ? "s" : ""}, ${views.length} view${views.length !== 1 ? "s" : ""}`}
            </p>
          </div>
        </div>

        {/* Quick links */}
        {navPending ? (
          <section>
            <h2 className="mb-3 text-xs font-medium tracking-wide text-muted-foreground uppercase">
              Sections
            </h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <Card key={i}>
                  <CardHeader>
                    <div className="flex items-center gap-3">
                      <Skeleton className="size-5 rounded-md" />
                      <div className="flex-1 space-y-2">
                        <Skeleton className="h-4 w-24" />
                        <Skeleton className="h-3 w-40" />
                      </div>
                    </div>
                  </CardHeader>
                </Card>
              ))}
            </div>
          </section>
        ) : visibleLinks.length > 0 ? (
          <section>
            <h2 className="mb-3 text-xs font-medium tracking-wide text-muted-foreground uppercase">
              Sections
            </h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              {visibleLinks.map((link) => (
                <Link
                  key={link.title}
                  to={`/$schema/${link.url}`}
                  params={{ schema: params.schema }}
                >
                  <Card className="transition-colors hover:bg-accent/50">
                    <CardHeader>
                      <div className="flex items-center gap-3">
                        <span className="text-muted-foreground">
                          {link.icon}
                        </span>
                        <div>
                          <CardTitle className="text-sm">
                            {link.title}
                          </CardTitle>
                          <CardDescription className="mt-0.5 text-xs">
                            {link.description}
                          </CardDescription>
                        </div>
                      </div>
                    </CardHeader>
                  </Card>
                </Link>
              ))}
            </div>
          </section>
        ) : null}

        {/* Resources */}
        <section>
          <h2 className="mb-3 text-xs font-medium tracking-wide text-muted-foreground uppercase">
            Resources
          </h2>
          {isPending ? (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {Array.from({ length: 6 }).map((_, i) => (
                <Card key={i}>
                  <CardHeader>
                    <div className="flex items-center gap-2">
                      <Skeleton className="size-4 rounded-md" />
                      <Skeleton className="h-4 w-28" />
                      <Skeleton className="ml-auto h-5 w-12 rounded-full" />
                    </div>
                  </CardHeader>
                </Card>
              ))}
            </div>
          ) : resources.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No tables or views found in this schema.
            </p>
          ) : (
            <ResourceCardGrid resources={resources} />
          )}
        </section>
      </div>
    </div>
  )
}
