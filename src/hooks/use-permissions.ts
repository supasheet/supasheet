import { useRouterState } from "@tanstack/react-router"

import { useQuery } from "@tanstack/react-query"

import type { AppRole, PermissionsMap } from "#/lib/supabase/data/core"
import {
  hasRoleQueryOptions,
  userPermissionsQueryOptions,
} from "#/lib/supabase/data/core"

export type PermissionCheck = {
  schema: string
  resource: string
  action: string
}

function usePermissions(): PermissionsMap | null {
  return useRouterState({
    select: (s) => {
      const match = s.matches.find((m) => "permissions" in (m.context ?? {}))
      return (
        (match?.context as { permissions?: PermissionsMap | null })
          ?.permissions ?? null
      )
    },
  })
}

export function hasResourcePermission(
  permissions: PermissionsMap | null | undefined,
  { schema, resource, action }: PermissionCheck
): boolean {
  return permissions?.[schema]?.[resource]?.includes(action) ?? false
}

export function useHasPermission(
  permission: PermissionCheck | undefined
): boolean {
  const contextPermissions = usePermissions()
  const isActiveSchema =
    !!permission && !!contextPermissions?.[permission.schema]

  const { data: fetchedPermissions } = useQuery({
    ...userPermissionsQueryOptions(permission?.schema),
    enabled: !!permission && !isActiveSchema,
  })

  if (!permission) return false
  const permissions = isActiveSchema ? contextPermissions : fetchedPermissions
  return hasResourcePermission(permissions, permission)
}

export function useHasRole(role: AppRole): boolean {
  const { data } = useQuery(hasRoleQueryOptions(role))
  return data ?? false
}
