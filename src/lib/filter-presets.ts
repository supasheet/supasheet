import { serializeColumnFilter } from "#/lib/data-table-parsers"
import type {
  ColumnFilterItem,
  FilterOperator as TableFilterOperator,
  FilterVariant,
} from "#/lib/data-table-types"
import { coerceFilterValue } from "#/lib/data-table-utils"
import type { FilterOperator, FilterRule } from "#/lib/database-meta.types"

const OPERATORS: Record<FilterOperator, TableFilterOperator> = {
  eq: "eq",
  neq: "ne",
  lt: "lt",
  lte: "lte",
  gt: "gt",
  gte: "gte",
  like: "iLike",
  ilike: "iLike",
  is: "isEmpty",
  in: "inArray",
  "not.ilike": "notILike",
  "not.is": "isNotEmpty",
  "not.in": "notInArray",
}

function toList(value: FilterRule["value"]) {
  return (Array.isArray(value) ? value : String(value).split(","))
    .map(String)
    .filter(Boolean)
}

/**
 * Converts a comment-JSON filter rule (PostgREST operator) into a data table
 * filter. `variants` maps column ids to their filter variant.
 */
export function ruleToFilterItem(
  rule: FilterRule,
  variants: Record<string, FilterVariant | undefined>,
  index: number
): ColumnFilterItem {
  const variant = variants[rule.id] ?? "text"
  const isBooleanIs =
    rule.operator === "is" && ["true", "false"].includes(String(rule.value))
  const operator = isBooleanIs ? "eq" : OPERATORS[rule.operator]
  const raw = Array.isArray(rule.value) ? rule.value : String(rule.value)

  return {
    id: rule.id,
    variant,
    operator,
    value: coerceFilterValue(
      operator,
      operator === "inArray" || operator === "notInArray" ? toList(raw) : raw
    ),
    filterId: `${rule.id}-${index}`,
  }
}

/**
 * Serializes rules into per-column URL search params for a data table route.
 * Operators are always written explicitly so the table can parse them with
 * its own column variants.
 */
export function rulesToSearch(rules: FilterRule[]) {
  const params: Record<string, string[]> = {}
  rules.forEach((rule, index) => {
    const item = ruleToFilterItem(rule, {}, index)
    params[rule.id] = [...(params[rule.id] ?? []), serializeColumnFilter(item)]
  })
  // A single value stays a plain string: the router writes arrays as JSON.
  return Object.fromEntries(
    Object.entries(params).map(([id, values]) => [
      id,
      values.length === 1 ? values[0] : values,
    ])
  )
}

export function getFiltersSignature(
  filters: Pick<ColumnFilterItem, "id" | "operator" | "value">[]
) {
  return filters
    .map(
      (filter) =>
        `${filter.id}|${filter.operator}|${[filter.value].flat().join(",")}`
    )
    .sort()
    .join("&")
}
