import type { User as AuthUser } from "@supabase/supabase-js"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { useForm } from "@tanstack/react-form"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Field, FieldLabel } from "#/components/ui/field"
import { Input } from "#/components/ui/input"
import { adminUpdateUserMutationOptions } from "#/lib/supabase/data/admin-auth"

export function UserEditForm({ user }: { user: AuthUser }) {
  const queryClient = useQueryClient()

  const { mutateAsync: updateUser } = useMutation({
    ...adminUpdateUserMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["admin", "auth", "user", user.id],
      })
      toast.success("User updated")
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Failed to update user"),
  })

  const form = useForm({
    defaultValues: {
      email: user.email ?? "",
      name: (user.user_metadata?.name as string | undefined) ?? "",
      password: "",
    },
    onSubmit: async ({ value }) => {
      const attrs: Parameters<typeof updateUser>[0] = {
        userId: user.id,
        email: value.email,
        user_metadata: { ...user.user_metadata, name: value.name },
      }
      if (value.password) attrs.password = value.password
      await updateUser(attrs)
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Edit user</CardTitle>
      </CardHeader>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          form.handleSubmit()
        }}
      >
        <CardContent className="space-y-4 py-4">
          <form.Field
            name="email"
            validators={{
              onChange: ({ value }) =>
                !value.trim() ? "Email is required" : undefined,
            }}
          >
            {(field) => (
              <Field>
                <FieldLabel htmlFor={field.name}>Email</FieldLabel>
                <Input
                  id={field.name}
                  type="email"
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  aria-invalid={field.state.meta.errors.length > 0}
                />
              </Field>
            )}
          </form.Field>

          <form.Field name="name">
            {(field) => (
              <Field>
                <FieldLabel htmlFor={field.name}>Display name</FieldLabel>
                <Input
                  id={field.name}
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                />
              </Field>
            )}
          </form.Field>

          <form.Field name="password">
            {(field) => (
              <Field>
                <FieldLabel htmlFor={field.name}>
                  New password{" "}
                  <span className="text-xs text-muted-foreground">
                    (leave blank to keep current)
                  </span>
                </FieldLabel>
                <Input
                  id={field.name}
                  type="password"
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="••••••••"
                />
              </Field>
            )}
          </form.Field>
        </CardContent>

        <CardFooter className="justify-end">
          <form.Subscribe
            selector={(s) => ({
              isSubmitting: s.isSubmitting,
              canSubmit: s.canSubmit,
            })}
          >
            {({ isSubmitting, canSubmit }) => (
              <Button type="submit" disabled={!canSubmit || isSubmitting}>
                {isSubmitting ? "Saving…" : "Save changes"}
              </Button>
            )}
          </form.Subscribe>
        </CardFooter>
      </form>
    </Card>
  )
}
