import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { EyeIcon, Image as ImageIcon, Trash } from "lucide-react"
import { toast } from "sonner"

import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { ButtonGroup, ButtonGroupSeparator } from "#/components/ui/button-group"
import { Card, CardContent } from "#/components/ui/card"
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
import type { EnumBadgeMeta } from "#/lib/fields"
import { getPkValue } from "#/lib/fields"
import { deleteResourceMutationOptions } from "#/lib/supabase/data/resource"
import { cn } from "#/lib/utils"

export interface GalleryViewData {
  cover: string | null
  title: string | null
  description: string | null
  badge: string | null
  badgeIcon?: EnumBadgeMeta["icon"]
  badgeVariant?: EnumBadgeMeta["variant"]
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
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
          {data.map((item) => {
            const resourceId = getPkValue(item.data, primaryKeys)
            return (
              <GalleryCard
                key={resourceId}
                item={item}
                schema={schema}
                resource={resource}
                resourceId={resourceId}
                primaryKeys={primaryKeys}
                isTable={isTable}
              />
            )
          })}
        </div>
      )}
    </div>
  )
}

function GalleryCard<S extends DatabaseSchemas>({
  item,
  schema,
  resource,
  resourceId,
  primaryKeys,
  isTable,
}: {
  item: GalleryViewData
  schema: S
  resource: DatabaseViews<S> | DatabaseTables<S>
  resourceId: string
  primaryKeys: PrimaryKey[]
  isTable: boolean
}) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const canDelete = useHasPermission({ schema, resource, action: "delete" })
  const { mutateAsync: deleteRow } = useMutation(
    deleteResourceMutationOptions(schema, resource)
  )

  const goToDetail = () =>
    navigate({
      to: "/$schema/resource/$resource/$resourceId/detail",
      params: { schema, resource, resourceId },
    })

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
      <Card className="h-full">
        <CardContent className="flex flex-col gap-4">
          <div className="relative aspect-4/3 w-full overflow-hidden rounded-lg bg-muted">
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
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-5">
              <div className="flex items-center gap-1">
                <span className="text-secondary-foreground font-medium line-clamp-1">
                  {item.title}
                </span>
              </div>
              {item.badge && (
                <Badge variant={item.badgeVariant ?? "outline"}>
                  <DynamicIcon iconName={item.badgeIcon} />
                  {item.badge}
                </Badge>
              )}
            </div>

            <p className="text-foreground text-sm line-clamp-2">
              {item.description}
            </p>
          </div>

          <ButtonGroup className="w-full">
            <Button variant="secondary" className="flex-1" onClick={goToDetail}>
              <EyeIcon aria-hidden="true" />
              View details
            </Button>
            {isTable && canDelete && (
              <>
                <ButtonGroupSeparator />
                <Button
                  size="icon"
                  variant="destructive"
                  onClick={() => deleteConfirm.request(item)}
                >
                  <Trash />
                </Button>
              </>
            )}
          </ButtonGroup>
        </CardContent>
      </Card>
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
