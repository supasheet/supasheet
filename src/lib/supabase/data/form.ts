import { mutationOptions, queryOptions } from "@tanstack/react-query"

import type {
  ColumnSchema,
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
} from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"

export type ResourceFormRow<S extends DatabaseSchemas = DatabaseSchemas> = {
  schema: S
  name: string
  arguments: string
  comment: string | null
}

export const resourceFormsQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  resource: DatabaseTables<S> | DatabaseViews<S>
) =>
  queryOptions({
    queryKey: ["supasheet", "resource-forms", schema, resource],
    queryFn: async () => {
      const args: { p_schema: string; p_resource: string } = {
        p_schema: schema,
        p_resource: resource,
      }
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_forms", args)
      if (error) throw error
      return (data ?? []) as unknown as ResourceFormRow<S>[]
    },
    staleTime: 1000 * 60 * 5,
  })

export const resourceFormFieldsQueryOptions = <S extends DatabaseSchemas>(
  schema: S,
  functionName: string
) =>
  queryOptions({
    queryKey: ["supasheet", "schema", "form-fields", schema, functionName],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_form_fields", {
          p_schema: schema,
          p_function_name: functionName,
        })
      if (error) throw error
      return (data as unknown as ColumnSchema<S>[]) ?? []
    },
    staleTime: 1000 * 60 * 5,
  })

export const runResourceFormMutationOptions = () =>
  mutationOptions({
    mutationFn: async ({
      schema,
      functionName,
      params,
    }: {
      schema: DatabaseSchemas
      functionName: string
      params: Record<string, unknown>
    }) => {
      const { data, error } = await supabase
        .schema(schema)
        .rpc(functionName as never, params as never)
      if (error) throw error
      return data
    },
  })
