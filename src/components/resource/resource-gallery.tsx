import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { Eye, Image as ImageIcon, Trash } from "lucide-react"
import { toast } from "sonner"

import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
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
import { useConfirmAction } from "#/hooks/use-confirm-action"
import { useHasPermission } from "#/hooks/use-permissions"
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
import { cn } from "#/lib/utils"

export interface GalleryViewData {
  cover: string | null
  title: string | null
  description: string | null
  badge: string | null
  data: Record<string, unknown>
}

interface ResourceGalleryProps {
  data: GalleryViewData[]
  resourceSchema: ResourceSchema
}

export function ResourceGallery({
  data,
  resourceSchema,
}: ResourceGalleryProps) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const isTable = isTableSchema(resourceSchema)

  return (
    <div className="flex flex-col gap-4">
      {data.length === 0 ? (
        <Empty className="min-h-[400px] border">
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <ImageIcon />
            </EmptyMedia>
            <EmptyTitle>No items to display</EmptyTitle>
            <EmptyDescription>
              There are no gallery items available at the moment.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {data.map((item) => {
            const resourceId = getPkValue(item.data, primaryKeys)
            return (
              <GalleryContextMenu
                key={resourceId}
                item={item}
                schema={schema}
                resource={resource}
                resourceId={resourceId}
                primaryKeys={primaryKeys}
                isTable={isTable}
              >
                <Card className="h-full cursor-pointer shadow-xs">
                  <CardHeader>
                    <div className="relative aspect-4/3 w-full overflow-hidden rounded-md bg-muted">
                      {item.cover ? (
                        <img
                          src={item.cover}
                          alt={item.title ?? "Gallery item"}
                          className="h-full w-full object-cover"
                          loading="lazy"
                          onError={(e) => {
                            const target = e.target as HTMLImageElement
                            target.style.display = "none"
                            const sibling = target.nextElementSibling
                            if (sibling) sibling.classList.remove("hidden")
                          }}
                        />
                      ) : null}
                      <div
                        className={cn(
                          "absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2",
                          item.cover && "hidden"
                        )}
                      >
                        <ImageIcon className="h-12 w-12 text-muted-foreground/40" />
                      </div>
                      {item.badge && (
                        <Badge className="absolute top-2 right-2 capitalize">
                          {item.badge}
                        </Badge>
                      )}
                    </div>
                  </CardHeader>
                  <CardContent>
                    <CardTitle className="line-clamp-1">
                      {item.title ?? "Untitled"}
                    </CardTitle>
                    {item.description && (
                      <CardDescription className="line-clamp-2">
                        {item.description}
                      </CardDescription>
                    )}
                  </CardContent>
                </Card>
              </GalleryContextMenu>
            )
          })}
        </div>
      )}
    </div>
  )
}

function GalleryContextMenu<S extends DatabaseSchemas>({
  children,
  item,
  schema,
  resource,
  resourceId,
  primaryKeys,
  isTable,
}: {
  children: React.ReactNode
  item: GalleryViewData
  schema: S
  resource: DatabaseViews<S> | DatabaseTables<S>
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

  const deleteConfirm = useConfirmAction(async (target: GalleryViewData) => {
    const pk = Object.fromEntries(
      primaryKeys.map((pkField) => [pkField.name, target.data[pkField.name]])
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
