import { useMutation } from "@tanstack/react-query"

import { useForm } from "@tanstack/react-form"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Input } from "#/components/ui/input"
import { Label } from "#/components/ui/label"
import { updatePasswordMutationOptions } from "#/lib/supabase/data/security"

export function SecurityPasswordCard() {
  const { mutateAsync: updatePassword } = useMutation({
    ...updatePasswordMutationOptions,
    onSuccess: () => {
      toast.success("Password updated")
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Failed to update password"
      )
    },
  })

  const form = useForm({
    defaultValues: { password: "", confirmPassword: "" },
    onSubmit: async ({ value }) => {
      await updatePassword(value.password)
      form.reset()
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Change password</CardTitle>
        <CardDescription>
          Choose a new password for your account.
        </CardDescription>
      </CardHeader>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          form.handleSubmit()
        }}
      >
        <CardContent className="space-y-4 py-4">
          <form.Field
            name="password"
            validators={{
              onChange: ({ value }) => {
                if (!value) return "Password is required"
                if (value.length < 8)
                  return "Password must be at least 8 characters"
                return undefined
              },
            }}
          >
            {(field) => (
              <div className="space-y-1.5">
                <Label htmlFor={field.name}>New password</Label>
                <Input
                  id={field.name}
                  type="password"
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  aria-invalid={field.state.meta.errors.length > 0}
                  disabled
                />
                {field.state.meta.errors.length > 0 && (
                  <p className="text-xs text-destructive">
                    {String(field.state.meta.errors[0])}
                  </p>
                )}
              </div>
            )}
          </form.Field>

          <form.Field
            name="confirmPassword"
            validators={{
              onChangeListenTo: ["password"],
              onChange: ({ value, fieldApi }) => {
                const password = fieldApi.form.getFieldValue("password")
                if (!value) return "Please confirm your password"
                if (value !== password) return "Passwords do not match"
                return undefined
              },
            }}
          >
            {(field) => (
              <div className="space-y-1.5">
                <Label htmlFor={field.name}>Confirm new password</Label>
                <Input
                  id={field.name}
                  type="password"
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  aria-invalid={field.state.meta.errors.length > 0}
                  disabled
                />
                {field.state.meta.errors.length > 0 && (
                  <p className="text-xs text-destructive">
                    {String(field.state.meta.errors[0])}
                  </p>
                )}
              </div>
            )}
          </form.Field>
        </CardContent>
        <CardFooter className="justify-end">
          <form.Subscribe
            selector={(s) => ({
              isSubmitting: s.isSubmitting,
              isDirty: s.isDirty,
              canSubmit: s.canSubmit,
            })}
          >
            {({ isSubmitting, isDirty, canSubmit }) => (
              <Button
                type="submit"
                size="sm"
                disabled={!isDirty || !canSubmit || isSubmitting}
              >
                {isSubmitting ? "Saving…" : "Save password"}
              </Button>
            )}
          </form.Subscribe>
        </CardFooter>
      </form>
    </Card>
  )
}
