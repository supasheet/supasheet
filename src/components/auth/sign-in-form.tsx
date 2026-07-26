import { Link, getRouteApi } from "@tanstack/react-router"

import { useForm } from "@tanstack/react-form"

import { toast } from "sonner"

import { AuthMethodLinks } from "#/components/auth/auth-method-links"
import { OAuthProviderButtons } from "#/components/auth/oauth-providers"
import { Button } from "#/components/ui/button"
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "#/components/ui/field"
import { Input } from "#/components/ui/input"
import { Separator } from "#/components/ui/separator"
import { useAuthConfig } from "#/hooks/use-auth-config"
import { useCompleteSignIn } from "#/hooks/use-complete-sign-in"
import { supabase } from "#/lib/supabase/client"

const routeApi = getRouteApi("/auth/sign-in")

export function SignInForm() {
  const { redirect } = routeApi.useSearch()
  const authConfig = useAuthConfig()
  const completeSignIn = useCompleteSignIn(redirect)

  const form = useForm({
    defaultValues: { email: "", password: "" },
    onSubmit: async ({ value }) => {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: value.email,
        password: value.password,
      })
      if (error || !data.user) {
        toast.error(error?.message ?? "Could not sign in")
        return
      }
      completeSignIn(data.user)
    },
  })

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">Sign in</h1>
        <p className="text-sm text-muted-foreground">
          Enter your credentials to access your account
        </p>
      </div>

      <OAuthProviderButtons providers={authConfig.providers} />

      {authConfig.providers.length > 0 && authConfig.emailEnabled && (
        <div className="flex items-center gap-3">
          <Separator className="flex-1" />
          <span className="text-xs text-muted-foreground">or</span>
          <Separator className="flex-1" />
        </div>
      )}

      {authConfig.emailEnabled ? (
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

            <form.Field
              name="password"
              validators={{
                onChange: ({ value }) =>
                  !value ? "Password is required" : undefined,
              }}
            >
              {(field) => (
                <Field>
                  <div className="flex items-center justify-between">
                    <FieldLabel htmlFor={field.name}>Password</FieldLabel>
                    <Link
                      to="/auth/forgot-password"
                      className="text-sm text-muted-foreground hover:text-foreground"
                    >
                      Forgot password?
                    </Link>
                  </div>
                  <Input
                    id={field.name}
                    type="password"
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
                  {isSubmitting ? "Signing in…" : "Sign in"}
                </Button>
              )}
            </form.Subscribe>
          </FieldGroup>
        </form>
      ) : (
        !authConfig.phoneEnabled &&
        authConfig.providers.length === 0 && (
          <p className="text-center text-sm text-muted-foreground">
            Sign-in is not configured. Contact your administrator.
          </p>
        )
      )}

      <AuthMethodLinks
        authConfig={authConfig}
        exclude="password"
        redirect={redirect}
      />

      {authConfig.signupEnabled && (
        <p className="text-center text-sm text-muted-foreground">
          Don't have an account?{" "}
          <Link to="/auth/sign-up" className="text-foreground underline">
            Sign up
          </Link>
        </p>
      )}
    </div>
  )
}
