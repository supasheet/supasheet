import { useState } from "react"

import { getRouteApi } from "@tanstack/react-router"

import { useForm } from "@tanstack/react-form"

import { MailCheckIcon } from "lucide-react"
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
import { supabase } from "#/lib/supabase/client"

const routeApi = getRouteApi("/auth/magic-link")

export function MagicLinkForm() {
  const { redirect } = routeApi.useSearch()
  const authConfig = useAuthConfig()
  const [sentTo, setSentTo] = useState<string | null>(null)

  const form = useForm({
    defaultValues: { email: "" },
    onSubmit: async ({ value }) => {
      const { error } = await supabase.auth.signInWithOtp({
        email: value.email,
      })
      if (error) {
        toast.error(error.message)
        return
      }
      setSentTo(value.email)
    },
  })

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">
          Sign in with a magic link
        </h1>
        <p className="text-sm text-muted-foreground">
          We'll email you a link that signs you in instantly
        </p>
      </div>

      {sentTo ? (
        <div className="flex flex-col items-center gap-2 py-4 text-center">
          <MailCheckIcon className="size-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            We sent a sign-in link to{" "}
            <span className="font-medium text-foreground">{sentTo}</span>. Click
            it to continue.
          </p>
          <Button variant="ghost" size="sm" onClick={() => setSentTo(null)}>
            Use a different email
          </Button>
        </div>
      ) : (
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
                <Button
                  type="submit"
                  className="w-full"
                  disabled={isSubmitting}
                >
                  {isSubmitting ? "Sending…" : "Send magic link"}
                </Button>
              )}
            </form.Subscribe>
          </FieldGroup>
        </form>
      )}

      <AuthMethodLinks
        authConfig={authConfig}
        exclude="magic-link"
        redirect={redirect}
      />
    </div>
  )
}
