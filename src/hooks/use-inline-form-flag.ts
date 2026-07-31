import { useMemo } from "react"

import { useQuery } from "@tanstack/react-query"

import type { TableMetadata } from "#/lib/database-meta.types"
import { tableSchemaQueryOptions } from "#/lib/supabase/data/meta"

export function useInlineFormFlag(schema: string, resource: string) {
  const { data: tableSchema } = useQuery({
    ...tableSchemaQueryOptions(schema as never, resource as never),
    enabled: Boolean(schema && resource),
  })
  return useMemo(() => {
    try {
      const meta = JSON.parse(tableSchema?.comment ?? "{}") as TableMetadata
      return meta.inline_form === true
    } catch {
      return false
    }
  }, [tableSchema?.comment])
}
