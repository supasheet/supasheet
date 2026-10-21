import {
  parseColumnFilter,
  getSortingStateParser,
} from "#/lib/data-table-parsers"
import type {
  ColumnFilterItem,
  ColumnSortItem,
  FilterVariant,
  JoinOperator,
} from "#/lib/data-table-types"
import { getIsActiveFilter, JOIN_OPERATORS } from "#/lib/data-table-utils"

export const DEFAULT_PAGE_SIZE = 20
export const DEFAULT_PAGINATION = { pageIndex: 0, pageSize: DEFAULT_PAGE_SIZE }

export type TableQuery = {
  page: number
  perPage: number
  sorting: ColumnSortItem[]
  filters: ColumnFilterItem[]
  joinOperator: JoinOperator
}

export type TableSearch = Record<string, unknown>

const sortingParser = getSortingStateParser()

function toStrings(value: unknown): string[] {
  if (value === undefined || value === null) return []
  return (Array.isArray(value) ? value : [value]).map((item) =>
    typeof item === "object" ? JSON.stringify(item) : String(item)
  )
}

function toPositiveInt(value: unknown, fallback: number) {
  const parsed = Number.parseInt(String(value ?? ""), 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
}

/**
 * Validator for routes that host a data table. The table state lives in the
 * URL (via nuqs), so the route keeps every search key as-is and the loader
 * derives the query from it with `getTableQuery`.
 */
export function validateTableSearch(search: Record<string, unknown>) {
  return search as TableSearch
}

/**
 * Turns the URL search params written by `useDataTable` into a query. The
 * per-column filter params need each filterable column's variant to parse.
 */
export function getTableQuery(
  search: TableSearch,
  filterVariants: Record<string, FilterVariant>,
  defaultPerPage = DEFAULT_PAGE_SIZE
): TableQuery {
  const sorting = sortingParser.parse(toStrings(search.sort)[0] ?? "") ?? []

  const joinOperator = JOIN_OPERATORS.find((op) => op === search.joinOperator)

  const filters = Object.entries(filterVariants).flatMap(([id, variant]) =>
    toStrings(search[id])
      .map((param, index) => ({
        ...parseColumnFilter(id, variant, param),
        filterId: `${id}-${index}`,
      }))
      .filter(getIsActiveFilter)
  )

  return {
    page: toPositiveInt(search.page, 1),
    perPage: toPositiveInt(search.perPage, defaultPerPage),
    sorting,
    filters,
    joinOperator: joinOperator ?? "and",
  }
}
