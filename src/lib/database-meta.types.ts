import type * as LucideIcons from "lucide-react"
import type { LucideIcon } from "lucide-react"

import { METADATA_COLUMNS } from "#/config/database.config"

import type { Database } from "./database.types"

export type ResourceDataSchema = Record<string, unknown>

export type DatabaseSchemas = keyof Database

export type ColumnName = string

export type TableAlias = string

// PascalCase names of Lucide icon components, as authored in metadata JSON
// `icon` fields (e.g. "Activity", "AlertCircle") and looked up against
// `lucide-react`'s exports at render time.
export type IconName = {
  [K in keyof typeof LucideIcons]: (typeof LucideIcons)[K] extends LucideIcon
    ? K
    : never
}[keyof typeof LucideIcons]

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
    name: ColumnName
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
  TableSchema<S> | ViewSchema<S>

export function isTableSchema<S extends DatabaseSchemas>(
  schema: ResourceSchema<S>
): schema is TableSchema<S> {
  return "primary_keys" in schema
}

export function getMetaFields(
  resourceSchema: ResourceSchema | null
): ColumnName[] {
  if (!resourceSchema || !isTableSchema(resourceSchema)) return METADATA_COLUMNS
  const meta = resourceSchema.comment
    ? (JSON.parse(resourceSchema.comment) as TableMetadata)
    : {}
  return meta.fields?.metadata ?? METADATA_COLUMNS
}

export type PrimaryKey = {
  name: ColumnName
  schema: DatabaseSchemas
  table_id: number
  table_name: DatabaseTables<DatabaseSchemas>
}

export type Relationship = {
  id: number
  constraint_name: string
  source_schema: DatabaseSchemas
  source_table_name: DatabaseTables<DatabaseSchemas>
  source_column_name: ColumnName
  target_table_schema: DatabaseSchemas
  target_table_name: DatabaseTables<DatabaseSchemas>
  target_column_name: ColumnName
}

export type PaginatedData<T> = {
  results: T[]
  total: number
  page: number
  perPage: number
}

export type FormMode = "create" | "update" | "read"

export type FieldCondition = {
  id: ColumnName
  operator: string // e.g. eq, neq, lt, lte, gt, gte, like, ilike, is, in, not.ilike, not.is, not.in
  value: string | string[]
}

export type FieldBehavior = {
  visible?: FieldCondition[] // shown when ALL conditions match
  required?: FieldCondition[] // required when ALL conditions match
  read_only?: FieldCondition[] // read-only when ALL conditions match
}

export type LookupFillRule = {
  target: ColumnName // local form field to populate
  source: ColumnName // column from the lookup target table
}

export type LookupFilterRule = {
  on: ColumnName // local field to watch
  column: ColumnName // lookup target column to match against
}

export type LookupConfig = {
  fill?: LookupFillRule[]
  filter?: LookupFilterRule[]
}

export type FieldSectionFields =
  ColumnName[] | Partial<Record<FormMode, ColumnName[]>>

export type FieldSection = {
  id: string
  title: string
  description?: string
  icon?: IconName
  fields: FieldSectionFields
  collapsible?: boolean
}

export type FilterRule = {
  id: ColumnName
  value: string | string[]
  operator: string
}

export type SortRule = {
  id: ColumnName
  desc: boolean
}

export type JoinClause = {
  table: string
  on: string
  alias?: TableAlias
  columns: ColumnName[]
}

export type QueryConfig = {
  sort?: SortRule[]
  filter?: FilterRule[]
  join?: JoinClause[]
  select?: ColumnName[]
}

type BaseViewLayout = {
  id: string
  name: string
  query?: Record<string, unknown>
}

export type KanbanLayout = BaseViewLayout & {
  type: "kanban"
  group?: ColumnName
  title?: ColumnName
  description?: ColumnName
  badge?: ColumnName
  date?: ColumnName
}

export type CalendarLayout = BaseViewLayout & {
  type: "calendar"
  title?: ColumnName
  start_date?: ColumnName
  end_date?: ColumnName
  badge?: ColumnName
}

export type GalleryLayout = BaseViewLayout & {
  type: "gallery"
  cover?: ColumnName
  title?: ColumnName
  description?: ColumnName
  badge?: ColumnName
}

export type ListLayout = BaseViewLayout & {
  type: "list"
  title?: ColumnName
  description?: ColumnName
  field_1?: ColumnName
  field_2?: ColumnName
}

export type TreeLayout = BaseViewLayout & {
  type: "tree"
  parent: ColumnName
  title: ColumnName
  secondary?: ColumnName
}

export type ViewLayout =
  KanbanLayout | CalendarLayout | GalleryLayout | ListLayout | TreeLayout

export type ViewLayoutType = ViewLayout["type"]

export type DetailHeaderMeta = {
  title?: ColumnName
  badges?: ColumnName[]
}

export type FilterPreset = {
  id: string
  name: string
  description?: string
  icon?: IconName
  filters: FilterRule[]
}

// Valid for both tables and views
export type FieldsConfig = {
  sections?: FieldSection[]
  metadata?: ColumnName[]
}

// Table-only: includes form-specific options
export type TableFieldsConfig = FieldsConfig & {
  quick_create?: ColumnName[]
  duplicated?: ColumnName[]
  behavior?: Record<ColumnName, FieldBehavior>
  lookups?: Record<ColumnName, LookupConfig>
}

type BaseResourceMetadata = {
  display?: "block" | "none"
  name?: string
  description?: string
  icon?: IconName
  group?: string
  singleton?: boolean
  primary_view?: string
  views?: ViewLayout[]
  filter_presets?: FilterPreset[]
  fields?: FieldsConfig
  detail?: DetailHeaderMeta
}

export type TableMetadata = BaseResourceMetadata & {
  inline_form?: boolean
  query?: QueryConfig
  tabs?: TableAlias[]
  fields?: TableFieldsConfig
}

export type ViewMetadata = BaseResourceMetadata

export type DashboardWidgetType =
  "card_1"
  | "card_2"
  | "card_3"
  | "card_4"
  | "card_5"
  | "card_6"
  | "table_1"
  | "table_2"
  | "list_1"
  | "list_2"
  | "list_3"
  | "list_4"

export type DashboardWidgetMeta = {
  name: string
  description?: string
  caption?: string
  type: "dashboard_widget"
  widget_type: DashboardWidgetType
  resource?: string
  link?: string
}

export type ChartType = "area" | "pie" | "line" | "radar" | "bar"

export type ChartMeta = {
  name: string
  description?: string
  caption?: string
  type: "chart"
  chart_type: ChartType
  resource?: string
}

export type ColumnMetadata = {
  name?: string
  description?: string
  icon?: IconName
}

export type EnumColumnMetadata = ColumnMetadata & {
  progress?: boolean
  iconOnly?: boolean
  enums?: {
    [key: string]: {
      icon?: IconName
      variant:
        "default" | "secondary" | "success" | "warning" | "destructive" | "info"
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
