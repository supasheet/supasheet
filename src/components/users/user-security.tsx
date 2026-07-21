import { useState } from "react"

import type { User as AuthUser } from "@supabase/supabase-js"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "#/components/ui/card"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "#/components/ui/select"
import { Separator } from "#/components/ui/separator"
import { useHasRole } from "#/hooks/use-permissions"
import {
  adminBanUserMutationOptions,
  adminGenerateLinkMutationOptions,
  adminSetUserRoleMutationOptions,
} from "#/lib/supabase/data/admin-auth"
import { rolesQueryOptions } from "#/lib/supabase/data/core"

function isBanned(user: AuthUser): boolean {
  return !!user.banned_until && new Date(user.banned_until) > new Date()
}

export function UserSecurity({ user }: { user: AuthUser }) {
  const queryClient = useQueryClient()
  const [banDuration, setBanDuration] = useState("720h")

  const canBan = useHasRole("x-admin")
  const canGenerateLink = useHasRole("x-admin")
  const canSetRole = useHasRole("x-admin")

  const { data: roles } = useQuery({
    ...rolesQueryOptions,
    enabled: canSetRole,
  })

  const currentRole = (user.app_metadata?.role as string | undefined) ?? "user"

  const { mutateAsync: setUserRole, isPending: isSettingRole } = useMutation({
    ...adminSetUserRoleMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["admin", "auth", "user", user.id],
      })
      toast.success("Role updated")
    },
    onError: (err) => toast.error(err.message),
  })

  const { mutateAsync: banUser, isPending: isBanning } = useMutation({
    ...adminBanUserMutationOptions,
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({
        queryKey: ["admin", "auth", "user", user.id],
      })
      toast.success(
        vars.ban_duration === "none" ? "User unbanned" : "User banned"
      )
    },
    onError: (err) => toast.error(err.message),
  })

  const { mutateAsync: generateLink, isPending: isGeneratingLink } =
    useMutation({
      ...adminGenerateLinkMutationOptions,
      onSuccess: async (data) => {
        await navigator.clipboard.writeText(data.properties.action_link)
        toast.success("Link copied to clipboard")
      },
      onError: (err) => toast.error(err.message),
    })

  const banned = isBanned(user)

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Security</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 py-4">
        {canSetRole && (
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-medium">Role</p>
              <p className="text-xs text-muted-foreground">
                Takes effect next time this user signs in or refreshes their
                session
              </p>
            </div>
            <Select
              value={currentRole}
              disabled={isSettingRole || !roles}
              onValueChange={(val) => {
                if (val !== null) setUserRole({ userId: user.id, role: val })
              }}
            >
              <SelectTrigger className="w-32">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {roles?.map((role) => (
                  <SelectItem key={role} value={role}>
                    {role}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}

        {canSetRole && (canBan || canGenerateLink) && <Separator />}

        {canBan && (
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-medium">
                {banned ? "Unban user" : "Ban user"}
              </p>
              <p className="text-xs text-muted-foreground">
                {banned
                  ? "Remove the ban and restore access"
                  : "Prevent the user from signing in"}
              </p>
            </div>
            {banned ? (
              <Button
                variant="outline"
                size="sm"
                disabled={isBanning}
                onClick={() =>
                  banUser({ userId: user.id, ban_duration: "none" })
                }
              >
                Unban
              </Button>
            ) : (
              <div className="flex items-center gap-2">
                <Select
                  value={banDuration}
                  onValueChange={(val) => {
                    if (val !== null) setBanDuration(val)
                  }}
                >
                  <SelectTrigger className="w-28">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="1h">1 hour</SelectItem>
                    <SelectItem value="24h">24 hours</SelectItem>
                    <SelectItem value="168h">7 days</SelectItem>
                    <SelectItem value="720h">30 days</SelectItem>
                    <SelectItem value="876000h">Permanent</SelectItem>
                  </SelectContent>
                </Select>
                <Button
                  variant="destructive"
                  size="sm"
                  disabled={isBanning}
                  onClick={() =>
                    banUser({ userId: user.id, ban_duration: banDuration })
                  }
                >
                  Ban
                </Button>
              </div>
            )}
          </div>
        )}

        {canBan && canGenerateLink && <Separator />}

        {canGenerateLink && (
          <>
            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-medium">Password reset link</p>
                <p className="text-xs text-muted-foreground">
                  Generate and copy a recovery link for this user
                </p>
              </div>
              <Button
                variant="outline"
                size="sm"
                disabled={isGeneratingLink || !user.email}
                onClick={() =>
                  generateLink({ type: "recovery", email: user.email! })
                }
              >
                Copy link
              </Button>
            </div>

            <div className="flex items-center justify-between gap-4">
              <div>
                <p className="text-sm font-medium">Magic link</p>
                <p className="text-xs text-muted-foreground">
                  Generate and copy a one-time sign-in link
                </p>
              </div>
              <Button
                variant="outline"
                size="sm"
                disabled={isGeneratingLink || !user.email}
                onClick={() =>
                  generateLink({ type: "magiclink", email: user.email! })
                }
              >
                Copy link
              </Button>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}
