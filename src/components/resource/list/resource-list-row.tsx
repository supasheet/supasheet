import { useNavigate } from "@tanstack/react-router"

import type { Row } from "@tanstack/react-table"

import { Checkbox } from "#/components/ui/checkbox"
import { useInlineFormFlag } from "#/hooks/use-inline-form-flag"
import { useSheetHref } from "#/hooks/use-sheet-href"
import type {
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
  ListLayout,
  PrimaryKey,
} from "#/lib/database-meta.types"
import { getPkValue } from "#/lib/fields"
import { cn } from "#/lib/utils"

import { readField } from "./read-field"

interface ResourceListRowProps<S extends DatabaseSchemas> {
  row: Row<Record<string, unknown>>
  listView: ListLayout
  schema: S
  resource: DatabaseTables<S> | DatabaseViews<S>
  primaryKeys: PrimaryKey[]
}

export function ResourceListRow<S extends DatabaseSchemas>({
  row,
  listView,
  schema,
  resource,
  primaryKeys,
}: ResourceListRowProps<S>) {
  const navigate = useNavigate()
  const inlineForm = useInlineFormFlag(schema, resource)
  const data = row.original
  const pk = Object.fromEntries(primaryKeys.map((k) => [k.name, data[k.name]]))
  const sheetLink = useSheetHref({ mode: "detail", pk })

  const titleValue = readField(data, listView.title)
  const descriptionValue = readField(data, listView.description)
  const field1Value = readField(data, listView.field_1)
  const field2Value = readField(data, listView.field_2)

  function handleClick() {
    if (inlineForm && sheetLink) {
      navigate({
        to: sheetLink.to as never,
        search: sheetLink.search as never,
      })
      return
    }
    const resourceId = getPkValue(data, primaryKeys)
    navigate({
      to: "/$schema/resource/$resource/$resourceId/detail",
      params: { schema, resource, resourceId },
    })
  }

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={handleClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          handleClick()
        }
      }}
      className={cn(
        "flex cursor-pointer items-center gap-4 px-4 py-3 transition-colors hover:bg-muted/40",
        row.getIsSelected() && "bg-muted/60"
      )}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(checked) => row.toggleSelected(!!checked)}
          aria-label="Select row"
        />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium">
          {titleValue ?? "Untitled"}
        </div>
        {descriptionValue && (
          <div className="truncate text-xs text-muted-foreground">
            {descriptionValue}
          </div>
        )}
      </div>
      <div className="hidden min-w-0 flex-1 flex-col gap-1 text-sm sm:flex">
        {field1Value && (
          <div className="truncate text-muted-foreground">{field1Value}</div>
        )}
        {field2Value && (
          <div className="truncate text-muted-foreground">{field2Value}</div>
        )}
      </div>
    </div>
  )
}
