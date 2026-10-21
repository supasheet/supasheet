import type {
  PostgrestClientOptions,
  PostgrestFilterBuilder,
} from "@supabase/postgrest-js"

import { UUID_RE } from "#/lib/columns"
import type { ColumnFilterItem, JoinOperator } from "#/lib/data-table-types"
import type { FilterRule } from "#/lib/database-meta.types"

// Structural mirrors of unexported types from @supabase/postgrest-js.
// These must stay in sync with GenericRelationship / GenericSchema in that package.
type GenericRelationship = {
  foreignKeyName: string
  columns: string[]
  isOneToOne?: boolean
  referencedRelation: string
  referencedColumns: string[]
}

type GenericTable = {
  Row: Record<string, unknown>
  Insert: Record<string, unknown>
  Update: Record<string, unknown>
  Relationships: GenericRelationship[]
}

type GenericView =
  | { Row: Record<string, unknown>; Relationships: GenericRelationship[] }
  | {
      Row: Record<string, unknown>
      Insert: Record<string, unknown>
      Update: Record<string, unknown>
      Relationships: GenericRelationship[]
    }

type GenericFunction = {
  Args: Record<string, unknown> | never
  Returns: unknown
  SetofOptions?: {
    isSetofReturn?: boolean
    isOneToOne?: boolean
    isNotNullable?: boolean
    to: string
    from: string
  }
}

type GenericSchema = {
  Tables: Record<string, GenericTable>
  Views: Record<string, GenericView>
  Functions: Record<string, GenericFunction>
}

type Q<
  TClientOptions extends PostgrestClientOptions,
  TSchema extends GenericSchema,
  TRow extends Record<string, unknown>,
  TResult,
> = PostgrestFilterBuilder<TClientOptions, TSchema, TRow, TResult>

function quote(value: string) {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
}

function clause(col: string, op: string, value: string) {
  return `${col}.${op}.${quote(value)}`
}

function list(col: string, op: "in" | "not.in", values: string[]) {
  return `${col}.${op}.(${values.map(quote).join(",")})`
}

function nullClause(col: string, negate: boolean) {
  return `${col}.${negate ? "not.is" : "is"}.null`
}

function combine(op: "and" | "or", clauses: string[]) {
  return clauses.length === 1 ? clauses[0] : `${op}(${clauses.join(",")})`
}

function ymd(date: Date) {
  const month = String(date.getUTCMonth() + 1).padStart(2, "0")
  const day = String(date.getUTCDate()).padStart(2, "0")
  return `${date.getUTCFullYear()}-${month}-${day}`
}

function addDays(value: string, days: number) {
  const [year, month, day] = value.split("-").map(Number)
  return ymd(new Date(Date.UTC(year, month - 1, day + days)))
}

function relativeRange(value: string): [string, string] | null {
  const [amountRaw, unit] = value.split(" ")
  const amount = Number.parseInt(amountRaw ?? "", 10)
  if (Number.isNaN(amount)) return null

  const days =
    unit === "days" ? 1 : unit === "weeks" ? 7 : unit === "months" ? 30 : 0
  if (!days) return null

  const now = new Date()
  const today = ymd(
    new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()))
  )
  const start = addDays(today, amount * days)
  return [start, addDays(start, days)]
}

/**
 * Date filters hold calendar dates (`yyyy-mm-dd`). They are sent as plain
 * dates, with day boundaries as half-open ranges, so the same filter works
 * for `date` and `timestamp(tz)` columns.
 */
function dateExpression(item: ColumnFilterItem): string | null {
  const { id: col, operator } = item
  const [first, second] = Array.isArray(item.value) ? item.value : [item.value]

  if (operator === "isRelativeToToday") {
    const range = relativeRange(first ?? "")
    if (!range) return null
    return combine("and", [
      clause(col, "gte", range[0]),
      clause(col, "lt", range[1]),
    ])
  }

  if (!first) return null
  const end = addDays(first, 1)

  switch (operator) {
    case "eq":
      return combine("and", [clause(col, "gte", first), clause(col, "lt", end)])
    case "ne":
      return combine("or", [clause(col, "lt", first), clause(col, "gte", end)])
    case "lt":
      return clause(col, "lt", first)
    case "lte":
      return clause(col, "lt", end)
    case "gt":
      return clause(col, "gte", end)
    case "gte":
      return clause(col, "gte", first)
    case "isBetween": {
      if (!second) return clause(col, "gte", first)
      return combine("and", [
        clause(col, "gte", first),
        clause(col, "lt", addDays(second, 1)),
      ])
    }
    default:
      return null
  }
}

/** Builds one PostgREST filter expression for a data table filter. */
function filterExpression(item: ColumnFilterItem): string | null {
  const { id: col, operator, variant } = item
  const values = Array.isArray(item.value) ? item.value : [item.value]
  const first = values[0] ?? ""

  if (operator === "isEmpty") {
    return variant === "text"
      ? combine("or", [nullClause(col, false), clause(col, "eq", "")])
      : nullClause(col, false)
  }
  if (operator === "isNotEmpty") {
    return variant === "text"
      ? combine("and", [nullClause(col, true), clause(col, "neq", "")])
      : nullClause(col, true)
  }

  if (variant === "date" || variant === "dateRange") return dateExpression(item)

  // A partial or malformed uuid can't be cast by Postgres, so it matches nothing
  // for "is" and everything for "is not" instead of raising an error.
  if (variant === "uuid" && first && !UUID_RE.test(first)) {
    return operator === "eq"
      ? combine("and", [nullClause(col, false), nullClause(col, true)])
      : null
  }

  switch (operator) {
    case "iLike":
      return first ? clause(col, "ilike", `*${first}*`) : null
    case "notILike":
      return first ? clause(col, "not.ilike", `*${first}*`) : null
    case "eq":
      return first ? clause(col, "eq", first) : null
    case "ne":
      return first ? clause(col, "neq", first) : null
    case "lt":
    case "lte":
    case "gt":
    case "gte":
      return first ? clause(col, operator, first) : null
    case "inArray": {
      const list_ = values.filter(Boolean)
      return list_.length ? list(col, "in", list_) : null
    }
    case "notInArray": {
      const list_ = values.filter(Boolean)
      return list_.length ? list(col, "not.in", list_) : null
    }
    case "isBetween": {
      const [min, max] = values
      const clauses = [
        ...(min ? [clause(col, "gte", min)] : []),
        ...(max ? [clause(col, "lte", max)] : []),
      ]
      return clauses.length ? combine("and", clauses) : null
    }
    default:
      return null
  }
}

/** Builds one PostgREST filter expression for a comment-JSON filter rule. */
function ruleExpression(rule: FilterRule): string | null {
  const col = rule.id
  const values = Array.isArray(rule.value) ? rule.value : [rule.value]
  const first = values[0] ?? ""

  switch (rule.operator) {
    case "ilike":
      return clause(col, "ilike", `*${first}*`)
    case "not.ilike":
      return clause(col, "not.ilike", `*${first}*`)
    case "like":
      return clause(col, "like", `${first}*`)
    case "is":
      return nullClause(col, false)
    case "not.is":
      return nullClause(col, true)
    case "in":
    case "not.in": {
      const list_ = values.flatMap((v) => String(v).split(",")).filter(Boolean)
      return list_.length ? list(col, rule.operator, list_) : null
    }
    default:
      return first ? clause(col, rule.operator, String(first)) : null
  }
}

function applyExpressions<
  TClientOptions extends PostgrestClientOptions,
  TSchema extends GenericSchema,
  TRow extends Record<string, unknown>,
  TResult,
>(
  query: Q<TClientOptions, TSchema, TRow, TResult>,
  expressions: string[],
  join: JoinOperator
): Q<TClientOptions, TSchema, TRow, TResult> {
  if (!expressions.length) return query
  // `or=(...)` with a single entry is a plain filter, so successive calls AND.
  if (join === "or") return query.or(expressions.join(","))
  return expressions.reduce((q, expression) => q.or(expression), query)
}

export function applyFilters<
  TClientOptions extends PostgrestClientOptions,
  TSchema extends GenericSchema,
  TRow extends Record<string, unknown>,
  TResult,
>(
  query: Q<TClientOptions, TSchema, TRow, TResult>,
  filters: ColumnFilterItem[],
  joinOperator: JoinOperator = "and"
): Q<TClientOptions, TSchema, TRow, TResult> {
  const expressions = filters.flatMap((filter) => {
    const expression = filterExpression(filter)
    return expression ? [expression] : []
  })
  return applyExpressions(query, expressions, joinOperator)
}

/** Applies the always-on filter rules from table/view metadata (AND-ed). */
export function applyFilterRules<
  TClientOptions extends PostgrestClientOptions,
  TSchema extends GenericSchema,
  TRow extends Record<string, unknown>,
  TResult,
>(
  query: Q<TClientOptions, TSchema, TRow, TResult>,
  rules: FilterRule[]
): Q<TClientOptions, TSchema, TRow, TResult> {
  const expressions = rules.flatMap((rule) => {
    const expression = ruleExpression(rule)
    return expression ? [expression] : []
  })
  return applyExpressions(query, expressions, "and")
}
