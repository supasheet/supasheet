import { Fragment, Suspense, useMemo } from "react"

import { useNavigate } from "@tanstack/react-router"

import type { LucideIcon } from "lucide-react"
import {
  ChevronDownIcon,
  ExternalLinkIcon,
  FileTextIcon,
  FilterIcon,
  LinkIcon,
} from "lucide-react"

import { ChartSkeleton, ChartWidget } from "#/components/chart/chart-widget"
import { DashboardWidget } from "#/components/dashboard/dashboard-widget"
import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { Button } from "#/components/ui/button"
import { ButtonGroup } from "#/components/ui/button-group"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import { getFormMeta } from "#/hooks/use-custom-form"
import type {
  DatabaseSchemas,
  DatabaseTables,
  FilterRule,
  IconName,
  TableMetadata,
} from "#/lib/database-meta.types"
import { rulesToSearch } from "#/lib/filter-presets"
import {
  getAvailableViews,
  getPrimaryViewIcon,
  resolvePrimaryViewTarget,
} from "#/lib/resource-view"
import type { ChartSchema } from "#/lib/supabase/data/chart"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"
import type { ResourceFormRow } from "#/lib/supabase/data/form"

function isExternalHref(href: string) {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(href)
}

const OVERVIEW_CARD_GRID = "grid grid-cols-1 gap-2.5 md:grid-cols-3"

type MenuEntry = {
  key: string
  name: string
  description?: string
  icon?: IconName
  fallbackIcon: LucideIcon
  external?: boolean
  onSelect: () => void
}

function OverviewMenuCard({
  icon: Icon,
  title,
  description,
  triggerLabel,
  emptyMessage,
  entries,
}: {
  icon: LucideIcon
  title: string
  description: string
  triggerLabel: string
  emptyMessage: string
  entries: MenuEntry[]
}) {
  const isEmpty = entries.length === 0

  return (
    <Card size="sm" className="h-full">
      <CardHeader className="flex flex-row items-center gap-2 space-y-0">
        <Icon className="size-4 shrink-0 text-muted-foreground" />
        <CardTitle className="truncate">{title}</CardTitle>
        {!isEmpty && (
          <span className="ml-auto text-xs text-muted-foreground tabular-nums">
            {entries.length}
          </span>
        )}
      </CardHeader>
      <CardContent className="flex flex-1 flex-col justify-between gap-3">
        <CardDescription>{isEmpty ? emptyMessage : description}</CardDescription>
        <DropdownMenu>
          <DropdownMenuTrigger
            disabled={isEmpty}
            render={
              <Button
                variant="outline"
                className="w-full justify-between"
                disabled={isEmpty}
              >
                {triggerLabel}
                <ChevronDownIcon className="size-3.5 opacity-50" />
              </Button>
            }
          />
          <DropdownMenuContent
            align="start"
            className="w-(--anchor-width) min-w-56 rounded-lg"
          >
            <DropdownMenuGroup>
              <DropdownMenuLabel>{title}</DropdownMenuLabel>
              {entries.map((entry) => (
                <DropdownMenuItem key={entry.key} onClick={entry.onSelect}>
                  {entry.icon ? (
                    <DynamicIcon iconName={entry.icon} className="size-3.5" />
                  ) : (
                    <entry.fallbackIcon className="size-3.5" />
                  )}
                  <div className="flex min-w-0 flex-col">
                    <span className="truncate">{entry.name}</span>
                    {entry.description && (
                      <span className="truncate text-xs text-muted-foreground">
                        {entry.description}
                      </span>
                    )}
                  </div>
                  {entry.external && (
                    <ExternalLinkIcon className="ml-auto size-3 text-muted-foreground" />
                  )}
                </DropdownMenuItem>
              ))}
            </DropdownMenuGroup>
          </DropdownMenuContent>
        </DropdownMenu>
      </CardContent>
    </Card>
  )
}

export function ResourceOpenView<S extends DatabaseSchemas>({
  schema,
  resource,
  meta,
}: {
  schema: S
  resource: DatabaseTables<S>
  meta: TableMetadata
}) {
  const navigate = useNavigate()
  const PrimaryViewIcon = useMemo(() => getPrimaryViewIcon(meta), [meta])
  const availableViews = useMemo(
    () => getAvailableViews(schema, resource, meta),
    [schema, resource, meta]
  )

  return (
    <ButtonGroup>
      <Button
        variant="outline"
        onClick={() => navigate(resolvePrimaryViewTarget(schema, resource, meta))}
      >
        <PrimaryViewIcon className="size-3.5" />
        Open view
      </Button>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button variant="outline" className="px-2" aria-label="Views">
              <ChevronDownIcon className="size-3.5" />
            </Button>
          }
        />
        <DropdownMenuContent align="end" className="w-fit rounded-lg">
          <DropdownMenuGroup>
            <DropdownMenuLabel>Views</DropdownMenuLabel>
            {availableViews.map((view, index) => (
              <Fragment key={view.id}>
                {index > 0 &&
                  view.builtIn !== availableViews[index - 1].builtIn && (
                    <DropdownMenuSeparator />
                  )}
                <DropdownMenuItem onClick={() => navigate(view.target)}>
                  <view.icon className="size-3.5" />
                  {view.label}
                </DropdownMenuItem>
              </Fragment>
            ))}
          </DropdownMenuGroup>
        </DropdownMenuContent>
      </DropdownMenu>
    </ButtonGroup>
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

  function openTableWithFilters(rules: FilterRule[]) {
    navigate({
      to: "/$schema/resource/$resource/table",
      params: { schema, resource },
      search: { ...rulesToSearch(rules), page: 1 },
    })
  }

  function openLink(href: string) {
    if (isExternalHref(href)) {
      window.open(href, "_blank", "noreferrer")
      return
    }
    navigate({ to: href as never })
  }

  const cardWidgets = widgets.filter((w) => w.widget_type.startsWith("card_"))
  const tableWidgets = widgets.filter((w) => w.widget_type.startsWith("table_"))

  const presetEntries: MenuEntry[] = (meta.filter_presets ?? []).map(
    (preset) => ({
      key: preset.id,
      name: preset.name,
      description: preset.description,
      icon: preset.icon,
      fallbackIcon: FilterIcon,
      onSelect: () => openTableWithFilters(preset.filters),
    })
  )

  const linkEntries: MenuEntry[] = (meta.links ?? []).map((link) => ({
    key: link.id,
    name: link.name,
    description: link.description,
    icon: link.icon,
    fallbackIcon: LinkIcon,
    external: isExternalHref(link.url),
    onSelect: () => openLink(link.url),
  }))

  const formEntries: MenuEntry[] = forms.map((form) => {
    const formMeta = getFormMeta(form)
    return {
      key: form.name,
      name: formMeta.name,
      description: formMeta.description,
      icon: formMeta.icon,
      fallbackIcon: FileTextIcon,
      onSelect: () =>
        navigate({
          to: `/${schema}/resource/${resource}/form/${form.name}` as never,
        }),
    }
  })

  return (
    <div className="mx-auto w-full max-w-6xl space-y-4 p-4">
      <div className={OVERVIEW_CARD_GRID}>
        <OverviewMenuCard
          icon={FilterIcon}
          title="Filters"
          description={`Jump to ${friendlyName} filtered by a saved preset.`}
          triggerLabel="Choose a filter"
          emptyMessage={`No filter presets are configured for ${friendlyName}.`}
          entries={presetEntries}
        />
        <OverviewMenuCard
          icon={LinkIcon}
          title="Links"
          description={`Reports and shortcuts related to ${friendlyName}.`}
          triggerLabel="Open a link"
          emptyMessage={`No links are configured for ${friendlyName}.`}
          entries={linkEntries}
        />
        <OverviewMenuCard
          icon={FileTextIcon}
          title="Forms"
          description={`Guided forms that create or update ${friendlyName}.`}
          triggerLabel="Start a form"
          emptyMessage={`No custom forms are available for ${friendlyName}.`}
          entries={formEntries}
        />
      </div>

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
