import { useCallback, useEffect, useState } from "react"

import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { AlignStartHorizontalIcon, AlignStartVerticalIcon } from "lucide-react"
import { toast } from "sonner"

import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import {
  Kanban,
  KanbanBoard,
  KanbanColumn,
  KanbanColumnContent,
  KanbanItem,
  KanbanItemHandle,
  KanbanOverlay,
} from "#/components/reui/kanban"
import type { KanbanCommitMeta } from "#/components/reui/kanban"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { ButtonGroup } from "#/components/ui/button-group"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import type { ResourceSchema } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import type { EnumBadgeMeta } from "#/lib/fields"
import { getPkValue } from "#/lib/fields"
import { updateResourceMutationOptions } from "#/lib/supabase/data/resource"
import { cn } from "#/lib/utils"

export interface KanbanViewData {
  title: string | null
  description: string | null
  badge: string | null
  badgeIcon?: EnumBadgeMeta["icon"]
  badgeVariant?: EnumBadgeMeta["variant"]
  date: string | null
  data: Record<string, unknown>
}

export type KanbanViewReducedData = Record<string, KanbanViewData[]>

export type KanbanBoardMode = "board" | "list"

function seedGroupColumns(
  data: KanbanViewReducedData,
  groupValues: string[]
): KanbanViewReducedData {
  if (groupValues.length === 0) return data

  const seeded: KanbanViewReducedData = {}
  for (const value of groupValues) {
    seeded[value] = data[value] ?? []
  }
  for (const [value, tasks] of Object.entries(data)) {
    if (!(value in seeded)) seeded[value] = tasks
  }
  return seeded
}

export function ResourceKanban({
  data,
  resourceSchema,
  groupBy,
  groupValues = [],
  layout,
}: {
  data: KanbanViewReducedData
  resourceSchema: ResourceSchema
  groupBy: string
  groupValues?: string[]
  layout: KanbanBoardMode
}) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const navigate = useNavigate({
    from: "/$schema/resource/$resource/kanban/$kanbanId",
  })
  const queryClient = useQueryClient()
  const [columns, setColumns] = useState<KanbanViewReducedData>(() =>
    seedGroupColumns(data, groupValues)
  )

  useEffect(() => {
    setColumns(seedGroupColumns(data, groupValues))
  }, [data, groupValues])

  const { mutate: updateResource } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )

  const buildId = useCallback(
    (item: KanbanViewData) => Object.values(item.data).join("/"),
    []
  )

  const handleValueCommit = useCallback(
    (next: KanbanViewReducedData, meta: KanbanCommitMeta<KanbanViewData>) => {
      if (meta.kind !== "item" || meta.activeContainer === meta.overContainer) {
        return
      }
      const item = next[meta.overContainer]?.[meta.overIndex]
      if (!item) return

      const pk = Object.fromEntries(
        primaryKeys.map((pkField) => [pkField.name, item.data[pkField.name]])
      )
      updateResource(
        { pk, data: { [groupBy]: meta.overContainer } },
        {
          onSuccess: () => {
            queryClient.invalidateQueries({
              queryKey: ["supasheet", "resource-data", schema, resource],
            })
          },
          onError: (err) => {
            setColumns(meta.previousValue)
            toast.error(
              err instanceof Error ? err.message : "Failed to update record"
            )
          },
        }
      )
    },
    [primaryKeys, groupBy, updateResource, queryClient, schema, resource]
  )

  function goToLayout(l: KanbanBoardMode) {
    void navigate({
      search: (prev: Record<string, unknown>) => ({
        ...prev,
        layout: l,
      }),
    })
  }

  const hasNoData =
    Object.keys(columns).length === 0 ||
    Object.values(columns).every((tasks) => tasks.length === 0)

  return (
    <div className="flex flex-col gap-2">
      <div className="flex justify-end">
        <ButtonGroup>
          <Button
            size="icon-sm"
            variant={layout === "board" ? "default" : "outline"}
            aria-label="Board layout"
            onClick={() => goToLayout("board")}
          >
            <AlignStartHorizontalIcon />
          </Button>
          <Button
            size="icon-sm"
            variant={layout === "list" ? "default" : "outline"}
            aria-label="List layout"
            onClick={() => goToLayout("list")}
          >
            <AlignStartVerticalIcon />
          </Button>
        </ButtonGroup>
      </div>

      {hasNoData ? (
        <Empty className="min-h-[400px] border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <AlignStartHorizontalIcon />
            </EmptyMedia>
            <EmptyTitle>No items to display</EmptyTitle>
            <EmptyDescription>
              There are no items available in this kanban view.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <Kanban
          value={columns}
          onValueChange={setColumns}
          onValueCommit={handleValueCommit}
          getItemValue={buildId}
        >
          <KanbanBoard
            className={cn(
              "overflow-x-auto",
              layout === "board"
                ? "flex h-[calc(100svh-135px)] flex-row"
                : "flex flex-col"
            )}
          >
            {Object.entries(columns).map(([columnValue, tasks]) => (
              <KanbanColumn
                key={columnValue}
                value={columnValue}
                className={cn(
                  "flex flex-col gap-2 rounded-lg border bg-card p-2.5",
                  layout === "board" && "min-w-sm max-w-2xl"
                )}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-semibold">{columnValue}</span>
                    <Badge
                      variant="secondary"
                      className="pointer-events-none rounded-sm"
                    >
                      {tasks.length}
                    </Badge>
                  </div>
                </div>
                <KanbanColumnContent
                  value={columnValue}
                  className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-0.5"
                >
                  {tasks.map((task) => {
                    const resourceId = getPkValue(task.data, primaryKeys)
                    return (
                      <KanbanItem key={buildId(task)} value={buildId(task)}>
                        <KanbanItemHandle
                          className="block cursor-pointer rounded-lg bg-card p-3 shadow-xs ring-1 ring-foreground/10"
                          onClick={() =>
                            navigate({
                              to: "/$schema/resource/$resource/$resourceId/detail",
                              params: { schema, resource, resourceId },
                            })
                          }
                        >
                          <div className="flex flex-col gap-2">
                            <div className="flex items-center justify-between gap-2">
                              <span className="line-clamp-1 text-sm font-medium">
                                {task.title ?? "Untitled"}
                              </span>
                              {task.badge && (
                                <Badge
                                  variant={task.badgeVariant}
                                  className="pointer-events-none h-5 px-1.5 text-[11px] capitalize"
                                >
                                  <DynamicIcon iconName={task.badgeIcon} />
                                  {task.badge}
                                </Badge>
                              )}
                            </div>
                            <div className="flex items-center justify-between text-xs text-muted-foreground">
                              {task.description && (
                                <span className="line-clamp-1">
                                  {task.description}
                                </span>
                              )}
                              {task.date && (
                                <time className="text-[10px] tabular-nums whitespace-nowrap">
                                  {new Date(task.date).toDateString()}
                                </time>
                              )}
                            </div>
                          </div>
                        </KanbanItemHandle>
                      </KanbanItem>
                    )
                  })}
                </KanbanColumnContent>
              </KanbanColumn>
            ))}
          </KanbanBoard>
          <KanbanOverlay>
            <div className="size-full rounded-md bg-primary/10" />
          </KanbanOverlay>
        </Kanban>
      )}
    </div>
  )
}
