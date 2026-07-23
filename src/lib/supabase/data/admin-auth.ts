import type {
  AdminUserAttributes,
  GenerateLinkParams,
  GenerateLinkProperties,
  Pagination,
  User,
} from "@supabase/supabase-js"

import { mutationOptions, queryOptions } from "@tanstack/react-query"

import { supabase } from "#/lib/supabase/client"

export type { GenerateLinkParams }

export interface AdminUsersPage {
  users: User[]
  aud: string
  nextPage: Pagination["nextPage"]
  lastPage: Pagination["lastPage"]
  total: Pagination["total"]
}

export interface GenerateLinkResult {
  user: User
  properties: GenerateLinkProperties
}

async function invoke<T>(
  fn: string,
  body?: Record<string, unknown>
): Promise<T> {
  const { data, error } = await supabase.functions.invoke<T>(fn, {
    body: body as Record<string, unknown>,
  })
  if (error) throw error
  return data as T
}

function toBody(attrs: object): Record<string, unknown> {
  return attrs as Record<string, unknown>
}

export const adminListUsersQueryOptions = (page = 1, perPage = 50) =>
  queryOptions({
    queryKey: ["admin", "auth", "users", page, perPage],
    queryFn: () =>
      invoke<AdminUsersPage>("admin-list-users", { page, perPage }),
    staleTime: 1000 * 60 * 2,
  })

export const adminGetUserQueryOptions = (userId: string) =>
  queryOptions({
    queryKey: ["admin", "auth", "user", userId],
    queryFn: () => invoke<{ user: User }>("admin-get-user", { userId }),
    staleTime: 1000 * 60 * 2,
    enabled: !!userId,
  })

export const adminInviteUserMutationOptions = mutationOptions({
  mutationFn: ({
    email,
    userData,
    redirectTo,
  }: {
    email: string
    userData?: Record<string, unknown>
    redirectTo?: string
  }) =>
    invoke<{ user: User }>("admin-invite-user", {
      email,
      data: userData,
      redirectTo,
    }),
})

export const adminCreateUserMutationOptions = mutationOptions({
  mutationFn: (attrs: AdminUserAttributes & { email: string }) =>
    invoke<{ user: User }>("admin-create-user", toBody(attrs)),
})

export const adminUpdateUserMutationOptions = mutationOptions({
  mutationFn: ({
    userId,
    ...attrs
  }: AdminUserAttributes & { userId: string }) =>
    invoke<{ user: User }>("admin-update-user", { userId, ...toBody(attrs) }),
})

/** Pass `ban_duration: "24h"` to ban, `ban_duration: "none"` to unban. */
export const adminBanUserMutationOptions = mutationOptions({
  mutationFn: ({
    userId,
    ban_duration,
  }: {
    userId: string
    ban_duration: NonNullable<AdminUserAttributes["ban_duration"]>
  }) => invoke<{ user: User }>("admin-update-user", { userId, ban_duration }),
})

export const adminDeleteUserMutationOptions = mutationOptions({
  mutationFn: (userId: string) =>
    invoke<{ success: true }>("admin-delete-user", { userId }),
})

export const adminGenerateLinkMutationOptions = mutationOptions({
  mutationFn: (params: GenerateLinkParams) =>
    invoke<GenerateLinkResult>("admin-generate-link", toBody(params)),
})

export const adminSetUserRoleMutationOptions = mutationOptions({
  mutationFn: ({ userId, role }: { userId: string; role: string | null }) =>
    invoke<{ user: User }>("admin-set-user-role", { userId, role }),
})
