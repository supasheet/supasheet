import * as LucideIcons from "lucide-react"
import type { LucideIcon } from "lucide-react"

import type {
  ColumnMetadata,
  ColumnSchema,
  Relationship,
} from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"

export interface LinkedResource {
  schema: string
  name: string
  label: string
}

export interface FieldRow {
  id: string
  name: string
  label: string
  description?: string
  icon?: string
  type: string
  required: boolean
  unique: boolean
  isIdentifier: boolean
  enumValues: string[]
  linkedTo?: LinkedResource
}

export interface DynamicIconProps {
  iconName?: string
  className?: string
}

export function DynamicIcon({ iconName, className }: DynamicIconProps) {
  if (!iconName) return null
  const Icon = LucideIcons[iconName as keyof typeof LucideIcons] as
    LucideIcon | undefined
  if (!Icon) return null
  return <Icon className={className ?? "size-4 shrink-0"} />
}

const FRIENDLY_FORMAT_MAP: Record<string, string> = {
  text: "Text",
  varchar: "Text",
  bpchar: "Text",
  citext: "Text",
  name: "Text",
  uuid: "ID",
  int2: "Number",
  int4: "Number",
  int8: "Number",
  numeric: "Number",
  float4: "Number",
  float8: "Number",
  money: "Currency",
  bool: "Yes / No",
  date: "Date",
  time: "Time",
  timetz: "Time",
  timestamp: "Date & time",
  timestamptz: "Date & time",
  interval: "Duration",
  json: "Structured data",
  jsonb: "Structured data",
  bytea: "Binary",
  inet: "IP address",
  cidr: "IP address",
}

export function parseColumnMeta(comment: string | null): ColumnMetadata {
  if (!comment) return {}
  try {
    return JSON.parse(comment) as ColumnMetadata
  } catch {
    return {}
  }
}

export function friendlyType(column: ColumnSchema, isLinked: boolean): string {
  if (isLinked) return "Linked record"
  if (column.data_type === "ARRAY") return "List"
  if (column.data_type === "USER-DEFINED") return "Choice"
  if (column.format && FRIENDLY_FORMAT_MAP[column.format])
    return FRIENDLY_FORMAT_MAP[column.format]
  if (column.data_type) return formatTitle(column.data_type)
  return "Text"
}

export function buildFieldRow(
  column: ColumnSchema,
  linkedRel: Relationship | undefined,
  primaryKeyNames: Set<string>
): FieldRow | null {
  const meta = parseColumnMeta(column.comment)
  if (meta.name === "") return null
  const name = column.name ?? ""
  const isLinked = !!linkedRel
  const enumValues = Array.isArray(column.enums)
    ? (column.enums as string[])
    : []
  return {
    id: column.id,
    name,
    label: meta.name ?? formatTitle(name),
    description: meta.description,
    icon: meta.icon,
    type: friendlyType(column, isLinked),
    required: !column.is_nullable,
    unique: !!column.is_unique,
    isIdentifier: primaryKeyNames.has(name),
    enumValues,
    linkedTo: linkedRel
      ? {
          schema: linkedRel.target_table_schema,
          name: linkedRel.target_table_name,
          label: formatTitle(linkedRel.target_table_name),
        }
      : undefined,
  }
}
