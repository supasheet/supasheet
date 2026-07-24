import type { LucideIcon } from "lucide-react"
import {
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
  ViewLayoutType,
} from "#/lib/database-meta.types"

const VIEW_TYPE_ICON: Record<ViewLayoutType, LucideIcon> = {
  kanban: SquareKanbanIcon,
  calendar: Grid3X3Icon,
  gallery: ImageIcon,
  list: ListIcon,
  tree: ListTreeIcon,
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

  if (primaryView?.type === "kanban") {
    return {
      to: "/$schema/resource/$resource/kanban/$kanbanId" as const,
      params: () => ({ schema, resource, kanbanId: primaryView.id }),
      search: { layout: "board" },
    }
  }
  if (primaryView?.type === "calendar") {
    return {
      to: "/$schema/resource/$resource/calendar/$calendarId" as const,
      params: () => ({ schema, resource, calendarId: primaryView.id }),
      search: { view: "month" },
    }
  }
  if (primaryView?.type === "gallery") {
    return {
      to: "/$schema/resource/$resource/gallery/$galleryId" as const,
      params: () => ({ schema, resource, galleryId: primaryView.id }),
    }
  }
  if (primaryView?.type === "list") {
    return {
      to: "/$schema/resource/$resource/list/$listId" as const,
      params: () => ({ schema, resource, listId: primaryView.id }),
    }
  }
  if (primaryView?.type === "tree") {
    return {
      to: "/$schema/resource/$resource/tree/$treeId" as const,
      params: () => ({ schema, resource, treeId: primaryView.id }),
    }
  }
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
