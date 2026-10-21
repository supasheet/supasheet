import { Subscribe } from "@tanstack/react-table"
import type { RowData } from "@tanstack/react-table"

import { ChevronDownIcon, FilterIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type { DataTableInstance, FilterVariant } from "#/lib/data-table-types"
import type { FilterPreset } from "#/lib/database-meta.types"
import { getFiltersSignature, ruleToFilterItem } from "#/lib/filter-presets"

const ALL_RECORDS_ID = "__all__"

function getVariants<TData extends RowData>(table: DataTableInstance<TData>) {
  return Object.fromEntries(
    table
      .getAllColumns()
      .map((column) => [column.id, column.columnDef.meta?.variant])
  ) as Record<string, FilterVariant | undefined>
}

export function ResourceFilterPresets<TData extends RowData>({
  table,
  filterPresets,
}: {
  table: DataTableInstance<TData>
  filterPresets: FilterPreset[]
}) {
  if (filterPresets.length === 0) return null

  function getPresetFilters(preset: FilterPreset) {
    const variants = getVariants(table)
    return preset.filters.map((rule, index) =>
      ruleToFilterItem(rule, variants, index)
    )
  }

  function handleSelect(value: string) {
    if (value === ALL_RECORDS_ID) {
      table.resetColumnFilters(true)
      return
    }
    const preset = filterPresets.find((t) => t.id === value)
    if (!preset) return
    table.setJoinOperator("and")
    table.setColumnFilters(getPresetFilters(preset))
  }

  return (
    <Subscribe source={table.atoms.columnFilters}>
      {(columnFilters) => {
        const current = table.getColumnFilterItems()
        const activePresetId =
          columnFilters.length === 0
            ? ALL_RECORDS_ID
            : filterPresets.find(
                (preset) =>
                  getFiltersSignature(getPresetFilters(preset)) ===
                  getFiltersSignature(current)
              )?.id
        const activePreset = filterPresets.find((t) => t.id === activePresetId)
        const triggerLabel =
          activePresetId === ALL_RECORDS_ID
            ? "All records"
            : (activePreset?.name ?? "Custom filter")

        return (
          <DropdownMenu>
            <DropdownMenuTrigger render={<Button variant="outline" />}>
              <FilterIcon className="size-3" />
              <span className="truncate font-medium">{triggerLabel}</span>
              <ChevronDownIcon className="size-3.5 opacity-50" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="w-fit rounded-lg">
              <DropdownMenuGroup>
                <DropdownMenuLabel>Filter presets</DropdownMenuLabel>
              </DropdownMenuGroup>
              <DropdownMenuRadioGroup
                value={activePresetId}
                onValueChange={handleSelect}
              >
                <DropdownMenuRadioItem value={ALL_RECORDS_ID}>
                  All records
                </DropdownMenuRadioItem>
                <DropdownMenuSeparator />
                {filterPresets.map((preset) => (
                  <DropdownMenuRadioItem key={preset.id} value={preset.id}>
                    {preset.name}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        )
      }}
    </Subscribe>
  )
}
