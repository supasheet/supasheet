import type { LucideIcon } from "lucide-react"
import {
  GanttChartIcon,
  Grid3X3Icon,
  ImageIcon,
  LayoutGridIcon,
  ListIcon,
  ListTreeIcon,
  SquareKanbanIcon,
  TableIcon,
} from "lucide-react"

import type {
  DatabaseSchemas,
  DatabaseTables,
  TableMetadata,
  ViewLayout,
  ViewLayoutType,
} from "#/lib/database-meta.types"

const VIEW_TYPE_ICON: Record<ViewLayoutType, LucideIcon> = {
  kanban: SquareKanbanIcon,
  calendar: Grid3X3Icon,
  gallery: ImageIcon,
  list: ListIcon,
  tree: ListTreeIcon,
  gantt: GanttChartIcon,
}

function resolveMetaViewTarget<S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S>,
  view: ViewLayout
) {
  if (view.type === "kanban") {
    return {
      to: "/$schema/resource/$resource/kanban/$kanbanId" as const,
      params: () => ({ schema, resource, kanbanId: view.id }),
      search: { layout: "board" },
    }
  }
  if (view.type === "calendar") {
    return {
      to: "/$schema/resource/$resource/calendar/$calendarId" as const,
      params: () => ({ schema, resource, calendarId: view.id }),
      search: { view: "month" },
    }
  }
  if (view.type === "gallery") {
    return {
      to: "/$schema/resource/$resource/gallery/$galleryId" as const,
      params: () => ({ schema, resource, galleryId: view.id }),
    }
  }
  if (view.type === "list") {
    return {
      to: "/$schema/resource/$resource/list/$listId" as const,
      params: () => ({ schema, resource, listId: view.id }),
    }
  }
  if (view.type === "tree") {
    return {
      to: "/$schema/resource/$resource/tree/$treeId" as const,
      params: () => ({ schema, resource, treeId: view.id }),
    }
  }
  return {
    to: "/$schema/resource/$resource/gantt/$ganttId" as const,
    params: () => ({ schema, resource, ganttId: view.id }),
    search: { scale: "month" },
  }
}

export function resolvePrimaryViewTarget<S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S>,
  meta: TableMetadata
) {
  const primary = meta.primary_view
  const primaryView = primary
    ? (meta.views ?? []).find((v) => v.id === primary)
    : undefined

  if (primaryView) return resolveMetaViewTarget(schema, resource, primaryView)
  if (primary === "grid") {
    return {
      to: "/$schema/resource/$resource/grid" as const,
      params: { schema, resource },
    }
  }
  return {
    to: "/$schema/resource/$resource/table" as const,
    params: { schema, resource },
  }
}

export function getPrimaryViewIcon(meta: TableMetadata): LucideIcon {
  const primary = meta.primary_view
  const primaryView = primary
    ? (meta.views ?? []).find((v) => v.id === primary)
    : undefined

  if (primaryView) return VIEW_TYPE_ICON[primaryView.type]
  if (primary === "grid") return LayoutGridIcon
  return TableIcon
}

export type AvailableView = {
  id: string
  label: string
  icon: LucideIcon
  target: ReturnType<typeof resolveMetaViewTarget>
  builtIn: boolean
}

export function getAvailableViews<S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S>,
  meta: TableMetadata
): AvailableView[] {
  const builtIn: AvailableView[] = [
    {
      id: "table",
      label: "Table View",
      icon: TableIcon,
      target: {
        to: "/$schema/resource/$resource/table" as const,
        params: { schema, resource },
      },
      builtIn: true,
    },
    {
      id: "grid",
      label: "Grid View",
      icon: LayoutGridIcon,
      target: {
        to: "/$schema/resource/$resource/grid" as const,
        params: { schema, resource },
      },
      builtIn: true,
    },
  ]

  const metaViews: AvailableView[] = (meta.views ?? []).map((view) => ({
    id: view.id,
    label: view.name || view.id,
    icon: VIEW_TYPE_ICON[view.type],
    target: resolveMetaViewTarget(schema, resource, view),
    builtIn: false,
  }))

  return [...builtIn, ...metaViews]
}
