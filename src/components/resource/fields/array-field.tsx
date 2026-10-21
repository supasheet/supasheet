import { useRef } from "react"

import { GripVertical, Plus, SquarePenIcon, XIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import { ButtonGroup } from "#/components/ui/button-group"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import {
  Sortable,
  SortableContent,
  SortableItem,
  SortableItemHandle,
} from "#/components/ui/sortable"
import type { ColumnFieldMetadata } from "#/types/fields"

import type { ResourceFormApi } from "../form-hook"
import { useFieldContext } from "../form-hook"
import { AllFields } from "./all-fields"

export function ArrayField({
  form,
  columnMetadata,
}: {
  form: ResourceFormApi
  columnMetadata: ColumnFieldMetadata
}) {
  const field = useFieldContext<unknown[]>()

  const rawValue: unknown = field.state.value
  const isNull = rawValue === null
  const isDefault = rawValue === "" && !!columnMetadata.defaultValue
  const value = Array.isArray(rawValue) ? (rawValue as unknown[]) : []
  const isEmptyArray = Array.isArray(rawValue) && value.length === 0
  const currentLength = value.length

  // Maintain stable IDs per item for the Sortable component.
  // IDs must travel with the data when items are reordered/removed/added.
  const stableIds = useRef<string[]>([])

  while (stableIds.current.length < currentLength) {
    stableIds.current.push(crypto.randomUUID())
  }
  stableIds.current.length = Math.max(0, currentLength)

  const sortableItems = stableIds.current.map((id) => ({ id }))

  return (
    <Sortable
      value={sortableItems}
      onDragEnd={(event) => {
        const { active, over } = event

        if (over && active.id !== over.id) {
          const oldIndex = sortableItems.findIndex(
            (item) => item.id === active.id
          )
          const newIndex = sortableItems.findIndex(
            (item) => item.id === over.id
          )

          if (oldIndex !== -1 && newIndex !== -1) {
            const [movedId] = stableIds.current.splice(oldIndex, 1)
            stableIds.current.splice(newIndex, 0, movedId)
            field.moveValue(oldIndex, newIndex)
          }
        }
      }}
      orientation="vertical"
      getItemValue={(item) => item.id}
    >
      <div className="space-y-2 rounded-lg border p-2">
        {isNull && (
          <p className="py-2 text-center text-sm text-muted-foreground">
            Items set to null
          </p>
        )}
        {isEmptyArray && (
          <p className="py-2 text-center text-sm text-muted-foreground">
            Empty array []
          </p>
        )}
        {isDefault && (
          <p className="py-2 text-center text-sm text-muted-foreground">
            DEFAULT VALUE
          </p>
        )}
        <SortableContent render={<div className="space-y-2" />}>
          <>
            {Array.isArray(value) &&
              value.map((_, index) => (
                <SortableItem
                  key={stableIds.current[index]}
                  value={stableIds.current[index]}
                >
                  <form.AppField name={`${field.name}[${index}]`}>
                    {() => (
                      <ButtonGroup className="flex w-full gap-2">
                        <SortableItemHandle
                          render={
                            <Button
                              variant="ghost"
                              size="icon"
                              className="size-8"
                            />
                          }
                        >
                          <GripVertical className="h-4 w-4" />
                        </SortableItemHandle>
                        <ButtonGroup className="flex-1">
                          <AllFields
                            columnMetadata={{
                              ...columnMetadata,
                              required: true,
                              defaultValue: null,
                            }}
                          />
                        </ButtonGroup>
                        <ButtonGroup>
                          <Button
                            type="button"
                            variant="outline"
                            size="icon"
                            onClick={() => {
                              stableIds.current.splice(index, 1)
                              field.removeValue(index)
                            }}
                          >
                            <XIcon className="size-4" />
                          </Button>
                        </ButtonGroup>
                      </ButtonGroup>
                    )}
                  </form.AppField>
                </SortableItem>
              ))}
          </>
        </SortableContent>
        <ButtonGroup className="flex w-full gap-2">
          <ButtonGroup className="flex-1">
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                stableIds.current.push(crypto.randomUUID())
                field.pushValue("")
              }}
              className="flex-1"
            >
              <Plus className="mr-2 h-4 w-4" />
              Add Item
            </Button>
          </ButtonGroup>
          <ButtonGroup>
            <DropdownMenu>
              {/* @ts-expect-error – Radix asChild typing limitation */}
              <DropdownMenuTrigger asChild>
                <Button variant="outline" size="icon">
                  <SquarePenIcon size={16} aria-hidden="true" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                {!columnMetadata.required && (
                  <DropdownMenuItem
                    onClick={() => {
                      stableIds.current = []
                      field.handleChange(null as unknown as unknown[])
                    }}
                  >
                    Set null
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem
                  onClick={() => {
                    stableIds.current = []
                    field.handleChange([])
                  }}
                >
                  Set empty array
                </DropdownMenuItem>
                {columnMetadata.defaultValue && (
                  <DropdownMenuItem
                    onClick={() => {
                      stableIds.current = []
                      field.handleChange("" as unknown as unknown[])
                    }}
                  >
                    Set default value
                  </DropdownMenuItem>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
          </ButtonGroup>
        </ButtonGroup>
      </div>
    </Sortable>
  )
}
