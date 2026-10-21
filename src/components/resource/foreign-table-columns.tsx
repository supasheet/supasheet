import { getColumnCell, getColumnDefMeta } from "#/lib/columns"
import type { DataTableColumnDef } from "#/lib/data-table-types"
import type {
  ColumnSchema,
  ResourceDataSchema,
} from "#/lib/database-meta.types"

export function foreignTableColumns({
  columnsSchema,
  setRecord,
}: {
  columnsSchema: ColumnSchema[]
  setRecord: (record: ResourceDataSchema) => void
}) {
  const cols: DataTableColumnDef<ResourceDataSchema>[] = []

  cols.push(
    ...((columnsSchema ?? []).map((c) => {
      const meta = getColumnDefMeta(null, c)

      return {
        id: c.name,
        accessorKey: c.name,
        header: () => <div className="truncate select-none">{meta.label}</div>,
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
    }) as DataTableColumnDef<ResourceDataSchema>[])
  )

  return cols
}
