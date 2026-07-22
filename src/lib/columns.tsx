import type { LucideIcon } from "lucide-react"
import {
  BaselineIcon,
  BinaryIcon,
  CalendarClockIcon,
  CalendarDaysIcon,
  ChevronDownIcon,
  ClockIcon,
  HashIcon,
  Link2Icon,
  LinkIcon,
  MailIcon,
  PaletteIcon,
  PaperclipIcon,
  PercentIcon,
  PhoneIcon,
  StarIcon,
  TimerIcon,
  ToggleLeftIcon,
  UserIcon,
} from "lucide-react"
import * as LucideIcons from "lucide-react"

import { getMetaFields, isTableSchema } from "#/lib/database-meta.types"
import type {
  ColumnMetadata,
  ColumnSchema,
  PrimaryKey,
  Relationship,
  TableSchema,
  ViewSchema,
} from "#/lib/database-meta.types"
import type { ColumnFieldMetadata } from "#/types/fields"

export const NUMERIC_TYPES = new Set([
  "integer",
  "bigint",
  "smallint",
  "numeric",
  "real",
  "double precision",
  "float",
  "float4",
  "float8",
  "int2",
  "int4",
  "int8",
])

export const TEMPORAL_TYPES = new Set([
  "timestamp with time zone",
  "timestamp without time zone",
  "timestamptz",
  "timestamp",
  "date",
  "time",
  "time with time zone",
  "time without time zone",
  "timetz",
  "interval",
])

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function coerceColumnValue(
  val: string,
  col: ColumnSchema | undefined
): unknown {
  if (!col) return val
  if (val === "") return null

  const type = col.data_type ?? ""
  const format = col.format ?? ""

  if (type === "boolean" || format === "bool") {
    const lower = val.toLowerCase()
    if (lower === "true" || lower === "yes" || val === "1") return true
    if (lower === "false" || lower === "no" || val === "0") return false
    return null
  }

  if (NUMERIC_TYPES.has(type) || NUMERIC_TYPES.has(format)) {
    const num = Number(val)
    return isNaN(num) ? null : num
  }

  if (TEMPORAL_TYPES.has(type)) {
    const d = new Date(val)
    return isNaN(d.getTime()) ? null : val
  }

  if (type === "uuid" || format === "uuid") {
    return UUID_RE.test(val) ? val : null
  }

  if (type === "json" || type === "jsonb") {
    try {
      return JSON.parse(val)
    } catch {
      return null
    }
  }

  const isArray =
    type.toUpperCase() === "ARRAY" ||
    type.startsWith("_") ||
    type.includes("[]") ||
    format.startsWith("_")
  if (isArray) {
    if (val.startsWith("{") && val.endsWith("}")) return val
    if (val.startsWith("[") && val.endsWith("]")) {
      try {
        return JSON.parse(val)
      } catch {
        /* fall through */
      }
    }
    return null
  }

  return val
}

export function getColumnCell(columnSchema: ColumnSchema) {
  switch (columnSchema.data_type) {
    case "json":
    case "jsonb":
      return "json"

    case "ARRAY":
      return "array"

    default:
      return "text"
  }
}

export function getColumnMetadata(
  tableSchema: TableSchema | ViewSchema | null,
  columnSchema = {} as ColumnSchema
): ColumnFieldMetadata {
  const commentMeta = JSON.parse(columnSchema.comment ?? "{}") as ColumnMetadata
  const commentIconName = commentMeta.icon as
    keyof typeof LucideIcons | undefined
  const ColumnIcon = commentIconName
    ? (LucideIcons[commentIconName] as LucideIcon | undefined)
    : undefined
  const columnIcon = ColumnIcon ? (
    <ColumnIcon className="size-4 shrink-0 text-muted-foreground" />
  ) : null

  const format = columnSchema.format?.startsWith("_")
    ? columnSchema.format?.slice(1)
    : columnSchema.format

  let defaultValue: string | null = null

  if (columnSchema.default_value === "NULL") {
    defaultValue = null
  } else if (columnSchema.default_value) {
    defaultValue = columnSchema.default_value
  } else {
    defaultValue = null
  }

  const name = commentMeta.name ?? columnSchema.name
  const required =
    columnSchema.is_nullable === false && !columnSchema.default_value
  const disabled = columnSchema.is_generated || !columnSchema.is_updatable
  const isArray = columnSchema.data_type === "ARRAY"
  const isMetadata = getMetaFields(tableSchema).includes(name)

  const isRelationship = !!(
    tableSchema &&
    isTableSchema(tableSchema) &&
    (tableSchema.relationships as Relationship[] | undefined)?.find(
      (r) => r.source_column_name === columnSchema.name
    )
  )

  const isPrimaryKey =
    tableSchema && isTableSchema(tableSchema)
      ? (tableSchema.primary_keys as PrimaryKey[])?.some(
          (key) =>
            key.name === columnSchema.name && key.schema === columnSchema.schema
        )
      : false

  const relationshipIcon = isRelationship ? (
    <Link2Icon className="size-4 shrink-0 text-muted-foreground" />
  ) : null

  const baseOptions = {
    name,
    description: commentMeta.description,
    defaultValue,
    disabled,
    required,
    isArray,
    isMetadata,
    isPrimaryKey,
    isRelationship,
    icon: columnIcon ?? relationshipIcon,
    comment: columnSchema.comment,
    table: columnSchema.table as string,
    schema: columnSchema.schema as string,
    options:
      (columnSchema.enums as string[])?.map((option) => ({
        label: option,
        value: option,
      })) ?? [],
  }

  if (format === "file") {
    return {
      ...baseOptions,
      isArray: false, // special case for file upload
      variant: "file",
      filterVariant: "text",
      icon: baseOptions.icon ?? (
        <PaperclipIcon className="size-4 shrink-0 text-muted-foreground" />
      ),
    }
  }

  if (format === "avatar") {
    return {
      ...baseOptions,
      variant: "avatar",
      filterVariant: "text",
      icon: baseOptions.icon ?? (
        <UserIcon className="size-4 shrink-0 text-muted-foreground" />
      ),
    }
  }

  if (columnSchema.data_type === "USER-DEFINED") {
    return {
      ...baseOptions,
      filterVariant: "multiSelect",
      variant: "select",
      icon: baseOptions.icon ?? (
        <ChevronDownIcon className="size-4 shrink-0 text-muted-foreground" />
      ),
    }
  }

  switch (format) {
    case "email":
      return {
        ...baseOptions,
        variant: "email",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <MailIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "tel":
      return {
        ...baseOptions,
        variant: "tel",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <PhoneIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "url":
      return {
        ...baseOptions,
        variant: "url",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <LinkIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "rating":
      return {
        ...baseOptions,
        variant: "rating",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <StarIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "percentage":
      return {
        ...baseOptions,
        variant: "percentage",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <PercentIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "color":
      return {
        ...baseOptions,
        variant: "color",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <PaletteIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "duration":
      return {
        ...baseOptions,
        variant: "duration",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <TimerIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "uuid":
      return {
        ...baseOptions,
        variant: "uuid",
        filterVariant: "uuid",
        icon: baseOptions.icon ?? (
          <HashIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "rich_text":
      return {
        ...baseOptions,
        variant: "rich_text",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <BaselineIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "character":
    case "varchar":
    case "bpchar":
      return {
        ...baseOptions,
        variant: "text",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">ab</code>
        ),
      }

    case "text":
      return {
        ...baseOptions,
        variant: "long_text",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">AB</code>
        ),
      }

    case "bit":
    case "varbit":
      return {
        ...baseOptions,
        variant: "text",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <BinaryIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "bytea":
      return {
        ...baseOptions,
        variant: "text",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">\x0</code>
        ),
      }

    case "double precision":
    case "decimal":
    case "numeric":
    case "real":
    case "float4":
    case "float8":
      return {
        ...baseOptions,
        variant: "number",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">1.23</code>
        ),
      }

    case "int8":
    case "bigint":
    case "bigserial":
      return {
        ...baseOptions,
        variant: "number",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">123</code>
        ),
      }

    case "int2":
    case "smallint":
    case "smallserial":
      return {
        ...baseOptions,
        variant: "number",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">123</code>
        ),
      }

    case "int4":
    case "integer":
    case "serial":
      return {
        ...baseOptions,
        variant: "number",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">123</code>
        ),
      }

    case "money":
      return {
        ...baseOptions,
        variant: "money",
        filterVariant: "number",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">$</code>
        ),
      }

    case "date":
      return {
        ...baseOptions,
        variant: "date",
        filterVariant: "date",
        icon: baseOptions.icon ?? (
          <CalendarDaysIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "time":
      return {
        ...baseOptions,
        variant: "time",
        filterVariant: "time",
        icon: baseOptions.icon ?? (
          <ClockIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "timetz":
      return {
        ...baseOptions,
        variant: "time",
        filterVariant: "timetz",
        icon: baseOptions.icon ?? (
          <ClockIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "timestamptz":
      return {
        ...baseOptions,
        variant: "datetime",
        filterVariant: "timestamptz",
        icon: baseOptions.icon ?? (
          <CalendarClockIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "timestamp":
      return {
        ...baseOptions,
        variant: "datetime",
        filterVariant: "timestamp",
        icon: baseOptions.icon ?? (
          <CalendarClockIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    case "json":
    case "jsonb":
      return {
        ...baseOptions,
        variant: "json",
        filterVariant: "text",
        icon: baseOptions.icon ?? (
          <code className="font-mono text-sm text-muted-foreground">{`{}`}</code>
        ),
      }

    case "bool":
      return {
        ...baseOptions,
        variant: "boolean",
        filterVariant: "boolean",
        icon: baseOptions.icon ?? (
          <ToggleLeftIcon className="size-4 shrink-0 text-muted-foreground" />
        ),
      }

    default:
      return {
        ...baseOptions,
        variant: "text",
        filterVariant: "text",
        icon: columnIcon,
      }
  }
}
