import { useRouterState } from "@tanstack/react-router"

import { useQuery } from "@tanstack/react-query"

import type { DatabaseSchemas } from "#/lib/database-meta.types"
import type { AppPermission, AppRole } from "#/lib/supabase/data/core"
import {
  hasRoleQueryOptions,
  userPermissionsQueryOptions,
} from "#/lib/supabase/data/core"

type PermissionRow = { permission: AppPermission }

function usePermissions(): PermissionRow[] | null {
  return useRouterState({
    select: (s) => {
      const match = s.matches.find((m) => "permissions" in (m.context ?? {}))
      return (
        (match?.context as { permissions?: PermissionRow[] | null })
          ?.permissions ?? null
      )
    },
  })
}

function getSchema(
  permission: AppPermission | undefined
): DatabaseSchemas | undefined {
  return permission?.split(".")[0] as DatabaseSchemas | undefined
}

export function useHasPermission(
  permission: AppPermission | undefined
): boolean {
  const contextPermissions = usePermissions()
  const targetSchema = getSchema(permission)
  const activeSchema = getSchema(contextPermissions?.[0]?.permission)
  const isActiveSchema = !!targetSchema && targetSchema === activeSchema

  const { data: fetchedPermissions } = useQuery({
    ...userPermissionsQueryOptions(targetSchema),
    enabled: !!permission && !isActiveSchema,
  })

  if (!permission) return false
  const permissions = isActiveSchema ? contextPermissions : fetchedPermissions
  return permissions?.some((p) => p.permission === permission) ?? false
}

export function useHasRole(role: AppRole): boolean {
  const { data } = useQuery(hasRoleQueryOptions(role))
  return data ?? false
}
