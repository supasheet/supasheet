import { useNavigate } from "@tanstack/react-router"

import { useQuery, useQueryClient } from "@tanstack/react-query"

import { useForm } from "@tanstack/react-form"

import { ShieldCheckIcon } from "lucide-react"
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
import { authUserQueryOptions } from "#/lib/supabase/data/auth"
import { mfaFactorsQueryOptions } from "#/lib/supabase/data/security"

export function MfaForm() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { data: factors } = useQuery(mfaFactorsQueryOptions)
  const totpFactor = factors?.totp?.[0]

  const form = useForm({
    defaultValues: { code: "" },
    onSubmit: async ({ value }) => {
      if (!totpFactor) {
        toast.error("No authenticator factor found")
        return
      }
      const { error } = await supabase.auth.mfa.challengeAndVerify({
        factorId: totpFactor.id,
        code: value.code.replace(/\s/g, ""),
      })
      if (error) {
        toast.error(error.message)
        return
      }
      await queryClient.invalidateQueries({
        queryKey: authUserQueryOptions.queryKey,
      })
      navigate({ to: "/", replace: true })
    },
  })

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-1 text-center">
        <div className="mb-2 flex justify-center">
          <div className="flex size-12 items-center justify-center rounded-full border">
            <ShieldCheckIcon className="size-6" />
          </div>
        </div>
        <h1 className="text-2xl font-semibold tracking-tight">
          Two-factor authentication
        </h1>
        <p className="text-sm text-muted-foreground">
          Enter the 6-digit code from your authenticator app
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
                  Authentication code
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
          </form.Field>

          <form.Subscribe
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
                {isSubmitting ? "Verifying…" : "Verify"}
              </Button>
            )}
          </form.Subscribe>
        </FieldGroup>
      </form>
    </div>
  )
}
