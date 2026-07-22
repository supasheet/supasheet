import { Link } from "@tanstack/react-router"

import { useForm } from "@tanstack/react-form"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "#/components/ui/field"
import { Input } from "#/components/ui/input"
import { supabase } from "#/lib/supabase/client"

export function ForgotPasswordForm() {
  const form = useForm({
    defaultValues: { email: "" },
    onSubmit: async ({ value }) => {
      const { error } = await supabase.auth.resetPasswordForEmail(value.email, {
        redirectTo: `${window.location.origin}/auth/update-password`,
      })
      if (error) {
        toast.error(error.message)
        return
      }
      toast.success("Check your email — we've sent a password reset link.")
    },
  })

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">
          Forgot password
        </h1>
        <p className="text-sm text-muted-foreground">
          Enter your email to receive a reset link
        </p>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault()
          form.handleSubmit()
        }}
      >
        <FieldGroup>
          <form.Field
            name="email"
            validators={{
              onChange: ({ value }) =>
                !value
                  ? "Email is required"
                  : !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
                    ? "Enter a valid email address"
                    : undefined,
            }}
          >
            {(field) => (
              <Field>
                <FieldLabel htmlFor={field.name}>Email</FieldLabel>
                <Input
                  id={field.name}
                  type="email"
                  placeholder="you@example.com"
                  value={field.state.value}
                  onBlur={field.handleBlur}
                  onChange={(e) => field.handleChange(e.target.value)}
                />
                <FieldError
                  errors={field.state.meta.errors.map((e) => ({
                    message: String(e),
                  }))}
                />
              </Field>
            )}
          </form.Field>

          <form.Subscribe selector={(state) => state.isSubmitting}>
            {(isSubmitting) => (
              <Button type="submit" className="w-full" disabled={isSubmitting}>
                {isSubmitting ? "Sending…" : "Send reset link"}
              </Button>
            )}
          </form.Subscribe>
        </FieldGroup>
      </form>

      <Link
        to="/auth/sign-in"
        className="text-center text-sm text-muted-foreground underline hover:text-foreground"
      >
        Back to sign in
      </Link>
    </div>
  )
}
