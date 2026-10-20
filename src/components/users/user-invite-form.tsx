import { useForm } from "@tanstack/react-form"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { useNavigate } from "@tanstack/react-router"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Field, FieldError, FieldLabel } from "#/components/ui/field"
import { Input } from "#/components/ui/input"
import { adminInviteUserMutationOptions } from "#/lib/supabase/data/admin-auth"

export function UserInviteForm() {
  const queryClient = useQueryClient()
  const navigate = useNavigate()

  const { mutateAsync: inviteUser } = useMutation({
    ...adminInviteUserMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["supasheet", "users"] })
      queryClient.invalidateQueries({ queryKey: ["admin", "auth", "users"] })
      toast.success("Invite sent")
      navigate({
        to: "/core/users",
      })
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Failed to send invite")
    },
  })

  const form = useForm({
    defaultValues: { email: "", redirectTo: "" },
    onSubmit: async ({ value }) => {
      await inviteUser({
        email: value.email,
        redirectTo: value.redirectTo || undefined,
      })
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Invite user</CardTitle>
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
                  placeholder="user@example.com"
                />
                <FieldError
                  errors={field.state.meta.errors.map((e) => ({
                    message: String(e),
                  }))}
                />
              </Field>
            )}
          </form.Field>

          <form.Field name="redirectTo">
            {(field) => (
              <Field>
                <FieldLabel htmlFor={field.name}>
                  Redirect URL{" "}
                  <span className="text-xs text-muted-foreground">
                    (optional)
                  </span>
                </FieldLabel>
                <Input
                  id={field.name}
                  type="url"
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="https://example.com/welcome"
                />
              </Field>
            )}
          </form.Field>
        </CardContent>

        <CardFooter className="justify-end gap-2">
          <Button
            type="button"
            variant="outline"
            onClick={() =>
              navigate({
                to: "/core/users",
              })
            }
          >
            Cancel
          </Button>
          <form.Subscribe
            selector={(s) => ({
              isSubmitting: s.isSubmitting,
              canSubmit: s.canSubmit,
            })}
          >
            {({ isSubmitting, canSubmit }) => (
              <Button type="submit" disabled={!canSubmit || isSubmitting}>
                {isSubmitting ? "Sending…" : "Send invite"}
              </Button>
            )}
          </form.Subscribe>
        </CardFooter>
      </form>
    </Card>
  )
}
