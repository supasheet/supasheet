import type {
  ColumnSchema,
  PrimaryKey,
  Relationship,
  TableSchema,
} from "#/lib/database-meta.types"

export type RelatedTable = Omit<
  TableSchema,
  "columns" | "relationships" | "primary_keys"
> & {
  columns: ColumnSchema[]
  relationships: Relationship[]
  primary_keys: PrimaryKey[]
}

export type ManyRelation = RelatedTable & {
  __parentColumn: string
  __targetColumn: string
  __selectClause: string
}

export type OneToOneRelation = RelatedTable & {
  __fkColumn: string
  __foreignMatchColumn: string
  __parentMatchColumn: string
}

export type ClassifiedRelationships = {
  oneToOne: OneToOneRelation | undefined
  oneToMany: ManyRelation | undefined
  manyToMany: ManyRelation | undefined
}

export function classifyRelationships(
  schema: string,
  resource: string,
  tableSchema: TableSchema,
  columnsSchema: ColumnSchema[]
): ClassifiedRelationships {
  const table = {
    ...tableSchema,
    columns: columnsSchema ?? [],
    relationships: tableSchema.relationships ?? [],
    primary_keys: tableSchema.primary_keys ?? [],
  } as RelatedTable

  const oneToOneAsSource = table.relationships.find(
    (rel) => rel.source_schema === schema && rel.source_table_name === resource
  )
  if (oneToOneAsSource) {
    return {
      oneToOne: {
        ...table,
        __fkColumn: oneToOneAsSource.source_column_name,
        __foreignMatchColumn: oneToOneAsSource.target_column_name,
        __parentMatchColumn: oneToOneAsSource.source_column_name,
      },
      oneToMany: undefined,
      manyToMany: undefined,
    }
  }

  const oneToOneAsTarget = table.relationships.find(
    (rel) =>
      rel.target_table_schema === schema &&
      rel.target_table_name === resource &&
      (table.columns
        .filter((col) => col.is_unique)
        .some((col) => col.name === rel.source_column_name) ||
        (table.primary_keys.some(
          (key) => key.name === rel.source_column_name
        ) &&
          table.primary_keys.length === 1))
  )
  if (oneToOneAsTarget) {
    return {
      oneToOne: {
        ...table,
        __fkColumn: oneToOneAsTarget.source_column_name,
        __foreignMatchColumn: oneToOneAsTarget.source_column_name,
        __parentMatchColumn: oneToOneAsTarget.target_column_name,
      },
      oneToMany: undefined,
      manyToMany: undefined,
    }
  }

  const m2mRel = table.relationships.find(
    (rel) =>
      rel.target_table_schema === schema &&
      rel.target_table_name === resource &&
      table.relationships.length >= 2 &&
      table.primary_keys.length >= 2 &&
      table.primary_keys.some((key) => key.name === rel.source_column_name)
  )
  if (m2mRel) {
    const otherRel = table.relationships.find(
      (r) =>
        table.primary_keys.some((k) => k.name === r.source_column_name) &&
        !(r.target_table_schema === schema && r.target_table_name === resource)
    )
    return {
      oneToOne: undefined,
      oneToMany: undefined,
      manyToMany: {
        ...table,
        __parentColumn: m2mRel.source_column_name,
        __targetColumn: m2mRel.target_column_name,
        __selectClause: otherRel
          ? `*, ...${otherRel.target_table_name}(*)`
          : "*",
      },
    }
  }

  const oneToManyRel = table.relationships.find(
    (rel) =>
      rel.target_table_schema === schema &&
      rel.target_table_name === resource &&
      !(
        table.columns
          .filter((col) => col.is_unique)
          .some((col) => col.name === rel.source_column_name) ||
        table.primary_keys.some((key) => key.name === rel.source_column_name)
      )
  )

  return {
    oneToOne: undefined,
    manyToMany: undefined,
    oneToMany: oneToManyRel
      ? {
          ...table,
          __parentColumn: oneToManyRel.source_column_name,
          __targetColumn: oneToManyRel.target_column_name,
          __selectClause: "*",
        }
      : undefined,
  }
}
