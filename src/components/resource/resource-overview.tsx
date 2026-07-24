import { Suspense, useMemo } from "react"

import { Link, useNavigate } from "@tanstack/react-router"

import type { ColumnFiltersState } from "@tanstack/react-table"

import {
  ArrowRightIcon,
  ExternalLinkIcon,
  FilterIcon,
  LinkIcon,
} from "lucide-react"

import { ChartSkeleton, ChartWidget } from "#/components/chart/chart-widget"
import { DashboardWidget } from "#/components/dashboard/dashboard-widget"
import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { encodeFilterValue } from "#/lib/data-table"
import type {
  DatabaseSchemas,
  DatabaseTables,
  ResourceLink,
  TableMetadata,
} from "#/lib/database-meta.types"
import {
  getPrimaryViewIcon,
  resolvePrimaryViewTarget,
} from "#/lib/resource-view"
import type { ChartSchema } from "#/lib/supabase/data/chart"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

function isExternalLink(link: ResourceLink) {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(link.url)
}

export function ResourceOverview<S extends DatabaseSchemas>({
  schema,
  resource,
  meta,
  friendlyName,
  widgets,
  charts,
}: {
  schema: S
  resource: DatabaseTables<S>
  meta: TableMetadata
  friendlyName: string
  widgets: DashboardWidgetSchema<S>[]
  charts: ChartSchema<S>[]
}) {
  const navigate = useNavigate()

  const PrimaryViewIcon = useMemo(() => getPrimaryViewIcon(meta), [meta])

  function openPrimaryView() {
    navigate(resolvePrimaryViewTarget(schema, resource, meta))
  }

  function openTableWithFilters(filters: ColumnFiltersState) {
    navigate({
      to: "/$schema/resource/$resource/table",
      params: { schema, resource },
      search: { filters, page: 1 },
    })
  }

  const cardWidgets = widgets.filter((w) => w.widget_type.startsWith("card_"))
  const tableWidgets = widgets.filter((w) => w.widget_type.startsWith("table_"))
  const filterPresets = meta.filter_presets ?? []
  const links = meta.links ?? []

  return (
    <div className="mx-auto w-full max-w-6xl space-y-4 p-4">
      <section className="flex flex-col gap-3 rounded-lg border bg-card p-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-1.5">
          <div className="flex items-center gap-2">
            <DynamicIcon
              iconName={meta.icon}
              className="size-5 shrink-0 text-muted-foreground"
            />
            <h2 className="text-base font-medium">{friendlyName}</h2>
          </div>
          {meta.description && (
            <p className="text-sm text-muted-foreground">{meta.description}</p>
          )}
        </div>
        <Button size="sm" variant="outline" onClick={openPrimaryView}>
          <PrimaryViewIcon className="size-3.5" />
          Open view
        </Button>
      </section>

      {filterPresets.length > 0 && (
        <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-3">
          {filterPresets.map((preset) => (
            <Card
              key={preset.id}
              size="sm"
              className="h-full cursor-pointer transition-colors hover:bg-muted/50"
              onClick={() =>
                openTableWithFilters(
                  preset.filters.map((f) => ({
                    id: f.id,
                    value: encodeFilterValue(f.operator, f.value),
                  }))
                )
              }
            >
              <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0">
                <div className="flex min-w-0 items-center gap-2">
                  {preset.icon ? (
                    <DynamicIcon
                      iconName={preset.icon}
                      className="size-4 shrink-0 text-muted-foreground"
                    />
                  ) : (
                    <FilterIcon className="size-4 shrink-0 text-muted-foreground" />
                  )}
                  <CardTitle className="truncate">{preset.name}</CardTitle>
                </div>
                <ArrowRightIcon className="size-3.5 shrink-0 text-muted-foreground" />
              </CardHeader>
              {preset.description && (
                <CardContent>
                  <CardDescription>{preset.description}</CardDescription>
                </CardContent>
              )}
            </Card>
          ))}
        </div>
      )}

      {links.length > 0 && (
        <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-3">
          {links.map((link) => {
            const external = isExternalLink(link)
            const card = (
              <Card
                size="sm"
                className="h-full transition-colors hover:bg-muted/50"
              >
                <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0">
                  <div className="flex min-w-0 items-center gap-2">
                    {link.icon ? (
                      <DynamicIcon
                        iconName={link.icon}
                        className="size-4 shrink-0 text-muted-foreground"
                      />
                    ) : (
                      <LinkIcon className="size-4 shrink-0 text-muted-foreground" />
                    )}
                    <CardTitle className="truncate">{link.name}</CardTitle>
                  </div>
                  {external ? (
                    <ExternalLinkIcon className="size-3.5 shrink-0 text-muted-foreground" />
                  ) : (
                    <ArrowRightIcon className="size-3.5 shrink-0 text-muted-foreground" />
                  )}
                </CardHeader>
                {link.description && (
                  <CardContent>
                    <CardDescription>{link.description}</CardDescription>
                  </CardContent>
                )}
              </Card>
            )
            return external ? (
              <a
                key={link.id}
                href={link.url}
                target="_blank"
                rel="noreferrer"
                className="block h-full"
              >
                {card}
              </a>
            ) : (
              <Link
                key={link.id}
                to={link.url as never}
                className="block h-full"
              >
                {card}
              </Link>
            )
          })}
        </div>
      )}

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
            .sort((a, b) => a.widget_type.localeCompare(b.widget_type))
            .map((widget) => (
              <DashboardWidget key={widget.view_name} widget={widget} />
            ))}
        </div>
      )}

      {charts.length > 0 && (
        <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-4">
          {charts.map((chart) => (
            <Suspense key={chart.view_name} fallback={<ChartSkeleton />}>
              <ChartWidget chart={chart} />
            </Suspense>
          ))}
        </div>
      )}
    </div>
  )
}
