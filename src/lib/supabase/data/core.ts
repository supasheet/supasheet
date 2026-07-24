import { mutationOptions, queryOptions } from "@tanstack/react-query"

import type { ColumnFiltersState } from "@tanstack/react-table"

import type { Json } from "#/lib/database.types"

import { supabase } from "../client"
import { applyFilters } from "../filter"

export type AppRole = string
export type PermissionsMap = Record<string, Record<string, string[]>>

export const auditLogsQueryOptions = (
  page: number,
  pageSize: number,
  sortId?: string,
  sortDesc?: boolean,
  filters: ColumnFiltersState = []
) =>
  queryOptions({
    queryKey: [
      "supasheet",
      "audit_logs",
      page,
      pageSize,
      sortId,
      sortDesc,
      filters,
    ],
    queryFn: async () => {
      let query = supabase
        .schema("supasheet")
        .from("audit_logs")
        .select("*", { count: "exact" })
        .range((page - 1) * pageSize, page * pageSize - 1)

      if (sortId) {
        query = query.order(sortId, { ascending: !sortDesc })
      } else {
        query = query.order("created_at", { ascending: false })
      }

      query = applyFilters(query, filters)

      const { data, count, error } = await query
      if (error) throw error

      return {
        result: data,
        count: count,
        page: page,
        pageSize: pageSize,
      }
    },
    staleTime: 1000 * 60 * 5,
  })

export const usersQueryOptions = (
  page: number,
  pageSize: number,
  sortId?: string,
  sortDesc?: boolean,
  filters: ColumnFiltersState = []
) =>
  queryOptions({
    queryKey: ["supasheet", "users", page, pageSize, sortId, sortDesc, filters],
    queryFn: async () => {
      let query = supabase
        .schema("supasheet")
        .from("users")
        .select("*", { count: "exact" })
        .range((page - 1) * pageSize, page * pageSize - 1)

      if (sortId) {
        query = query.order(sortId, { ascending: !sortDesc })
      }

      query = applyFilters(query, filters)

      const { data, count, error } = await query
      if (error) throw error

      return {
        result: data,
        count: count,
        page: page,
        pageSize: pageSize,
      }
    },
    staleTime: 1000 * 60 * 5,
  })

export const allUsersQueryOptions = queryOptions({
  queryKey: ["supasheet", "users", "all"],
  queryFn: async () => {
    const { data, error } = await supabase
      .schema("supasheet")
      .from("users")
      .select("id, name, email")
      .order("name", { ascending: true })

    if (error) throw error
    return data
  },
  staleTime: 1000 * 60 * 5,
})

export const whoamiQueryOptions = queryOptions({
  queryKey: ["supasheet", "whoami"] as const,
  queryFn: async () => {
    const { data, error } = await supabase.schema("supasheet").rpc("whoami")
    if (error) throw error
    return data as { user_id: string | null; role: string | null }
  },
  staleTime: 1000 * 60 * 5,
})

export const rolesQueryOptions = queryOptions({
  queryKey: ["supasheet", "roles"] as const,
  queryFn: async () => {
    const { data, error } = await supabase.schema("supasheet").rpc("get_roles")
    if (error) throw error
    return data.map((row) => row.role)
  },
  staleTime: 1000 * 60 * 5,
})

export const hasRoleQueryOptions = (role: AppRole) =>
  queryOptions({
    queryKey: ["supasheet", "has_role", role],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("has_role", { requested_role: role })
      if (error) throw error
      return data
    },
    staleTime: 1000 * 60 * 5,
  })

export const auditLogQueryOptions = (id: string) =>
  queryOptions({
    queryKey: ["supasheet", "audit_logs", id],
    queryFn: async () => {
      const { data, error } = await supabase
        .schema("supasheet")
        .from("audit_logs")
        .select("*")
        .eq("id", id)
        .maybeSingle()
      if (error) throw error
      return data
    },
    staleTime: 1000 * 60 * 5,
  })

export const deleteAccountsMutationOptions = mutationOptions({
  mutationFn: async (ids: string[]) => {
    const { error } = await supabase
      .schema("supasheet")
      .from("users")
      .delete()
      .in("id", ids)
    if (error) throw error
  },
})

export const userPermissionsQueryOptions = (schema?: string) =>
  queryOptions({
    queryKey: ["supasheet", "permissions", schema ?? null],
    queryFn: async (): Promise<PermissionsMap> => {
      const { data, error } = await supabase
        .schema("supasheet")
        .rpc("get_permissions", { schema_name: schema })
      if (error) throw error
      return (data ?? {}) as PermissionsMap
    },
    staleTime: 1000 * 60 * 5,
  })

// ─────────────────────────────────────────────
// Notifications
// ─────────────────────────────────────────────

export type NotificationRow = {
  id: string
  type: string
  title: string
  body: string | null
  link: string | null
  metadata: Json | null
  created_by: string | null
  created_at: string
}

export type UserNotificationRow = {
  id: string
  notification_id: string
  user_id: string
  read_at: string | null
  archived_at: string | null
  created_at: string
  notification: NotificationRow
}

export const notificationsQueryOptions = queryOptions({
  queryKey: ["supasheet", "notifications", "me"] as const,
  queryFn: async (): Promise<UserNotificationRow[]> => {
    const { data, error } = await supabase
      .schema("supasheet")
      .from("user_notifications" as never)
      .select(
        "id, notification_id, user_id, read_at, archived_at, created_at, notification:notification_id ( id, type, title, body, link, metadata, created_by, created_at )"
      )
      .is("archived_at", null)
      .order("created_at", { ascending: false })

    if (error) throw error
    return data ?? []
  },
  staleTime: 1000 * 30,
})

export const unreadNotificationsCountQueryOptions = queryOptions({
  queryKey: ["supasheet", "notifications", "me", "unread-count"] as const,
  queryFn: async (): Promise<number> => {
    const { data, error } = await supabase
      .schema("supasheet")
      .rpc("unread_notifications_count" as never)
    if (error) throw error
    return data ?? 0
  },
  staleTime: 1000 * 30,
})

export const markNotificationReadMutationOptions = mutationOptions({
  mutationFn: async (id: string) => {
    const { error } = await supabase
      .schema("supasheet")
      .from("user_notifications" as never)
      .update({ read_at: new Date().toISOString() } as never)
      .eq("id", id)
    if (error) throw error
  },
})

export const markAllNotificationsReadMutationOptions = mutationOptions({
  mutationFn: async () => {
    const { error } = await supabase
      .schema("supasheet")
      .rpc("mark_all_notifications_read" as never)
    if (error) throw error
  },
})

export const archiveNotificationMutationOptions = mutationOptions({
  mutationFn: async (id: string) => {
    const { error } = await supabase
      .schema("supasheet")
      .from("user_notifications" as never)
      .update({ archived_at: new Date().toISOString() } as never)
      .eq("id", id)
    if (error) throw error
  },
})

export const deleteNotificationMutationOptions = mutationOptions({
  mutationFn: async (id: string) => {
    const { error } = await supabase
      .schema("supasheet")
      .from("user_notifications" as never)
      .delete()
      .eq("id", id)
    if (error) throw error
  },
})
