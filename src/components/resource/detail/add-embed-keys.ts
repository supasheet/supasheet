import type { TableMetadata, TableSchema } from "#/lib/database-meta.types"

import type { RelatedTable } from "./classify-relationships"

export type EmbeddedRelatedTable = Omit<RelatedTable, "columns"> & {
  __embedKey: string
}

export function addEmbedKeys(
  schema: string,
  resource: string,
  relatedTablesSchema: TableSchema[] | never[],
  metaJoins?: Required<TableMetadata>["query"]["join"]
): EmbeddedRelatedTable[] {
  const resolveAlias = (table: string, column: string) =>
    metaJoins?.find((j) => j.table === table && j.on === column)?.alias ?? table
  const tables = (relatedTablesSchema ?? []) as Omit<RelatedTable, "columns">[]

  const embeddedTables: EmbeddedRelatedTable[] = []

  for (const table of tables) {
    const rels = (table.relationships ?? []).filter(
      (rel) =>
        (rel.source_schema === schema && rel.source_table_name === resource) ||
        (rel.target_table_schema === schema &&
          rel.target_table_name === resource)
    )

    const hasRels = rels.filter(
      (rel) =>
        !(rel.source_schema === schema && rel.source_table_name === resource)
    )

    for (const rel of rels) {
      const isSource =
        rel.source_schema === schema && rel.source_table_name === resource
      const embedKey = isSource
        ? resolveAlias(rel.target_table_name, rel.source_column_name)
        : hasRels.length > 1
          ? `${rel.source_table_name}_${rel.source_column_name}`
          : rel.source_table_name
      embeddedTables.push({ ...table, __embedKey: embedKey })
    }
  }

  return embeddedTables
}
