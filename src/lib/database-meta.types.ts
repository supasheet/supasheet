import { METADATA_COLUMNS } from "#/config/database.config"

import type { Database } from "./database.types"

export type ResourceDataSchema = Record<string, unknown>

export type DatabaseSchemas = keyof Database

export type DatabaseTables<TSchema extends DatabaseSchemas> =
  Database[TSchema] extends { Tables: infer TTables }
    ? TTables extends Record<string, unknown>
      ? keyof TTables & string
      : never
    : never
export type DatabaseViews<TSchema extends DatabaseSchemas> =
  Database[TSchema] extends { Views: infer TViews }
    ? TViews extends Record<string, unknown>
      ? keyof TViews & string
      : never
    : never

export type ColumnSchema<S extends DatabaseSchemas = DatabaseSchemas> =
  Database["supasheet"]["Views"]["columns"]["Row"] & {
    id: string
    name: string
    schema: S
    table: DatabaseTables<S> | DatabaseViews<S>
  }

export type TableSchema<S extends DatabaseSchemas = DatabaseSchemas> = Omit<
  Database["supasheet"]["Views"]["tables"]["Row"],
  "name" | "schema" | "relationships" | "primary_keys"
> & {
  id: number
  schema: S
  name: DatabaseTables<S>
  relationships: Relationship[] | null
  primary_keys: PrimaryKey[] | null
}

export type ViewSchema<S extends DatabaseSchemas = DatabaseSchemas> =
  Database["supasheet"]["Views"]["views"]["Row"] & {
    id: number
    schema: S
    name: DatabaseViews<S>
  }

export type ResourceSchema<S extends DatabaseSchemas = DatabaseSchemas> =
  | TableSchema<S>
  | ViewSchema<S>

export function isTableSchema<S extends DatabaseSchemas>(
  schema: ResourceSchema<S>
): schema is TableSchema<S> {
  return "primary_keys" in schema
}

export function getMetaFields(resourceSchema: ResourceSchema | null): string[] {
  if (!resourceSchema || !isTableSchema(resourceSchema)) return METADATA_COLUMNS
  const meta = resourceSchema.comment
    ? (JSON.parse(resourceSchema.comment) as TableMetadata)
    : {}
  return meta.fields?.metadata ?? METADATA_COLUMNS
}

export type PrimaryKey = {
  name: string
  schema: string
  table_id: number
  table_name: string
}

export type Relationship = {
  id: number
  source_schema: DatabaseSchemas
  constraint_name: string
  source_table_name: DatabaseTables<DatabaseSchemas>
  target_table_name: DatabaseTables<DatabaseSchemas>
  source_column_name: string
  target_column_name: string
  target_table_schema: DatabaseSchemas
}

export type PaginatedData<T> = {
  results: T[]
  total: number
  page: number
  perPage: number
}

export type FormMode = "create" | "update" | "read"

export type FieldCondition = {
  id: string
  operator: string // e.g. eq, neq, lt, lte, gt, gte, like, ilike, is, in, not.ilike, not.is, not.in
  value: string | string[]
}

export type FieldBehavior = {
  visible?: FieldCondition[] // shown when ALL conditions match
  required?: FieldCondition[] // required when ALL conditions match
  read_only?: FieldCondition[] // read-only when ALL conditions match
}

export type LookupFillRule = {
  target: string // local form field to populate
  source: string // column from the lookup target table
}

export type LookupFilterRule = {
  on: string // local field to watch
  column: string // lookup target column to match against
}

export type LookupConfig = {
  fill?: LookupFillRule[]
  filter?: LookupFilterRule[]
}

export type FieldSectionFields = string[] | Partial<Record<FormMode, string[]>>

export type FieldSection = {
  id: string
  title: string
  description?: string
  icon?: string
  fields: FieldSectionFields
  collapsible?: boolean
}

export type FilterRule = {
  id: string
  value: string | string[]
  operator: string
}

export type SortRule = {
  id: string
  desc: boolean
}

export type JoinClause = {
  table: string
  on: string
  alias?: string
  columns: string[]
}

export type QueryConfig = {
  sort?: SortRule[]
  filter?: FilterRule[]
  join?: JoinClause[]
  select?: string[]
}

type BaseViewLayout = {
  id: string
  name: string
  query?: Record<string, unknown>
}

export type KanbanLayout = BaseViewLayout & {
  type: "kanban"
  group?: string
  title?: string
  description?: string
  badge?: string
  date?: string
}

export type CalendarLayout = BaseViewLayout & {
  type: "calendar"
  title?: string
  start_date?: string
  end_date?: string
  badge?: string
}

export type GalleryLayout = BaseViewLayout & {
  type: "gallery"
  cover?: string
  title?: string
  description?: string
  badge?: string
}

export type ListLayout = BaseViewLayout & {
  type: "list"
  title?: string
  description?: string
  field_1?: string
  field_2?: string
}

export type TreeLayout = BaseViewLayout & {
  type: "tree"
  parent: string
  title: string
  secondary?: string
}

export type ViewLayout =
  | KanbanLayout
  | CalendarLayout
  | GalleryLayout
  | ListLayout
  | TreeLayout

export type ViewLayoutType = ViewLayout["type"]

export type FilterPreset = {
  id: string
  name: string
  description?: string
  icon?: string
  filters: FilterRule[]
}

// Valid for both tables and views
export type FieldsConfig = {
  sections?: FieldSection[]
  metadata?: string[]
}

// Table-only: includes form-specific options
export type TableFieldsConfig = FieldsConfig & {
  quick_create?: string[]
  duplicated?: string[]
  behavior?: Record<string, FieldBehavior>
  lookups?: Record<string, LookupConfig>
}

type BaseResourceMetadata = {
  display?: "block" | "none"
  name?: string
  description?: string
  icon?: string
  group?: string
  singleton?: boolean
  primary_view?: string
  views?: ViewLayout[]
  filter_presets?: FilterPreset[]
  fields?: FieldsConfig
}

export type TableMetadata = BaseResourceMetadata & {
  inline_form?: boolean
  query?: QueryConfig
  tabs?: string[]
  fields?: TableFieldsConfig
}

export type UpdatableViewMetadata = {
  based_on: DatabaseTables<DatabaseSchemas>
} & TableMetadata

export type ViewMetadata = BaseResourceMetadata

export type ColumnMetadata = {
  name?: string
  description?: string
  icon?: string
}

export type EnumColumnMetadata = ColumnMetadata & {
  progress?: boolean
  enums?: {
    [key: string]: {
      icon?: string
      variant:
        | "default"
        | "secondary"
        | "success"
        | "warning"
        | "destructive"
        | "info"
    }
  }
}

export type FileColumnMetadata = ColumnMetadata & {
  accept?: string
  maxFiles?: number
  maxSize?: number
}

export type AvatarColumnMetadata = ColumnMetadata & {
  maxSize?: number
}
