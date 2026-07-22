import { useCallback, useEffect, useState } from "react"

import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import {
  AlignStartHorizontalIcon,
  AlignStartVerticalIcon,
  Eye,
  Trash,
} from "lucide-react"
import { toast } from "sonner"

import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { ButtonGroup } from "#/components/ui/button-group"
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "#/components/ui/context-menu"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import {
  Kanban,
  KanbanBoard,
  KanbanColumn,
  KanbanItem,
  KanbanOverlay,
} from "#/components/ui/kanban"
import { useDeleteConfirm } from "#/hooks/use-delete-confirm"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  DatabaseSchemas,
  DatabaseTables,
  PrimaryKey,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { getPkValue } from "#/lib/fields"
import {
  deleteResourceMutationOptions,
  updateResourceMutationOptions,
} from "#/lib/supabase/data/resource"
import { cn } from "#/lib/utils"

export interface KanbanViewData {
  title: string | null
  description: string | null
  badge: string | null
  date: string | null
  data: Record<string, unknown>
}

export type KanbanViewReducedData = Record<string, KanbanViewData[]>

export type KanbanLayout = "board" | "list"

export function ResourceKanban({
  data,
  resourceSchema,
  groupBy,
  layout,
}: {
  data: KanbanViewReducedData
  resourceSchema: ResourceSchema
  groupBy: string
  layout: KanbanLayout
}) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const isTable = isTableSchema(resourceSchema)

  const navigate = useNavigate({
    from: "/$schema/resource/$resource/kanban/$kanbanId",
  })
  const queryClient = useQueryClient()
  const [columns, setColumns] = useState<KanbanViewReducedData>(data)

  useEffect(() => {
    setColumns(data)
  }, [data])

  const { mutate: updateResource } = useMutation(
    updateResourceMutationOptions(schema, resource)
  )

  const buildId = useCallback(
    (item: KanbanViewData) => Object.values(item.data).join("/"),
    []
  )

  const handleUpdate = useCallback(
    (item: KanbanViewData, _from: string | number, to: string | number) => {
      const pk = Object.fromEntries(
        primaryKeys.map((pkField) => [pkField.name, item.data[pkField.name]])
      )
      updateResource(
        { pk, data: { [groupBy]: to } },
        {
          onSuccess: () => {
            queryClient.invalidateQueries({
              queryKey: ["supasheet", "resource-data", schema, resource],
            })
          },
          onError: (err) => {
            toast.error(
              err instanceof Error ? err.message : "Failed to update record"
            )
          },
        }
      )
    },
    [primaryKeys, groupBy, updateResource, queryClient, schema, resource]
  )

  function goToLayout(l: KanbanLayout) {
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
          onUpdate={handleUpdate}
          orientation={layout === "list" ? "vertical" : "horizontal"}
          getItemValue={buildId}
        >
          <KanbanBoard
            className={cn(
              "overflow-x-auto",
              layout === "board" && "h-[calc(100svh-135px)]"
            )}
          >
            {Object.entries(columns).map(([columnValue, tasks]) => (
              <KanbanColumn
                key={columnValue}
                value={columnValue}
                className={cn(layout === "board" ? "min-w-sm max-w-2xl" : "")}
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
                <div className="flex flex-col gap-2 overflow-y-auto p-0.5">
                  {tasks.map((task) => {
                    const resourceId = getPkValue(task.data, primaryKeys)
                    return (
                      <KanbanContextMenu
                        key={buildId(task)}
                        task={task}
                        schema={schema}
                        resource={resource}
                        resourceId={resourceId}
                        primaryKeys={primaryKeys}
                        isTable={isTable}
                      >
                        <KanbanItem value={buildId(task)} asHandle asChild>
                          <div className="rounded-lg bg-card p-3 shadow-xs ring-1 ring-foreground/10">
                            <div className="flex flex-col gap-2">
                              <div className="flex items-center justify-between gap-2">
                                <span className="line-clamp-1 text-sm font-medium">
                                  {task.title ?? "Untitled"}
                                </span>
                                {task.badge && (
                                  <Badge className="pointer-events-none h-5 px-1.5 text-[11px] capitalize">
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
                          </div>
                        </KanbanItem>
                      </KanbanContextMenu>
                    )
                  })}
                </div>
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

function KanbanContextMenu<S extends DatabaseSchemas>({
  children,
  task,
  schema,
  resource,
  resourceId,
  primaryKeys,
  isTable,
}: {
  children: React.ReactNode
  task: KanbanViewData
  schema: S
  resource: DatabaseTables<S>
  resourceId: string
  primaryKeys: PrimaryKey[]
  isTable: boolean
}) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const canDelete = useHasPermission(`${schema}.${resource}:delete`)
  const { mutateAsync: deleteRow } = useMutation(
    deleteResourceMutationOptions(schema, resource)
  )

  const deleteConfirm = useDeleteConfirm(async (item: KanbanViewData) => {
    const pk = Object.fromEntries(
      primaryKeys.map((pkField) => [pkField.name, item.data[pkField.name]])
    )
    try {
      await deleteRow(pk)
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success("Record deleted")
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to delete record"
      )
    }
  })

  return (
    <>
      <ContextMenu>
        <ContextMenuTrigger>{children}</ContextMenuTrigger>
        <ContextMenuContent className="w-52">
          <ContextMenuItem
            onClick={() =>
              navigate({
                to: "/$schema/resource/$resource/$resourceId/detail",
                params: { schema, resource, resourceId },
              })
            }
          >
            <Eye className="size-4" />
            View details
          </ContextMenuItem>
          {isTable && canDelete && (
            <>
              <ContextMenuSeparator />
              <ContextMenuItem
                variant="destructive"
                onClick={() => deleteConfirm.requestDelete(task)}
              >
                <Trash className="size-4" />
                Delete
              </ContextMenuItem>
            </>
          )}
        </ContextMenuContent>
      </ContextMenu>
      <ConfirmDeleteDialog
        open={deleteConfirm.open}
        onOpenChange={(open) => !open && deleteConfirm.cancel()}
        onConfirm={deleteConfirm.confirm}
        title="Delete record?"
        pending={deleteConfirm.pending}
      />
    </>
  )
}
