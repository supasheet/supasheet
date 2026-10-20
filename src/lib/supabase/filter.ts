import type {
  PostgrestClientOptions,
  PostgrestFilterBuilder,
} from "@supabase/postgrest-js"

import type { ColumnFiltersState } from "@tanstack/react-table"

import { decodeFilterValue } from "#/lib/data-table"

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

export function applyFilters<
  TClientOptions extends PostgrestClientOptions,
  TSchema extends GenericSchema,
  TRow extends Record<string, unknown>,
  TResult,
>(
  query: PostgrestFilterBuilder<TClientOptions, TSchema, TRow, TResult>,
  filters: ColumnFiltersState
): PostgrestFilterBuilder<TClientOptions, TSchema, TRow, TResult> {
  // Local alias so `as Q` casts resolve the polymorphic `this` return type
  type Q = PostgrestFilterBuilder<TClientOptions, TSchema, TRow, TResult>
  let q: Q = query

  for (const filter of filters) {
    const encoded = String(filter.value ?? "")
    if (!encoded) continue

    const { operator, value } = decodeFilterValue(encoded)
    const col = filter.id

    switch (operator) {
      case "ilike":
        q = q.filter(col, "ilike", `%${value}%`)
        break
      case "not.ilike":
        q = q.filter(col, "not.ilike", `%${value}%`)
        break
      case "like":
        q = q.filter(col, "like", `${value}%`)
        break
      case "is":
        q = q.filter(col, "is", null)
        break
      case "not.is":
        q = q.filter(col, "not.is", null)
        break
      case "in": {
        const values = value.split(",").filter(Boolean)
        if (values.length) q = q.filter(col, "in", `(${values.join(",")})`)
        break
      }
      case "not.in": {
        const values = value.split(",").filter(Boolean)
        if (values.length) q = q.filter(col, "not.in", `(${values.join(",")})`)
        break
      }
      default:
        if (value) q = q.filter(col, operator, value)
    }
  }

  return q
}
