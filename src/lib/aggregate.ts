import type { AggregateFunction } from "#/lib/database-meta.types"
import type { ColumnFieldMetadata } from "#/types/fields"

export const AGGREGATE_FUNCTION_LABELS: Record<AggregateFunction, string> = {
  none: "None",
  count: "Count",
  count_distinct: "Count unique",
  sum: "Sum",
  avg: "Average",
  min: "Min",
  max: "Max",
}

const NUMERIC_VARIANTS = new Set<ColumnFieldMetadata["variant"]>([
  "number",
  "money",
  "percentage",
  "duration",
  "rating",
])

const COMPARABLE_VARIANTS = new Set<ColumnFieldMetadata["variant"]>([
  ...NUMERIC_VARIANTS,
  "date",
  "datetime",
  "time",
])

export function getAvailableAggregates(
  variant: ColumnFieldMetadata["variant"]
): AggregateFunction[] {
  const fns: AggregateFunction[] = ["none", "count", "count_distinct"]
  if (COMPARABLE_VARIANTS.has(variant)) fns.push("min", "max")
  if (NUMERIC_VARIANTS.has(variant)) fns.push("sum", "avg")
  return fns
}

function toNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null
  const num = typeof value === "number" ? value : Number(value)
  return Number.isFinite(num) ? num : null
}

export function computeAggregate(
  values: unknown[],
  fn: AggregateFunction,
  variant: ColumnFieldMetadata["variant"]
): number | string | null {
  if (fn === "none") return null

  const nonNull = values.filter((v) => v !== null && v !== undefined && v !== "")

  if (fn === "count") return nonNull.length
  if (fn === "count_distinct")
    return new Set(nonNull.map((v) => String(v))).size

  if (!nonNull.length) return null

  if (fn === "min" || fn === "max") {
    if (variant === "date" || variant === "datetime" || variant === "time") {
      const times = nonNull
        .map((v) => new Date(v as string).getTime())
        .filter((t) => !isNaN(t))
      if (!times.length) return null
      const t = fn === "min" ? Math.min(...times) : Math.max(...times)
      return new Date(t).toLocaleString()
    }
    const nums = nonNull.map(toNumber).filter((n): n is number => n !== null)
    if (!nums.length) return null
    return fn === "min" ? Math.min(...nums) : Math.max(...nums)
  }

  const nums = nonNull.map(toNumber).filter((n): n is number => n !== null)
  if (!nums.length) return null

  if (fn === "sum") return nums.reduce((a, b) => a + b, 0)
  return nums.reduce((a, b) => a + b, 0) / nums.length // avg
}

export function formatAggregateValue(value: number | string | null): string {
  if (value === null) return ""
  if (typeof value === "string") return value
  return Number.isInteger(value)
    ? value.toLocaleString()
    : value.toLocaleString(undefined, { maximumFractionDigits: 2 })
}
