import type {
  ColumnSchema,
  EnumColumnMetadata,
  PrimaryKey,
  ResourceDataSchema,
} from "./database-meta.types"

export function getPkValue(
  data: ResourceDataSchema,
  primaryKeys: PrimaryKey[]
): string {
  return String(data[primaryKeys[0]?.name] ?? "")
}

function getEnumsMeta(
  col: ColumnSchema | undefined
): EnumColumnMetadata["values"] | undefined {
  if (!col?.comment) return undefined
  try {
    return (JSON.parse(col.comment) as EnumColumnMetadata).values
  } catch {
    return undefined
  }
}

export function getEnumValues(col: ColumnSchema | undefined): string[] {
  if (!col) return []

  const enumsMeta = getEnumsMeta(col)
  if (enumsMeta) return Object.keys(enumsMeta)

  return (col.enums as string[] | null) ?? []
}

export type EnumBadgeMeta = NonNullable<EnumColumnMetadata["values"]>[string]

export function getEnumBadgeMetaMap(
  col: ColumnSchema | undefined
): Record<string, EnumBadgeMeta> {
  return getEnumsMeta(col) ?? {}
}
