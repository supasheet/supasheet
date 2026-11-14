import { useMemo } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"
import { useNavigate } from "@tanstack/react-router"

import { EyeIcon, Image as ImageIcon, Trash } from "lucide-react"
import { Subscribe } from "@tanstack/react-table"
import { toast } from "sonner"

import { DataTableAdvancedToolbar } from "#/components/data-table/data-table-advanced-toolbar"
import { DataTableBulkActions } from "#/components/data-table/data-table-bulk-actions"
import { DataTableExportButton } from "#/components/data-table/data-table-export-button"
import { DataTableFilterMenu } from "#/components/data-table/data-table-filter-menu"
import { DataTablePagination } from "#/components/data-table/data-table-pagination"
import { DataTableSortMenu } from "#/components/data-table/data-table-sort-menu"
import { DynamicIcon } from "#/components/resource/resource-definition-utils"
import { ResourceFilterPresets } from "#/components/resource/resource-filter-presets"
import { getResourceTableColumns } from "#/components/resource/resource-table-columns"
import { ConfirmDeleteDialog } from "#/components/shared/confirm-delete-dialog"
import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { ButtonGroup, ButtonGroupSeparator } from "#/components/ui/button-group"
import { Card, CardContent } from "#/components/ui/card"
import { Checkbox } from "#/components/ui/checkbox"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { useConfirmAction } from "#/hooks/use-confirm-action"
import { useDataTable } from "#/hooks/use-data-table"
import { useHasPermission } from "#/hooks/use-permissions"
import { DEFAULT_PAGINATION } from "#/lib/data-table-search"
import type {
  ColumnSchema,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  FilterPreset,
  PrimaryKey,
  ResourceSchema,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import type { EnumBadgeMeta } from "#/lib/fields"
import { getPkValue } from "#/lib/fields"
import {
  deleteBulkResourceMutationOptions,
  deleteResourceMutationOptions,
} from "#/lib/supabase/data/resource"
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
  columnsSchema: ColumnSchema[]
  pageCount: number
  filterPresets?: FilterPreset[]
}

export function ResourceGallery({
  data,
  resourceSchema,
  columnsSchema,
  pageCount,
  filterPresets = [],
}: ResourceGalleryProps) {
  const schema = resourceSchema.schema ?? ""
  const resource = resourceSchema.name ?? ""
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []
  const isTable = isTableSchema(resourceSchema)

  const columns = useMemo(
    () => getResourceTableColumns({ columnsSchema, resourceSchema }),
    [columnsSchema, resourceSchema]
  )
  const rows = useMemo(() => data.map((item) => item.data), [data])

  const queryClient = useQueryClient()
  const canDeleteRows = useHasPermission({
    schema,
    resource,
    action: "delete",
  })
  const { mutateAsync: deleteRows } = useMutation(
    deleteBulkResourceMutationOptions(schema, resource)
  )
  const handleBulkDelete = async (selected: Record<string, unknown>[]) => {
    try {
      await deleteRows(
        selected.map((row) =>
          Object.fromEntries(
            primaryKeys.map((key) => [key.name, row[key.name]])
          )
        )
      )
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, resource],
      })
      toast.success(
        selected.length === 1
          ? "Record deleted"
          : `${selected.length} records deleted`
      )
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to delete record"
      )
    }
  }

  const { table } = useDataTable({
    columns,
    data: rows,
    pageCount,
    initialState: { pagination: DEFAULT_PAGINATION },
    getRowId: (row) => primaryKeys.map((key) => row[key.name]).join("/"),
  })

  return (
    <div className="flex min-h-0 w-full flex-1 flex-col gap-2">
      <DataTableAdvancedToolbar table={table} hideViewOptions>
        <ResourceFilterPresets table={table} filterPresets={filterPresets} />
        <DataTableFilterMenu table={table} />
        <DataTableSortMenu table={table} />
        <DataTableExportButton table={table} filename={resource} />
      </DataTableAdvancedToolbar>
      <DataTableBulkActions
        table={table}
        filename={resource}
        onDelete={isTable && canDeleteRows ? handleBulkDelete : undefined}
      />
      <div className="flex min-h-0 flex-1 flex-col overflow-auto p-1">
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
        <Subscribe source={table.atoms.rowSelection}>
          {() => (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
              {data.map((item, index) => {
                const resourceId = getPkValue(item.data, primaryKeys)
                const tableRow = table.getRowModel().rows[index]
                return (
                  <GalleryCard
                    key={resourceId}
                    item={item}
                    schema={schema}
                    resource={resource}
                    resourceId={resourceId}
                    primaryKeys={primaryKeys}
                    isTable={isTable}
                    selected={tableRow?.getIsSelected() ?? false}
                    onSelectedChange={(checked) =>
                      tableRow?.toggleSelected(checked)
                    }
                  />
                )
              })}
            </div>
          )}
        </Subscribe>
      )}
      </div>
      <DataTablePagination table={table} />
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
  selected,
  onSelectedChange,
}: {
  selected: boolean
  onSelectedChange: (checked: boolean) => void
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
      <Card className={cn("h-full", selected && "ring-2 ring-primary")}>
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
            <div className="absolute top-2 left-2 z-10 rounded-md bg-background/80 p-1 shadow-xs backdrop-blur-sm">
              <Checkbox
                checked={selected}
                onCheckedChange={(checked) => onSelectedChange(!!checked)}
                aria-label="Select item"
              />
            </div>
            <div
              className={cn(
                "absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2",
                item.cover && "hidden"
              )}
            >
              <ImageIcon className="h-12 w-12 text-muted-foreground/40" />
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-5">
              <div className="flex items-center gap-1">
                <span className="line-clamp-1 font-medium text-secondary-foreground">
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

            <p className="line-clamp-2 text-sm text-foreground">
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
