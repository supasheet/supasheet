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
import { adminCreateUserMutationOptions } from "#/lib/supabase/data/admin-auth"

export function UserCreateForm() {
  const queryClient = useQueryClient()
  const navigate = useNavigate()

  const { mutateAsync: createUser } = useMutation({
    ...adminCreateUserMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["supasheet", "users"] })
      queryClient.invalidateQueries({ queryKey: ["admin", "auth", "users"] })
      toast.success("User created")
      navigate({
        to: "/core/users",
      })
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Failed to create user")
    },
  })

  const form = useForm({
    defaultValues: { email: "", password: "" },
    onSubmit: async ({ value }) => {
      await createUser({
        email: value.email,
        password: value.password || undefined,
        email_confirm: true,
      })
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>New user</CardTitle>
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

          <form.Field name="password">
            {(field) => (
              <Field>
                <FieldLabel htmlFor={field.name}>
                  Password{" "}
                  <span className="text-xs text-muted-foreground">
                    (leave blank to send invite email instead)
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
                {isSubmitting ? "Creating…" : "Create"}
              </Button>
            )}
          </form.Subscribe>
        </CardFooter>
      </form>
    </Card>
  )
}
