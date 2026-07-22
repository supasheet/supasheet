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
import { useAuthUser } from "#/hooks/use-user"
import { updateEmailMutationOptions } from "#/lib/supabase/data/identities"

export function IdentityEmailCard() {
  const user = useAuthUser()

  const { mutateAsync: updateEmail } = useMutation({
    ...updateEmailMutationOptions,
    onSuccess: () => {
      toast.success(
        "Confirmation email sent. Check your inbox to confirm the change."
      )
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Failed to update email")
    },
  })

  const form = useForm({
    defaultValues: { email: user?.email ?? "" },
    onSubmit: async ({ value }) => {
      await updateEmail(value.email.trim())
    },
  })

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Email address</CardTitle>
        <CardDescription>
          Update your email address. A confirmation will be sent to the new
          address.
        </CardDescription>
      </CardHeader>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          form.handleSubmit()
        }}
      >
        <CardContent className="py-4">
          <form.Field
            name="email"
            validators={{
              onChange: ({ value }) => {
                if (!value.trim()) return "Email is required"
                if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()))
                  return "Enter a valid email address"
                return undefined
              },
            }}
          >
            {(field) => (
              <div className="space-y-1.5">
                <Label htmlFor={field.name}>Email</Label>
                <Input
                  id={field.name}
                  type="email"
                  value={field.state.value}
                  onChange={(e) => field.handleChange(e.target.value)}
                  onBlur={field.handleBlur}
                  placeholder="you@example.com"
                  aria-invalid={field.state.meta.errors.length > 0}
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
                {isSubmitting ? "Saving…" : "Save email"}
              </Button>
            )}
          </form.Subscribe>
        </CardFooter>
      </form>
    </Card>
  )
}
