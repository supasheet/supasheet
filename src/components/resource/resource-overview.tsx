import { Suspense, useMemo } from "react"

import { Link, useNavigate } from "@tanstack/react-router"

import type { ColumnFiltersState } from "@tanstack/react-table"

import type { LucideIcon } from "lucide-react"
import {
  ArrowRightIcon,
  ExternalLinkIcon,
  FileTextIcon,
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
import { getFormMeta } from "#/hooks/use-custom-form"
import { encodeFilterValue } from "#/lib/data-table"
import type {
  DatabaseSchemas,
  DatabaseTables,
  IconName,
  TableMetadata,
} from "#/lib/database-meta.types"
import {
  getPrimaryViewIcon,
  resolvePrimaryViewTarget,
} from "#/lib/resource-view"
import type { ChartSchema } from "#/lib/supabase/data/chart"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"
import type { ResourceFormRow } from "#/lib/supabase/data/form"

function isExternalHref(href: string) {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(href)
}

function getCardDescription(
  name: string,
  description: string | undefined,
  resourceName: string
) {
  return description ?? `${name} for ${resourceName}`
}

const OVERVIEW_CARD_GRID =
  "grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-3"

function OverviewCard({
  icon,
  fallbackIcon: FallbackIcon,
  name,
  description,
  href,
  onClick,
}: {
  icon?: IconName
  fallbackIcon: LucideIcon
  name: string
  description?: string
  href?: string
  onClick?: () => void
}) {
  const external = href ? isExternalHref(href) : false
  const TrailingIcon = href
    ? external
      ? ExternalLinkIcon
      : ArrowRightIcon
    : ArrowRightIcon

  const card = (
    <Card
      size="sm"
      className={
        "h-full transition-colors hover:bg-muted/50" +
        (onClick || href ? " cursor-pointer" : "")
      }
      onClick={onClick}
    >
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0">
        <div className="flex min-w-0 items-center gap-2">
          {icon ? (
            <DynamicIcon
              iconName={icon}
              className="size-4 shrink-0 text-muted-foreground"
            />
          ) : (
            <FallbackIcon className="size-4 shrink-0 text-muted-foreground" />
          )}
          <CardTitle className="truncate">{name}</CardTitle>
        </div>
        <TrailingIcon className="size-3.5 shrink-0 text-muted-foreground" />
      </CardHeader>
      {description && (
        <CardContent>
          <CardDescription>{description}</CardDescription>
        </CardContent>
      )}
    </Card>
  )

  if (!href) return card

  return external ? (
    <a href={href} target="_blank" rel="noreferrer" className="block h-full">
      {card}
    </a>
  ) : (
    <Link to={href as never} className="block h-full">
      {card}
    </Link>
  )
}

export function ResourceOverview<S extends DatabaseSchemas>({
  schema,
  resource,
  meta,
  friendlyName,
  widgets,
  charts,
  forms,
}: {
  schema: S
  resource: DatabaseTables<S>
  meta: TableMetadata
  friendlyName: string
  widgets: DashboardWidgetSchema<S>[]
  charts: ChartSchema<S>[]
  forms: ResourceFormRow<S>[]
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

  const presetCards = filterPresets.map((preset) => (
    <OverviewCard
      key={`preset-${preset.id}`}
      icon={preset.icon}
      fallbackIcon={FilterIcon}
      name={preset.name}
      description={getCardDescription(
        preset.name,
        preset.description,
        friendlyName
      )}
      onClick={() =>
        openTableWithFilters(
          preset.filters.map((f) => ({
            id: f.id,
            value: encodeFilterValue(f.operator, f.value),
          }))
        )
      }
    />
  ))

  const linkCards = links.map((link) => (
    <OverviewCard
      key={`link-${link.id}`}
      icon={link.icon}
      fallbackIcon={LinkIcon}
      name={link.name}
      description={getCardDescription(
        link.name,
        link.description,
        friendlyName
      )}
      href={link.url}
    />
  ))

  const formCards = forms.map((form) => {
    const formMeta = getFormMeta(form)
    return (
      <OverviewCard
        key={`form-${form.name}`}
        icon={formMeta.icon}
        fallbackIcon={FileTextIcon}
        name={formMeta.name}
        description={getCardDescription(
          formMeta.name,
          formMeta.description,
          friendlyName
        )}
        href={`/${schema}/resource/${resource}/form/${form.name}`}
      />
    )
  })

  const overviewCards = [...presetCards, ...linkCards, ...formCards]

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

      {overviewCards.length > 0 && (
        <div className={OVERVIEW_CARD_GRID}>{overviewCards}</div>
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
