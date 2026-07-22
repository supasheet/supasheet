import type { ReactElement } from "react"

import type { ColumnSchema } from "#/lib/database-meta.types"

import type { FilterVariant } from "./data-table"

export type ColumnFieldMetadata = {
  name: string
  variant:
    | "uuid"
    | "text"
    | "long_text"
    | "number"
    | "date"
    | "datetime"
    | "boolean"
    | "json"
    | "select"
    | "time"
    | "money"
    | "file"
    | "avatar"
    | "rich_text"
    | "email"
    | "tel"
    | "url"
    | "rating"
    | "percentage"
    | "color"
    | "duration"
    | "array"
  filterVariant: FilterVariant
  icon: ReactElement | null
  description?: string
  defaultValue: string | null
  required: boolean
  disabled: boolean
  isArray: boolean
  isMetadata: boolean
  isPrimaryKey: boolean
  isRelationship: boolean
  // relationship: Relationship | undefined
  comment: string | null
  // primaryKeys: PrimaryKey[]
  table: string
  schema: string
  options?: {
    label: string
    value: string
  }[]
}

export type FieldProps = {
  columnMetadata: ColumnFieldMetadata
  disabled?: boolean
}

export type FileObject = {
  name: string
  type: string
  size: number
  url: string
  last_modified: string
}

export type FileFieldProps = {
  columnMetadata: ColumnFieldMetadata
  columnSchema: ColumnSchema
}

export type UploadProgress = {
  fileId: string
  progress: number
  completed: boolean
  error?: string
}
