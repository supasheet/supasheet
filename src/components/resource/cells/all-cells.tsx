import { memo } from "react"

import type { ColumnFieldMetadata, FileObject } from "#/types/fields"

import { AvatarCell } from "./avatar-cell"
import { BarcodeCell } from "./barcode-cell"
import { BooleanCell } from "./boolean-cell"
import { ColorCell } from "./color-cell"
import { DurationCell } from "./duration-cell"
import { FileCell } from "./file-cell"
import { PercentageCell } from "./percentage-cell"
import { RatingCell } from "./rating-cell"
import { SelectCell } from "./select-cell"

export const AllCells = memo(function ({
  columnMetadata,
  value,
}: {
  columnMetadata: ColumnFieldMetadata
  value: unknown
}) {
  switch (columnMetadata.variant) {
    case "boolean":
      return <BooleanCell value={value as string} />
    case "barcode":
      return <BarcodeCell value={value as string | null} />
    case "color":
      return <ColorCell value={value as string} />
    case "percentage":
      return <PercentageCell value={value as number} />
    case "duration":
      return <DurationCell value={value as string} />
    case "file":
      return <FileCell value={value as FileObject[]} />
    case "avatar":
      return <AvatarCell value={value as FileObject | null} />
    case "rating":
      return <RatingCell value={value as number | null} />
    case "select":
      return (
        <SelectCell value={value as string} columnMetadata={columnMetadata} />
      )
    case "money":
      return value ? `${value}` : ""
    case "json":
      return (
        <pre className="truncate">
          {value ? JSON.stringify(value, null, 2) : ""}
        </pre>
      )
    case "date":
      return value ? new Date(value as string).toLocaleDateString() : ""
    case "datetime":
      return value ? new Date(value as string).toLocaleString() : ""
    case "time":
      return value?.toString()
    default:
      return value?.toString()
  }
})
