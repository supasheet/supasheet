"use client"

import { useMemo, useState } from "react"

import {
  useMutation,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query"

import type {
  ColumnFiltersState,
  PaginationState,
  RowSelectionState,
  SortingState,
  VisibilityState,
} from "@tanstack/react-table"
import { getCoreRowModel, useReactTable } from "@tanstack/react-table"

import { PlusIcon } from "lucide-react"
import { toast } from "sonner"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableActionBar } from "#/components/data-table/data-table-action-bar"
import { DataTableToolbar } from "#/components/data-table/data-table-toolbar"
import { NewRecordTrigger } from "#/components/resource/sheet/new-record-trigger"
import { useHasPermission } from "#/hooks/use-permissions"
import type {
  ColumnSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import {
  deleteBulkResourceMutationOptions,
  foreignTableDataQueryOptions,
  insertBulkResourceMutationOptions,
} from "#/lib/supabase/data/resource"

import { getResourceForeignTableColumns } from "./resource-foreign-table-columns"

type ResourceForeignTableProps = {
  parentResource: string
  parentColumn: string
  parentValue: unknown
  resourceSchema: ResourceSchema
  columnsSchema: ColumnSchema[]
  selectClause?: string
}

export function ResourceForeignTable({
  parentResource,
  parentColumn,
  parentValue,
  resourceSchema,
  columnsSchema,
  selectClause,
}: ResourceForeignTableProps) {
  const queryClient = useQueryClient()
  const [sorting, setSorting] = useState<SortingState>([])
  const [pagination, setPagination] = useState<PaginationState>({
    pageIndex: 0,
    pageSize: 10,
  })
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>([])
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({})
  const [columnVisibility, setColumnVisibility] = useState<VisibilityState>({})

  const sortId = sorting[0]?.id
  const sortDesc = sorting[0]?.desc ?? false

  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const schema = resourceSchema.schema
  const table = resourceSchema.name

  const canDelete = useHasPermission(`${schema}.${table}:delete`)
  const canInsert = useHasPermission(`${schema}.${table}:insert`)

  const hasParentValue =
    parentValue !== undefined && parentValue !== null && parentValue !== ""

  const defaultQuery = useMemo<TableMetadata["query"]>(() => {
    if (!resourceSchema.comment) return undefined
    try {
      return (JSON.parse(resourceSchema.comment) as TableMetadata).query
    } catch {
      return undefined
    }
  }, [resourceSchema.comment])

  const { data: queryResult } = useSuspenseQuery(
    foreignTableDataQueryOptions(
      schema,
      table,
      parentResource as never,
      parentColumn,
      hasParentValue ? parentValue : "__noop__",
      defaultQuery,
      selectClause,
      pagination.pageIndex + 1,
      pagination.pageSize,
      sortId,
      sortDesc,
      columnFilters
    )
  )

  const data = hasParentValue ? (queryResult?.result ?? []) : []
  const totalCount = hasParentValue ? (queryResult?.count ?? 0) : 0
  const pageCount = Math.max(1, Math.ceil(totalCount / pagination.pageSize))

  const { mutateAsync: deleteRows } = useMutation(
    deleteBulkResourceMutationOptions(schema, table)
  )
  const { mutateAsync: insertBulkRows } = useMutation(
    insertBulkResourceMutationOptions(schema, table)
  )

  const duplicated = resourceSchema.comment
    ? (JSON.parse(resourceSchema.comment) as TableMetadata).fields?.duplicated
    : undefined

  const handleDuplicate = async (rows: Record<string, unknown>[]) => {
    try {
      const pkNames = new Set(primaryKeys.map((k) => k.name))
      const columnNames = new Set(
        columnsSchema.map((c) => c.name).filter((n): n is string => n !== null)
      )
      const fields = duplicated ?? [...columnNames]
      const stripped = rows.map((row) =>
        Object.fromEntries(
          fields
            .filter((f) => !pkNames.has(f) && columnNames.has(f))
            .map((f) => [f, row[f]])
        )
      )
      await insertBulkRows(stripped)
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, table],
      })
      toast.success(
        rows.length === 1
          ? "Record duplicated"
          : `${rows.length} records duplicated`
      )
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to duplicate records"
      )
    }
  }

  const handleDelete = async (rows: Record<string, unknown>[]) => {
    try {
      await deleteRows(
        rows.map((row) =>
          Object.fromEntries(
            primaryKeys.map((key) => [key.name, row[key.name]])
          )
        )
      )
      queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, table],
      })
      toast.success(
        rows.length === 1 ? "Record deleted" : `${rows.length} records deleted`
      )
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to delete record"
      )
    }
  }

  const columns = useMemo(
    () =>
      getResourceForeignTableColumns({
        columnsSchema,
        resourceSchema,
      }),
    [data, columnsSchema, resourceSchema]
  )

  const tableInstance = useReactTable({
    data,
    columns,
    pageCount,
    state: {
      sorting,
      pagination,
      columnFilters,
      rowSelection,
      columnVisibility,
    },
    getRowId: primaryKeys.length
      ? (row) => primaryKeys.map((key) => row[key.name]).join("/")
      : undefined,
    onSortingChange: setSorting,
    onPaginationChange: setPagination,
    onColumnFiltersChange: setColumnFilters,
    onRowSelectionChange: setRowSelection,
    onColumnVisibilityChange: setColumnVisibility,
    manualSorting: true,
    manualPagination: true,
    manualFiltering: true,
    getCoreRowModel: getCoreRowModel(),
  })

  const defaults = hasParentValue
    ? { [parentColumn]: String(parentValue) }
    : undefined

  const newRecordUrl = (() => {
    const params = new URLSearchParams()
    if (defaults) params.set("defaults", JSON.stringify(defaults))
    const qs = params.toString()
    return `/${schema}/resource/${table}/new${qs ? `?${qs}` : ""}`
  })()

  return (
    <DataTable table={tableInstance}>
      <DataTableToolbar table={tableInstance}>
        {canInsert && (
          <NewRecordTrigger
            schema={schema}
            resource={table}
            defaults={defaults}
            url={newRecordUrl}
            size="sm"
          >
            <PlusIcon className="size-4" />
            New record
          </NewRecordTrigger>
        )}
      </DataTableToolbar>
      <DataTableActionBar
        table={tableInstance}
        onDuplicate={
          canInsert && primaryKeys.length ? handleDuplicate : undefined
        }
        onDelete={canDelete && primaryKeys.length ? handleDelete : undefined}
      />
    </DataTable>
  )
}
