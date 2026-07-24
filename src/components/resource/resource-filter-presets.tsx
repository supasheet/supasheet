import { useMemo } from "react"

import { useNavigate } from "@tanstack/react-router"

import type { ColumnFiltersState } from "@tanstack/react-table"

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
import { encodeFilterValue } from "#/lib/data-table"
import type { FilterPreset } from "#/lib/database-meta.types"

const ALL_RECORDS_ID = "__all__"

function encodePresetFilters(preset: FilterPreset): ColumnFiltersState {
  return preset.filters.map((f) => ({
    id: f.id,
    value: encodeFilterValue(f.operator, f.value),
  }))
}

function filtersEqual(a: ColumnFiltersState, b: ColumnFiltersState): boolean {
  if (a.length !== b.length) return false
  const bById = new Map(b.map((f) => [f.id, f.value]))
  return a.every((f) => bById.get(f.id) === f.value)
}

export function ResourceFilterPresets({
  filterPresets,
  currentFilters,
}: {
  filterPresets: FilterPreset[]
  currentFilters: ColumnFiltersState
}) {
  const navigate = useNavigate()

  const activePresetId = useMemo(() => {
    if (currentFilters.length === 0) return ALL_RECORDS_ID
    const match = filterPresets.find((t) =>
      filtersEqual(encodePresetFilters(t), currentFilters)
    )
    return match?.id
  }, [filterPresets, currentFilters])

  if (filterPresets.length === 0) return null

  const activePreset = filterPresets.find((t) => t.id === activePresetId)
  const triggerLabel =
    activePresetId === ALL_RECORDS_ID
      ? "All records"
      : (activePreset?.name ?? "Custom filter")

  function handleSelect(value: string) {
    if (value === ALL_RECORDS_ID) {
      navigate({
        to: ".",
        search: (prev) => ({ ...prev, filters: undefined, page: 1 }),
      })
      return
    }
    const preset = filterPresets.find((t) => t.id === value)
    if (!preset) return
    navigate({
      to: ".",
      search: (prev) => ({
        ...prev,
        filters: encodePresetFilters(preset),
        page: 1,
      }),
    })
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button size="sm" variant="outline" />}>
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
}
