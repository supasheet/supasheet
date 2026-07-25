import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { format } from "date-fns"
import { CheckIcon, Eye, HistoryIcon, Trash } from "lucide-react"
import { toast } from "sonner"

import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
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
  Timeline,
  TimelineContent,
  TimelineDate,
  TimelineHeader,
  TimelineIndicator,
  TimelineItem,
  TimelineSeparator,
  TimelineTitle,
} from "#/components/ui/timeline"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import { useInlineFormFlag } from "#/hooks/use-inline-form-flag"
import { useHasPermission } from "#/hooks/use-permissions"
import { useSheetHref } from "#/hooks/use-sheet-href"
import type {
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  PrimaryKey,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { getPkValue } from "#/lib/fields"
import { deleteResourceMutationOptions } from "#/lib/supabase/data/resource"

export interface TimelineViewData {
  title: string | null
  date: string | null
  description: string | null
  badge: string | null
  data: Record<string, unknown>
}

interface ResourceTimelineProps {
  data: TimelineViewData[]
  resourceSchema: ResourceSchema
}

export function ResourceTimeline({
  data,
  resourceSchema,
}: ResourceTimelineProps) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const isTable = isTableSchema(resourceSchema)

  const now = Date.now()
  const pastCount = data.filter(
    (item) => item.date && new Date(item.date).getTime() <= now
  ).length

  if (data.length === 0) {
    return (
      <Empty className="min-h-[400px] border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <HistoryIcon />
          </EmptyMedia>
          <EmptyTitle>No items to display</EmptyTitle>
          <EmptyDescription>
            There are no records with a valid date to plot on this timeline.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }

  return (
    <Timeline defaultValue={pastCount} className="w-full max-w-md p-2">
      {data.map((item, index) => {
        const resourceId = getPkValue(item.data, primaryKeys)
        return (
          <TimelineItem
            key={resourceId || index}
            step={index + 1}
            className="group-data-[orientation=vertical]/timeline:ms-10"
          >
            <TimelineContextMenu
              item={item}
              schema={schema}
              resource={resource}
              resourceId={resourceId}
              primaryKeys={primaryKeys}
              isTable={isTable}
            >
              <TimelineHeader>
                <TimelineSeparator className="group-data-[orientation=vertical]/timeline:-left-7 group-data-[orientation=vertical]/timeline:h-[calc(100%-1.5rem-0.25rem)] group-data-[orientation=vertical]/timeline:translate-y-6.5" />
                {item.date && (
                  <TimelineDate>{format(new Date(item.date), "PPp")}</TimelineDate>
                )}
                <div className="flex items-center gap-2">
                  <TimelineTitle>{item.title ?? "Untitled"}</TimelineTitle>
                  {item.badge && (
                    <Badge className="pointer-events-none h-5 px-1.5 text-[11px] capitalize">
                      {item.badge}
                    </Badge>
                  )}
                </div>
                <TimelineIndicator className="group-data-completed/timeline-item:bg-primary group-data-completed/timeline-item:text-primary-foreground flex size-6 items-center justify-center group-data-completed/timeline-item:border-none group-data-[orientation=vertical]/timeline:-left-7">
                  <CheckIcon className="size-4 group-not-data-completed/timeline-item:hidden" />
                </TimelineIndicator>
              </TimelineHeader>
              {item.description && (
                <TimelineContent className="line-clamp-1">
                  {item.description}
                </TimelineContent>
              )}
            </TimelineContextMenu>
          </TimelineItem>
        )
      })}
    </Timeline>
  )
}

function TimelineContextMenu<S extends DatabaseSchemas>({
  children,
  item,
  schema,
  resource,
  resourceId,
  primaryKeys,
  isTable,
}: {
  children: React.ReactNode
  item: TimelineViewData
  schema: S
  resource: DatabaseTables<S> | DatabaseViews<S>
  resourceId: string
  primaryKeys: PrimaryKey[]
  isTable: boolean
}) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const inlineForm = useInlineFormFlag(schema, resource)
  const pk = Object.fromEntries(
    primaryKeys.map((pkField) => [pkField.name, item.data[pkField.name]])
  )
  const sheetLink = useSheetHref({ mode: "detail", pk })
  const canDelete = useHasPermission({ schema, resource, action: "delete" })
  const { mutateAsync: deleteRow } = useMutation(
    deleteResourceMutationOptions(schema, resource)
  )

  const deleteConfirm = useConfirmAction(async (target: TimelineViewData) => {
    const deletePk = Object.fromEntries(
      primaryKeys.map((pkField) => [pkField.name, target.data[pkField.name]])
    )
    try {
      await deleteRow(deletePk)
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

  function handleViewDetails() {
    if (inlineForm && sheetLink) {
      navigate({
        to: sheetLink.to as never,
        search: sheetLink.search as never,
      })
      return
    }
    navigate({
      to: "/$schema/resource/$resource/$resourceId/detail",
      params: { schema, resource, resourceId },
    })
  }

  return (
    <>
      <ContextMenu>
        <ContextMenuTrigger
          className="cursor-pointer"
          onClick={handleViewDetails}
        >
          {children}
        </ContextMenuTrigger>
        <ContextMenuContent className="w-52">
          <ContextMenuItem onClick={handleViewDetails}>
            <Eye className="size-4" />
            View details
          </ContextMenuItem>
          {isTable && canDelete && (
            <>
              <ContextMenuSeparator />
              <ContextMenuItem
                variant="destructive"
                onClick={() => deleteConfirm.request(item)}
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
