import type { ColumnDef } from "@tanstack/react-table"

import { getColumnCell, getColumnMetadata } from "#/lib/columns"
import type {
  ColumnSchema,
  ResourceDataSchema,
} from "#/lib/database-meta.types"
import type { ResourceActionSchema } from "#/lib/supabase/data/resource"

import { ResourceRowActions } from "./resource-row-actions"

export function foreignTableColumns({
  schema,
  resource,
  columnsSchema,
  setRecord,
  actions = [],
}: {
  schema: string
  resource: string
  columnsSchema: ColumnSchema[]
  setRecord: (record: ResourceDataSchema) => void
  actions?: ResourceActionSchema[]
}) {
  const cols: ColumnDef<ResourceDataSchema, unknown>[] = []

  if (actions.length > 0) {
    cols.push({
      id: "actions",
      header: () => null,
      cell: ({ row }) => (
        <ResourceRowActions
          schema={schema}
          resource={resource}
          record={row.original}
          actions={actions}
          columnsSchema={columnsSchema}
        />
      ),
      size: 40,
      enableSorting: false,
      enableHiding: false,
      enableColumnFilter: false,
    })
  }

  cols.push(
    ...((columnsSchema ?? []).map((c) => {
      const meta = getColumnMetadata(null, c)

      return {
        id: c.name,
        accessorKey: c.name,
        header: () => <div className="truncate select-none">{meta.name}</div>,
        cell: ({ row }) => {
          const cell = getColumnCell(c)

          if (cell === "json" || cell === "array") {
            return (
              <pre
                className="truncate select-none"
                onClick={() => {
                  setRecord(row.original)
                }}
              >
                {JSON.stringify(row.original?.[c.name], null, 2)}
              </pre>
            )
          }

          return (
            <div
              className="truncate select-none"
              onClick={() => {
                setRecord(row.original)
              }}
            >
              {row.original[c.name] as string}
            </div>
          )
        },
        size: 150,
        enableColumnFilter: true,
        meta,
        enableSorting: true,
        enableHiding: true,
      }
    }) as ColumnDef<ResourceDataSchema, unknown>[])
  )

  return cols
}
