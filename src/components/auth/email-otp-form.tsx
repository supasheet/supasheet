import { useState } from "react"

import { getRouteApi } from "@tanstack/react-router"

import { useForm } from "@tanstack/react-form"

import { toast } from "sonner"

import { AuthMethodLinks } from "#/components/auth/auth-method-links"
import { Button } from "#/components/ui/button"
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "#/components/ui/field"
import { Input } from "#/components/ui/input"
import { useAuthConfig } from "#/hooks/use-auth-config"
import { useCompleteSignIn } from "#/hooks/use-complete-sign-in"
import { supabase } from "#/lib/supabase/client"

const routeApi = getRouteApi("/auth/email-otp")

export function EmailOtpForm() {
  const { redirect } = routeApi.useSearch()
  const authConfig = useAuthConfig()
  const completeSignIn = useCompleteSignIn(redirect)
  const [email, setEmail] = useState<string | null>(null)

  const requestForm = useForm({
    defaultValues: { email: "" },
    onSubmit: async ({ value }) => {
      const { error } = await supabase.auth.signInWithOtp({
        email: value.email,
      })
      if (error) {
        toast.error(error.message)
        return
      }
      setEmail(value.email)
    },
  })

  const verifyForm = useForm({
    defaultValues: { code: "" },
    onSubmit: async ({ value }) => {
      if (!email) return
      const { data, error } = await supabase.auth.verifyOtp({
        email,
        token: value.code.replace(/\s/g, ""),
        type: "email",
      })
      if (error || !data.user) {
        toast.error(error?.message ?? "Could not verify code")
        return
      }
      completeSignIn(data.user)
    },
  })

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">
          Sign in with an email code
        </h1>
        <p className="text-sm text-muted-foreground">
          We'll email you a one-time code
        </p>
      </div>

      {email ? (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            verifyForm.handleSubmit()
          }}
        >
          <FieldGroup>
            <p className="text-sm text-muted-foreground">
              Enter the code we sent to{" "}
              <span className="font-medium text-foreground">{email}</span>
            </p>
            <verifyForm.Field
              name="code"
              validators={{
                onChange: ({ value }) =>
                  !value
                    ? "Code is required"
                    : value.length < 6
                      ? "Enter all 6 digits"
                      : undefined,
              }}
            >
              {(field) => (
                <Field>
                  <FieldLabel htmlFor={field.name}>
                    Verification code
                  </FieldLabel>
                  <Input
                    id={field.name}
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    autoFocus
                    maxLength={6}
                    placeholder="000000"
                    value={field.state.value}
                    onBlur={field.handleBlur}
                    onChange={(e) =>
                      field.handleChange(e.target.value.replace(/\D/g, ""))
                    }
                    className="text-center font-mono tracking-widest"
                  />
                  <FieldError
                    errors={field.state.meta.errors.map((e) => ({
                      message: String(e),
                    }))}
                  />
                </Field>
              )}
            </verifyForm.Field>

            <verifyForm.Subscribe
              selector={(state) =>
                [state.isSubmitting, state.values.code] as const
              }
            >
              {([isSubmitting, code]) => (
                <Button
                  type="submit"
                  className="w-full"
                  disabled={isSubmitting || code.length < 6}
                >
                  {isSubmitting ? "Verifying…" : "Verify code"}
                </Button>
              )}
            </verifyForm.Subscribe>

            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => setEmail(null)}
            >
              Use a different email
            </Button>
          </FieldGroup>
        </form>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            requestForm.handleSubmit()
          }}
        >
          <FieldGroup>
            <requestForm.Field
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
            </requestForm.Field>

            <requestForm.Subscribe selector={(state) => state.isSubmitting}>
              {(isSubmitting) => (
                <Button
                  type="submit"
                  className="w-full"
                  disabled={isSubmitting}
                >
                  {isSubmitting ? "Sending…" : "Send code"}
                </Button>
              )}
            </requestForm.Subscribe>
          </FieldGroup>
        </form>
      )}

      <AuthMethodLinks
        authConfig={authConfig}
        exclude="email-otp"
        redirect={redirect}
      />
    </div>
  )
}
