import { useMemo } from "react"

import { hotkeysCoreFeature, syncDataLoaderFeature } from "@headless-tree/core"
import { useTree } from "@headless-tree/react"
import { ArrowUpRightIcon, ListTreeIcon } from "lucide-react"

import { Tree, TreeItem, TreeItemLabel } from "#/components/reui/tree"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import type { ResourceSchema, TreeLayout } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { cn } from "#/lib/utils"

type Row = Record<string, unknown>

interface ResourceTreeProps {
  rows: Row[]
  resourceSchema: ResourceSchema
  treeView: TreeLayout
  onSelect?: (row: Row) => void
}

const ROOT_KEY = "__root__"
const indent = 20

export function ResourceTree({
  rows,
  resourceSchema,
  treeView,
  onSelect,
}: ResourceTreeProps) {
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const pkColumn = primaryKeys[0]?.name
  const parentColumn = treeView.parent

  // Group row ids by their parent id. Null/undefined parent → synthetic root.
  // O(N) single pass; mutable Map operations only.
  const childrenByParent = useMemo(() => {
    const map = new Map<string, string[]>()
    if (!pkColumn) return map
    for (const row of rows) {
      const id = String(row[pkColumn])
      const parentVal = row[parentColumn]
      const key =
        parentVal === null || parentVal === undefined
          ? ROOT_KEY
          : String(parentVal)
      const bucket = map.get(key)
      if (bucket) bucket.push(id)
      else map.set(key, [id])
    }
    return map
  }, [rows, pkColumn, parentColumn])

  const itemsById = useMemo(() => {
    const map = new Map<string, Row>()
    if (!pkColumn) return map
    for (const row of rows) {
      map.set(String(row[pkColumn]), row)
    }
    return map
  }, [rows, pkColumn])

  const rootIds = childrenByParent.get(ROOT_KEY) ?? []

  const tree = useTree<string>({
    initialState: {
      expandedItems: [ROOT_KEY, ...rootIds],
    },
    indent,
    rootItemId: ROOT_KEY,
    getItemName: (item) => {
      const id = item.getId()
      const row = itemsById.get(id)
      const titleValue = row?.[treeView.title]
      return titleValue == null ? "Untitled" : String(titleValue)
    },
    isItemFolder: (item) => (childrenByParent.get(item.getId())?.length ?? 0) > 0,
    dataLoader: {
      getItem: (itemId) => itemId,
      getChildren: (itemId) => childrenByParent.get(itemId) ?? [],
    },
    features: [syncDataLoaderFeature, hotkeysCoreFeature],
  })

  if (!pkColumn) {
    return (
      <Empty className="min-h-[400px] border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ListTreeIcon />
          </EmptyMedia>
          <EmptyTitle>Tree view requires a primary key</EmptyTitle>
          <EmptyDescription>
            This resource has no primary key column.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }

  if (rows.length === 0 || rootIds.length === 0) {
    return (
      <Empty className="min-h-[400px] border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <ListTreeIcon />
          </EmptyMedia>
          <EmptyTitle>No items to display</EmptyTitle>
          <EmptyDescription>
            There are no records to render as a tree.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }

  return (
    <Tree
      indent={indent}
      tree={tree}
      className="rounded-md border bg-card p-1"
    >
      {tree.getItems().map((item) => {
        const id = item.getId()
        if (id === ROOT_KEY) return null

        const row = itemsById.get(id)
        if (!row) return null

        const secondaryValue = treeView.secondary
          ? row[treeView.secondary]
          : null
        const hasSecondary =
          secondaryValue !== null &&
          secondaryValue !== undefined &&
          secondaryValue !== ""

        return (
          <TreeItem key={id} item={item} render={<div />}>
            <TreeItemLabel className="group">
              <span className="flex-1 truncate">{item.getItemName()}</span>

              {hasSecondary && (
                <span className="shrink-0 text-xs text-muted-foreground">
                  {String(secondaryValue)}
                </span>
              )}

              {onSelect && (
                <button
                  type="button"
                  aria-label="Open details"
                  title="Open details"
                  className={cn(
                    "inline-flex size-6 shrink-0 items-center justify-center rounded-sm text-muted-foreground opacity-0 transition-opacity",
                    "hover:bg-accent-foreground/10 hover:text-foreground",
                    "group-hover:opacity-100 focus-visible:opacity-100",
                    "focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                  )}
                  onClick={(e) => {
                    e.stopPropagation()
                    e.preventDefault()
                    onSelect(row)
                  }}
                >
                  <ArrowUpRightIcon className="size-3.5" />
                </button>
              )}
            </TreeItemLabel>
          </TreeItem>
        )
      })}
    </Tree>
  )
}
