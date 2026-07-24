import { useState } from "react"

import { ButtonGroup } from "#/components/ui/button-group"
import { DropdownMenuItem } from "#/components/ui/dropdown-menu"
import { Input } from "#/components/ui/input"
import type { Relationship, TableMetadata } from "#/lib/database-meta.types"
import type { FieldProps } from "#/types/fields"

import { ForeignTableSheet } from "../foreign-table"
import type { ResourceFormApi } from "../form-hook"
import { useFieldContext } from "../form-hook"
import { FieldOptionDropdown } from "./field-option-dropdown"
import { ForeignDataCombobox } from "./foreign-data-combobox"

export function ForeignKeyField({
  columnMetadata,
  relationship,
  tableMetadata,
  form,
}: FieldProps & {
  relationship: Relationship
  tableMetadata?: TableMetadata
  form?: ResourceFormApi
}) {
  const field = useFieldContext<unknown>()
  const [open, setOpen] = useState(false)

  const joinConfig = tableMetadata?.query?.join?.find(
    (j) => j.on === relationship.source_column_name
  )

  const behavior = tableMetadata?.fields?.lookups?.[field.name]

  const placeholder =
    field.state.value === "" && columnMetadata.defaultValue
      ? "DEFAULT VALUE"
      : field.state.value === null
        ? "NULL"
        : "EMPTY"

  const applyFill = (record: Record<string, unknown>) => {
    if (!behavior?.fill?.length || !form) return
    for (const rule of behavior.fill) {
      const val = record[rule.target_column]
      if (val !== undefined) form.setFieldValue(rule.source_column, val)
    }
  }

  return (
    <ButtonGroup className="w-full">
      {joinConfig ? (
        <ButtonGroup className="w-full">
          <ForeignDataCombobox
            columnMetadata={columnMetadata}
            relationship={relationship}
            joinConfig={joinConfig}
            behavior={behavior}
            form={form}
            onRecordSelect={applyFill}
          />
        </ButtonGroup>
      ) : (
        <ButtonGroup className="w-full">
          <Input
            name={field.name}
            value={(field.state.value as string | null | undefined) ?? ""}
            onChange={(e) => field.handleChange(e.target.value)}
            onBlur={field.handleBlur}
            disabled={columnMetadata.disabled}
            placeholder={placeholder}
          />
        </ButtonGroup>
      )}
      <FieldOptionDropdown
        columnMetadata={columnMetadata}
        setValue={(value) => field.handleChange(value)}
      >
        <DropdownMenuItem onClick={() => setOpen(true)}>
          Select Record
        </DropdownMenuItem>
      </FieldOptionDropdown>
      {open && (
        <ForeignTableSheet
          open={open}
          onOpenChange={setOpen}
          relationship={relationship}
          setRecord={(record) => {
            field.handleChange(record[relationship.target_column_name])
            applyFill(record)
            setOpen(false)
          }}
        />
      )}
    </ButtonGroup>
  )
}
