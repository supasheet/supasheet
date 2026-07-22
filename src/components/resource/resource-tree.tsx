import { useMemo, useState } from "react"

import {
  ArrowUpRightIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  ListTreeIcon,
} from "lucide-react"

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

  // Group rows by their parent value. Null parent → roots.
  // O(N) single pass; mutable Map operations only.
  const childrenByParent = useMemo(() => {
    const map = new Map<string, Row[]>()
    if (!pkColumn) return map
    for (const row of rows) {
      const parentVal = row[parentColumn]
      const key =
        parentVal === null || parentVal === undefined
          ? ROOT_KEY
          : String(parentVal)
      const bucket = map.get(key)
      if (bucket) bucket.push(row)
      else map.set(key, [row])
    }
    return map
  }, [rows, pkColumn, parentColumn])

  const roots = childrenByParent.get(ROOT_KEY) ?? []

  const [expandedIds, setExpandedIds] = useState<Set<string>>(
    () => new Set(roots.map((r) => String(r[pkColumn ?? ""])))
  )

  const toggle = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

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

  if (rows.length === 0 || roots.length === 0) {
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
    <div
      className="flex flex-col overflow-hidden rounded-md border bg-card"
      role="tree"
    >
      {roots.map((row) => (
        <TreeRow
          key={String(row[pkColumn])}
          row={row}
          depth={0}
          pkColumn={pkColumn}
          childrenByParent={childrenByParent}
          expandedIds={expandedIds}
          onToggle={toggle}
          treeView={treeView}
          onSelect={onSelect}
        />
      ))}
    </div>
  )
}

interface TreeRowProps {
  row: Row
  depth: number
  pkColumn: string
  childrenByParent: Map<string, Row[]>
  expandedIds: Set<string>
  onToggle: (id: string) => void
  treeView: TreeLayout
  onSelect?: (row: Row) => void
}

function TreeRow({
  row,
  depth,
  pkColumn,
  childrenByParent,
  expandedIds,
  onToggle,
  treeView,
  onSelect,
}: TreeRowProps) {
  const id = String(row[pkColumn])
  const children = childrenByParent.get(id) ?? []
  const hasChildren = children.length > 0
  const isExpanded = expandedIds.has(id)

  const titleValue = row[treeView.title]
  const secondaryValue = treeView.secondary ? row[treeView.secondary] : null
  const hasSecondary =
    secondaryValue !== null &&
    secondaryValue !== undefined &&
    secondaryValue !== ""

  return (
    <div role="treeitem" aria-expanded={hasChildren ? isExpanded : undefined}>
      <div
        className="group flex items-center gap-2 rounded-sm px-2 py-1.5 text-sm transition-colors hover:bg-accent"
        style={{ paddingLeft: `${depth * 20 + 8}px` }}
      >
        {hasChildren ? (
          <button
            type="button"
            onClick={() => onToggle(id)}
            aria-label={isExpanded ? "Collapse" : "Expand"}
            className="inline-flex size-4 shrink-0 items-center justify-center text-muted-foreground hover:text-foreground"
          >
            {isExpanded ? (
              <ChevronDownIcon className="size-4" />
            ) : (
              <ChevronRightIcon className="size-4" />
            )}
          </button>
        ) : (
          <span className="inline-block size-4 shrink-0" />
        )}

        <span className="flex-1 truncate">
          {titleValue == null ? "Untitled" : String(titleValue)}
        </span>

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
      </div>

      {hasChildren && isExpanded && (
        <div role="group">
          {children.map((child) => (
            <TreeRow
              key={String(child[pkColumn])}
              row={child}
              depth={depth + 1}
              pkColumn={pkColumn}
              childrenByParent={childrenByParent}
              expandedIds={expandedIds}
              onToggle={onToggle}
              treeView={treeView}
              onSelect={onSelect}
            />
          ))}
        </div>
      )}
    </div>
  )
}
