import { useState } from "react"

import type { User as AuthUser } from "@supabase/supabase-js"

import { useNavigate } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "#/components/ui/alert-dialog"
import { Button } from "#/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "#/components/ui/card"
import { adminDeleteUserMutationOptions } from "#/lib/supabase/data/admin-auth"

export function UserDangerZone({ user }: { user: AuthUser }) {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const [deleteOpen, setDeleteOpen] = useState(false)

  const { mutateAsync: deleteUser, isPending: isDeleting } = useMutation({
    ...adminDeleteUserMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["supasheet", "users"] })
      queryClient.invalidateQueries({ queryKey: ["admin", "auth", "users"] })
      toast.success("User deleted")
      navigate({
        to: "/core/users",
      })
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Failed to delete user"),
  })

  return (
    <Card className="border-destructive/50">
      <CardHeader className="border-b border-destructive/50">
        <CardTitle className="text-destructive">Danger zone</CardTitle>
      </CardHeader>
      <CardContent className="py-4">
        <div className="flex items-center justify-between gap-4">
          <div>
            <p className="text-sm font-medium">Delete user</p>
            <p className="text-xs text-muted-foreground">
              Permanently delete this user and all associated data
            </p>
          </div>
          <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
            <AlertDialogTrigger
              render={
                <Button variant="destructive" size="sm" disabled={isDeleting}>
                  Delete
                </Button>
              }
            />
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Delete user?</AlertDialogTitle>
                <AlertDialogDescription>
                  This will permanently delete{" "}
                  <strong>{user.email ?? user.id}</strong>. This action cannot
                  be undone.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction
                  variant="destructive"
                  onClick={() => {
                    setDeleteOpen(false)
                    deleteUser(user.id)
                  }}
                >
                  Delete
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>
      </CardContent>
    </Card>
  )
}
