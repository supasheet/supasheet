import { getColumnMetadata } from "#/lib/columns"
import type {
  ColumnSchema,
  EnumColumnMetadata,
  FieldBehavior,
  FieldCondition,
  FieldSection,
  FieldSectionFields,
  FormMode,
  PrimaryKey,
  TableSchema,
} from "#/lib/database-meta.types"

export function isSkippedForUpdate(
  col: ColumnSchema,
  primaryKeys: PrimaryKey[]
): boolean {
  if (primaryKeys.some((pk) => pk.name === col.name)) return true
  return false
}

export function isSkippedForCreate(col: ColumnSchema): boolean {
  if (col.is_identity ?? false) return true
  return false
}

export function getUpdateInitialValue(
  col: ColumnSchema,
  record: Record<string, unknown>
): unknown {
  const val = record[col.name ?? col.id]
  if (val === null || val === undefined) return ""
  if (col.data_type === "ARRAY") return Array.isArray(val) ? val : []
  if (col.format === "json" || col.format === "jsonb") {
    return typeof val === "string" ? val : JSON.stringify(val, null, 2)
  }
  return val
}

export function getCreateInitialValue(col: ColumnSchema): unknown {
  if (col.data_type === "ARRAY") return []
  return ""
}

export function buildUpdatePayload(
  value: Record<string, unknown>,
  cols: ColumnSchema[],
  behavior?: Record<string, FieldBehavior>
): Record<string, unknown> {
  const payload: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(value)) {
    const visible = behavior?.[k]?.visible
    if (visible?.length && !evaluateConditionalField(visible, value)) {
      payload[k] = null
      continue
    }
    const col = cols.find((c) => (c.name ?? c.id) === k)
    if (v === "" || v === null || v === undefined) {
      payload[k] = null
    } else if (
      col &&
      (col.format === "json" || col.format === "jsonb") &&
      typeof v === "string"
    ) {
      try {
        payload[k] = JSON.parse(v)
      } catch {
        payload[k] = v
      }
    } else {
      payload[k] = v
    }
  }
  return payload
}

export function buildCreatePayload(
  value: Record<string, unknown>,
  cols: ColumnSchema[],
  behavior?: Record<string, FieldBehavior>
): Record<string, unknown> {
  const payload: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(value)) {
    const visible = behavior?.[k]?.visible
    if (visible?.length && !evaluateConditionalField(visible, value)) continue
    if (v === "" || v === null || v === undefined) continue
    const col = cols.find((c) => (c.name ?? c.id) === k)
    if (
      col &&
      (col.format === "json" || col.format === "jsonb") &&
      typeof v === "string"
    ) {
      try {
        payload[k] = JSON.parse(v)
      } catch {
        payload[k] = v
      }
    } else {
      payload[k] = v
    }
  }
  return payload
}

function toList(value: string | string[]): string[] {
  return Array.isArray(value)
    ? value.map((v) => String(v)).filter(Boolean)
    : value.split(",").filter(Boolean)
}

export function evaluateConditionalField(
  conditions: FieldCondition[],
  values: Record<string, unknown>
): boolean {
  return conditions.every((c) => {
    const fieldValue = values[c.id]
    const raw = String(fieldValue ?? "")
    const single = Array.isArray(c.value) ? (c.value[0] ?? "") : c.value
    const num = Number(raw)
    const compare = Number(single)
    switch (c.operator) {
      case "eq":
        return raw === single
      case "neq":
        return raw !== single
      case "lt":
        return num < compare
      case "lte":
        return num <= compare
      case "gt":
        return num > compare
      case "gte":
        return num >= compare
      case "like":
        return raw.toLowerCase().startsWith(single.toLowerCase())
      case "ilike":
        return raw.toLowerCase().includes(single.toLowerCase())
      case "not.ilike":
        return !raw.toLowerCase().includes(single.toLowerCase())
      case "in":
        return toList(c.value).includes(raw)
      case "not.in":
        return !toList(c.value).includes(raw)
      case "is":
        return fieldValue === null || fieldValue === undefined || raw === ""
      case "not.is":
        return fieldValue !== null && fieldValue !== undefined && raw !== ""
      default:
        return true
    }
  })
}

const FULL_WIDTH_VARIANTS = new Set(["rich_text", "long_text", "json"])

export function getColumnFieldSpan(
  col: ColumnSchema,
  tableSchema: TableSchema | null
): 1 | 2 {
  if (col.format === "file") return 2
  if (col.data_type === "ARRAY") return 2
  const meta = getColumnMetadata(tableSchema, col)
  if (FULL_WIDTH_VARIANTS.has(meta.variant)) return 2
  return 1
}

export type ProgressField = { col: ColumnSchema; meta: EnumColumnMetadata }

export function getProgressFields(cols: ColumnSchema[]): ProgressField[] {
  return cols
    .map((col) => {
      const meta = JSON.parse(col.comment ?? "{}") as EnumColumnMetadata
      if (!meta?.progress || !meta.enums) return null
      return { col, meta }
    })
    .filter((x): x is ProgressField => Boolean(x))
}

export function getSectionFields(
  fields: FieldSectionFields,
  mode: FormMode
): string[] {
  if (Array.isArray(fields)) return fields
  return fields[mode] ?? []
}

export type ResolvedFieldSection = Omit<FieldSection, "fields"> & {
  fields: string[]
}

export type LayoutPlan = {
  sections: ResolvedFieldSection[]
}

export function buildLayoutPlan(
  sectionsInput: FieldSection[] | undefined,
  availableNames: Set<string>,
  mode: FormMode
): LayoutPlan | null {
  if (!sectionsInput?.length) return null

  const seen = new Set<string>()
  const sections: ResolvedFieldSection[] = sectionsInput
    .map((s) => {
      const rawFields = getSectionFields(s.fields, mode)
      const fields: string[] = []
      for (const name of rawFields) {
        if (!availableNames.has(name)) {
          console.warn(
            `[layout] field "${name}" referenced in section "${s.id}" is not available in mode "${mode}"; skipping`
          )
          continue
        }
        if (seen.has(name)) {
          console.warn(
            `[layout] field "${name}" assigned to multiple sections; keeping first`
          )
          continue
        }
        seen.add(name)
        fields.push(name)
      }
      return { ...s, fields }
    })
    .filter((s) => s.fields.length > 0)

  if (!sections.length) return null

  return { sections }
}
