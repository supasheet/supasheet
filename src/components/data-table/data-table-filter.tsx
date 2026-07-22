import { useEffect, useRef, useState } from "react"

import type { Column, ColumnFiltersState, Table } from "@tanstack/react-table"

import { format } from "date-fns"
import {
  CalendarIcon,
  ChevronsUpDownIcon,
  ListFilterIcon,
  Trash2Icon,
} from "lucide-react"

import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import { Calendar } from "#/components/ui/calendar"
import { Checkbox } from "#/components/ui/checkbox"
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "#/components/ui/command"
import { Input } from "#/components/ui/input"
import { NativeSelect, NativeSelectOption } from "#/components/ui/native-select"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "#/components/ui/popover"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "#/components/ui/sheet"
import { useIsMobile } from "#/hooks/use-mobile"
import {
  decodeFilterValue,
  encodeFilterValue,
  getDefaultFilterOperator,
  getFilterOperators,
} from "#/lib/data-table"
import { cn } from "#/lib/utils"
import type { FilterOperator } from "#/types/data-table"

interface DataTableFilterProps<TData> {
  table: Table<TData>
}

export function DataTableFilter<TData>({ table }: DataTableFilterProps<TData>) {
  const [open, setOpen] = useState(false)
  const addButtonRef = useRef<HTMLButtonElement>(null)
  const isMobile = useIsMobile()
  const side = isMobile ? "bottom" : "right"

  const columnFilters = table.getState().columnFilters
  const filterableColumns = table
    .getAllColumns()
    .filter((col) => col.getCanFilter() && col.columnDef.meta?.variant)

  const onFilterAdd = () => {
    // Pick first column that doesn't already have a filter
    const used = new Set(columnFilters.map((f) => f.id))
    const col =
      filterableColumns.find((c) => !used.has(c.id)) ?? filterableColumns[0]
    if (!col) return
    const variant = col.columnDef.meta?.filterVariant ?? "text"
    const defaultOp = getDefaultFilterOperator(variant)
    table.setColumnFilters([
      ...columnFilters.filter((f) => f.id !== col.id),
      { id: col.id, value: encodeFilterValue(defaultOp, "") },
    ])
  }

  const onFilterUpdate = (id: string, newValue: string) => {
    table.setColumnFilters(
      columnFilters.map((f) => (f.id === id ? { ...f, value: newValue } : f))
    )
  }

  const onFilterFieldChange = (oldId: string, newColId: string) => {
    const newCol = filterableColumns.find((c) => c.id === newColId)
    if (!newCol) return
    const variant = newCol.columnDef.meta?.filterVariant ?? "text"
    const defaultOp = getDefaultFilterOperator(variant)
    table.setColumnFilters([
      ...columnFilters.filter((f) => f.id !== oldId && f.id !== newColId),
      { id: newColId, value: encodeFilterValue(defaultOp, "") },
    ])
  }

  const onFilterRemove = (id: string) => {
    table.setColumnFilters(columnFilters.filter((f) => f.id !== id))
    requestAnimationFrame(() => addButtonRef.current?.focus())
  }

  if (filterableColumns.length === 0) return null

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger
        render={<Button variant="outline" size="sm" className="font-normal" />}
      >
        <ListFilterIcon
          data-icon="inline-start"
          className="text-muted-foreground"
        />
        Filter
        {columnFilters.length > 0 && (
          <Badge
            variant="secondary"
            className="h-[18px] px-1.5 font-mono text-[10px] font-normal"
          >
            {columnFilters.length}
          </Badge>
        )}
      </SheetTrigger>

      <SheetContent
        side={side}
        className={cn(
          "gap-0",
          side === "right" && "w-full! sm:max-w-lg!",
          side === "bottom" && "max-h-[80vh]"
        )}
      >
        <SheetHeader className="border-b">
          <SheetTitle>
            {columnFilters.length > 0 ? "Filters" : "No filters applied"}
          </SheetTitle>
          <SheetDescription className={cn(columnFilters.length > 0 && "sr-only")}>
            Add filters to refine your rows.
          </SheetDescription>
        </SheetHeader>

        <div className="flex flex-1 flex-col gap-3.5 overflow-y-auto p-4">
          {columnFilters.length > 0 && (
            <div role="list" className="flex flex-col gap-2">
              {columnFilters.map((filter) => (
                <DataTableFilterItem
                  key={filter.id}
                  filter={filter}
                  filterableColumns={filterableColumns}
                  onUpdate={(newEncoded) => onFilterUpdate(filter.id, newEncoded)}
                  onFieldChange={(newId) => onFilterFieldChange(filter.id, newId)}
                  onRemove={() => onFilterRemove(filter.id)}
                />
              ))}
            </div>
          )}
        </div>

        <SheetFooter className="flex-row border-t">
          <Button size="sm" ref={addButtonRef} onClick={onFilterAdd}>
            Add filter
          </Button>
          {columnFilters.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => table.setColumnFilters([])}
            >
              Reset filters
            </Button>
          )}
        </SheetFooter>
      </SheetContent>
    </Sheet>
  )
}

interface DataTableFilterItemProps<TData> {
  filter: ColumnFiltersState[number]
  filterableColumns: Column<TData>[]
  onUpdate: (newEncodedValue: string) => void
  onFieldChange: (newColumnId: string) => void
  onRemove: () => void
}

function DataTableFilterItem<TData>({
  filter,
  filterableColumns,
  onUpdate,
  onFieldChange,
  onRemove,
}: DataTableFilterItemProps<TData>) {
  const [fieldOpen, setFieldOpen] = useState(false)
  const [valueOpen, setValueOpen] = useState(false)

  const column = filterableColumns.find((col) => col.id === filter.id)
  const columnMeta = column?.columnDef.meta
  const variant = columnMeta?.filterVariant ?? "text"

  const { operator, value: rawValue } = decodeFilterValue(
    String(filter.value ?? "")
  )
  const filterOperators = getFilterOperators(variant)

  const [textValue, setTextValue] = useState(rawValue)

  // Sync local text state when field changes (operator reset clears rawValue)
  useEffect(() => {
    setTextValue(rawValue)
  }, [filter.id, rawValue])

  const isEmptyOp =
    (operator === "is" || operator === "not.is") && variant !== "boolean"

  const handleOperatorChange = (newOp: FilterOperator) => {
    const clearValue = newOp === "is" || newOp === "not.is"
    onUpdate(encodeFilterValue(newOp, clearValue ? "" : rawValue))
  }

  return (
    <div role="listitem" className="flex flex-wrap items-center gap-2">
      {/* Field selector */}
      <Popover open={fieldOpen} onOpenChange={setFieldOpen}>
        <PopoverTrigger
          render={
            <Button
              variant="outline"
              size="sm"
              className="min-w-28 flex-1 justify-between font-normal sm:max-w-40"
            />
          }
        >
          <span className="truncate">{columnMeta?.name ?? filter.id}</span>
          <ChevronsUpDownIcon data-icon="inline-end" className="opacity-50" />
        </PopoverTrigger>
        <PopoverContent className="w-40 p-0" align="start">
          <Command>
            <CommandInput placeholder="Search fields..." />
            <CommandList>
              <CommandEmpty>No fields found.</CommandEmpty>
              <CommandGroup>
                {filterableColumns.map((col) => (
                  <CommandItem
                    key={col.id}
                    value={col.id}
                    data-checked={col.id === filter.id}
                    onSelect={(value) => {
                      onFieldChange(value)
                      setFieldOpen(false)
                    }}
                  >
                    <span className="truncate">{col.columnDef.meta?.name}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>

      {/* Operator selector */}
      <NativeSelect
        size="sm"
        value={operator}
        onChange={(e) => handleOperatorChange(e.target.value as FilterOperator)}
        className="min-w-28 flex-1 sm:max-w-40"
      >
        {filterOperators.map((op) => (
          <NativeSelectOption key={op.value} value={op.value}>
            {op.label}
          </NativeSelectOption>
        ))}
      </NativeSelect>

      {/* Value input */}
      <div className="min-w-36 flex-[2] sm:max-w-60">
        {isEmptyOp ? (
          <div className="h-7 w-full rounded-md border bg-transparent" />
        ) : (
          <FilterValueInput
            variant={variant}
            operator={operator}
            rawValue={rawValue}
            columnMeta={columnMeta}
            textValue={textValue}
            setTextValue={setTextValue}
            valueOpen={valueOpen}
            setValueOpen={setValueOpen}
            onUpdate={(newRawValue) =>
              onUpdate(encodeFilterValue(operator, newRawValue))
            }
          />
        )}
      </div>

      {/* Remove */}
      <Button variant="outline" size="icon-sm" onClick={onRemove} className="shrink-0">
        <Trash2Icon />
      </Button>
    </div>
  )
}

interface FilterValueInputProps {
  variant: string
  operator: FilterOperator
  rawValue: string
  columnMeta?: Column<unknown>["columnDef"]["meta"]
  textValue: string
  setTextValue: (v: string) => void
  valueOpen: boolean
  setValueOpen: (v: boolean) => void
  onUpdate: (newRawValue: string | string[]) => void
}

function FilterValueInput({
  variant,
  rawValue,
  columnMeta,
  textValue,
  setTextValue,
  valueOpen,
  setValueOpen,
  onUpdate,
}: FilterValueInputProps) {
  switch (variant) {
    case "text":
    case "number":
    case "range":
    case "uuid":
      return (
        <Input
          type={variant === "text" ? "text" : "number"}
          placeholder={"Enter a value..."}
          value={textValue}
          onChange={(e) => setTextValue(e.target.value)}
          onBlur={() => onUpdate(textValue)}
          onKeyDown={(e) => {
            if (e.key === "Enter") onUpdate(textValue)
          }}
          className="h-7 w-full focus-visible:ring-0"
        />
      )

    case "boolean":
      return (
        <NativeSelect
          size="sm"
          className="w-full"
          value={rawValue}
          onChange={(e) => onUpdate(e.target.value)}
        >
          <NativeSelectOption value="" disabled>
            Select...
          </NativeSelectOption>
          <NativeSelectOption value="true">True</NativeSelectOption>
          <NativeSelectOption value="false">False</NativeSelectOption>
        </NativeSelect>
      )

    case "select":
    case "multiSelect": {
      const multiple = variant === "multiSelect"
      const selectedValues = rawValue ? rawValue.split(",").filter(Boolean) : []

      const toggleValue = (val: string) => {
        if (multiple) {
          const next = selectedValues.includes(val)
            ? selectedValues.filter((v) => v !== val)
            : [...selectedValues, val]
          onUpdate(next)
        } else {
          onUpdate(val === selectedValues[0] ? "" : val)
          setValueOpen(false)
        }
      }

      return (
        <Popover open={valueOpen} onOpenChange={setValueOpen}>
          <PopoverTrigger
            render={
              <Button
                variant="outline"
                size="sm"
                className="w-full justify-start font-normal"
              />
            }
          >
            {selectedValues.length > 0 ? (
              <div className="flex items-center gap-1 overflow-hidden">
                {selectedValues.slice(0, 2).map((v) => {
                  const opt = columnMeta?.options?.find((o) => o.value === v)
                  return (
                    <Badge
                      key={v}
                      variant="secondary"
                      className="rounded-sm px-1 text-xs font-normal"
                    >
                      {opt?.label ?? v}
                    </Badge>
                  )
                })}
                {selectedValues.length > 2 && (
                  <span className="text-xs text-muted-foreground">
                    +{selectedValues.length - 2}
                  </span>
                )}
              </div>
            ) : (
              <span className="text-muted-foreground">
                Select {multiple ? "options" : "option"}...
              </span>
            )}
          </PopoverTrigger>
          <PopoverContent className="w-48 p-0" align="start">
            <Command>
              <CommandInput
                placeholder={`Search ${columnMeta?.name ?? ""}...`}
              />
              <CommandList className="max-h-48">
                <CommandEmpty>No results found.</CommandEmpty>
                <CommandGroup>
                  {columnMeta?.options?.map((opt) => (
                    <CommandItem
                      key={opt.value}
                      value={opt.value}
                      onSelect={() => toggleValue(opt.value)}
                    >
                      <Checkbox
                        checked={selectedValues.includes(opt.value)}
                        className="pointer-events-none"
                      />
                      {/* {opt.icon && (
                        <opt.icon className="size-4 text-muted-foreground" />
                      )} */}
                      <span>{opt.label}</span>
                    </CommandItem>
                  ))}
                </CommandGroup>
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>
      )
    }

    case "time":
      return (
        <Input
          type="time"
          step="1"
          value={textValue}
          onChange={(e) => {
            setTextValue(e.target.value)
            onUpdate(e.target.value)
          }}
          className="h-7 w-full focus-visible:ring-0"
        />
      )

    case "timetz": {
      // Strip the trailing timezone offset for the time input ("10:30:00+05:00" → "10:30:00")
      const timeDisplay = rawValue.replace(/[+-]\d{2}:\d{2}$/, "")

      const handleTimetzChange = (val: string) => {
        setTextValue(val)
        if (!val) {
          onUpdate("")
          return
        }
        const offsetMins = -new Date().getTimezoneOffset()
        const sign = offsetMins >= 0 ? "+" : "-"
        const abs = Math.abs(offsetMins)
        const tz = `${sign}${String(Math.floor(abs / 60)).padStart(2, "0")}:${String(abs % 60).padStart(2, "0")}`
        onUpdate(`${val}${tz}`)
      }

      return (
        <Input
          type="time"
          step="1"
          value={timeDisplay}
          onChange={(e) => handleTimetzChange(e.target.value)}
          className="h-7 w-full focus-visible:ring-0"
        />
      )
    }

    case "timestamp":
      return (
        <Input
          type="datetime-local"
          step="1"
          value={textValue.slice(0, 16)}
          onChange={(e) => {
            setTextValue(e.target.value)
            onUpdate(e.target.value)
          }}
          className="h-7 w-full focus-visible:ring-0"
        />
      )

    case "timestamptz": {
      // rawValue is stored as UTC ISO ("2026-03-22T05:30:00.000Z").
      // Convert to local datetime-local format for display; convert back on change.
      const displayValue = rawValue
        ? format(new Date(rawValue), "yyyy-MM-dd'T'HH:mm")
        : ""

      return (
        <Input
          type="datetime-local"
          step="1"
          value={displayValue}
          onChange={(e) => {
            const val = e.target.value
            setTextValue(val)
            // datetime-local strings without timezone are parsed as local time by
            // the engine, so new Date(val).toISOString() correctly gives UTC.
            onUpdate(val ? new Date(val).toISOString() : "")
          }}
          className="h-7 w-full focus-visible:ring-0"
        />
      )
    }

    case "date": {
      // Parse as local midnight — appending T00:00:00 prevents the browser
      // from interpreting the bare date string as UTC, which would shift the
      // displayed date by one day in timezones ahead of UTC.
      const dateValue = rawValue ? new Date(`${rawValue}T00:00:00`) : undefined

      return (
        <Popover open={valueOpen} onOpenChange={setValueOpen}>
          <PopoverTrigger
            render={
              <Button
                variant="outline"
                size="sm"
                className={cn(
                  "w-full justify-start font-normal",
                  !rawValue && "text-muted-foreground"
                )}
              />
            }
          >
            <CalendarIcon data-icon="inline-start" />
            <span className="truncate">
              {dateValue ? format(dateValue, "MMM d, y") : "Pick a date"}
            </span>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-0" align="start">
            <Calendar
              mode="single"
              selected={dateValue}
              onSelect={(date) => {
                // Use date-fns format (local time) instead of toISOString() (UTC)
                // to avoid the date shifting one day back in UTC+ timezones.
                onUpdate(date ? format(date, "yyyy-MM-dd") : "")
                setValueOpen(false)
              }}
            />
          </PopoverContent>
        </Popover>
      )
    }

    default:
      return null
  }
}
