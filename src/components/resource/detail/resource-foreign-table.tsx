import { useMemo } from "react"

import {
  useMutation,
  useQuery,
  useQueryClient,
  useSuspenseQuery,
} from "@tanstack/react-query"

import { PlusIcon } from "lucide-react"
import { toast } from "sonner"

import { DataTable } from "#/components/data-table/data-table"
import { DataTableAdvancedToolbar } from "#/components/data-table/data-table-advanced-toolbar"
import { DataTableBulkActions } from "#/components/data-table/data-table-bulk-actions"
import { DataTableFilterMenu } from "#/components/data-table/data-table-filter-menu"
import { DataTableSortMenu } from "#/components/data-table/data-table-sort-menu"
import { NewRecordTrigger } from "#/components/resource/sheet/new-record-trigger"
import {
  useLocalDataTable,
  useLocalTableState,
} from "#/hooks/use-local-data-table"
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
  resourceActionsQueryOptions,
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
  const primaryKeys = isTableSchema(resourceSchema)
    ? (resourceSchema.primary_keys ?? [])
    : []

  const schema = resourceSchema.schema
  const table = resourceSchema.name

  const canDelete = useHasPermission({
    schema,
    resource: table,
    action: "delete",
  })
  const canInsert = useHasPermission({
    schema,
    resource: table,
    action: "insert",
  })

  const { data: actions = [] } = useQuery(
    resourceActionsQueryOptions(schema as never, table)
  )

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

  const columns = useMemo(
    () =>
      getResourceForeignTableColumns({
        columnsSchema,
        resourceSchema,
        actions,
      }),
    [columnsSchema, resourceSchema, actions]
  )

  const { query, state } = useLocalTableState(columns)

  const { data: queryResult } = useSuspenseQuery(
    foreignTableDataQueryOptions(
      schema,
      table,
      parentResource as never,
      parentColumn,
      hasParentValue ? parentValue : "__noop__",
      defaultQuery,
      selectClause,
      query
    )
  )

  const data = hasParentValue ? (queryResult?.result ?? []) : []
  const totalCount = hasParentValue ? (queryResult?.count ?? 0) : 0
  const pageCount = Math.max(1, Math.ceil(totalCount / query.perPage))

  const { mutateAsync: deleteRows } = useMutation(
    deleteBulkResourceMutationOptions(schema, table)
  )
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

  const { table: tableInstance } = useLocalDataTable({
    data,
    columns,
    tableState: state,
    pageCount,
    getRowId: primaryKeys.length
      ? (row) => primaryKeys.map((key) => row[key.name]).join("/")
      : undefined,
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
    <DataTable
      table={tableInstance}
      actionBar={
        <DataTableBulkActions
          table={tableInstance}
          filename={table}
          onDelete={canDelete && primaryKeys.length ? handleDelete : undefined}
        />
      }
    >
      <DataTableAdvancedToolbar table={tableInstance}>
        <DataTableFilterMenu table={tableInstance} />
        <DataTableSortMenu table={tableInstance} />
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
      </DataTableAdvancedToolbar>
    </DataTable>
  )
}
