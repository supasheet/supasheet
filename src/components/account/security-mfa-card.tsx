import { useState } from "react"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { useForm } from "@tanstack/react-form"

import {
  ScanQrCodeIcon,
  ShieldCheckIcon,
  ShieldOffIcon,
  XIcon,
} from "lucide-react"
import { toast } from "sonner"

import { Badge } from "#/components/ui/badge"
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
import { Separator } from "#/components/ui/separator"
import {
  enrollTotpMutationOptions,
  mfaFactorsQueryOptions,
  unenrollMfaMutationOptions,
  verifyTotpMutationOptions,
} from "#/lib/supabase/data/security"

type EnrollState =
  | { step: "idle" }
  | { step: "setup"; factorId: string; qrCode: string; secret: string }
  | { step: "verify"; factorId: string }

export function SecurityMfaCard() {
  const queryClient = useQueryClient()
  const { data: factors, isLoading } = useQuery(mfaFactorsQueryOptions)
  const [enrollState, setEnrollState] = useState<EnrollState>({ step: "idle" })

  const verifiedFactors = factors?.totp ?? []

  const verifyForm = useForm({
    defaultValues: { code: "" },
    onSubmit: ({ value }) => {
      if (enrollState.step === "setup" || enrollState.step === "verify") {
        verifyTotp({
          factorId: enrollState.factorId,
          code: value.code.replace(/\s/g, ""),
        })
      }
    },
  })

  const { mutate: enrollTotp, isPending: isEnrolling } = useMutation({
    ...enrollTotpMutationOptions,
    onSuccess: (data) => {
      setEnrollState({
        step: "setup",
        factorId: data.id,
        qrCode: data.totp.qr_code,
        secret: data.totp.secret,
      })
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Failed to start enrollment"
      )
    },
  })

  const { mutate: verifyTotp, isPending: isVerifying } = useMutation({
    ...verifyTotpMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["auth", "mfa-factors"] })
      setEnrollState({ step: "idle" })
      verifyForm.reset()
      toast.success("Two-factor authentication enabled")
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Invalid code")
    },
  })

  const {
    mutate: unenroll,
    isPending: isUnenrolling,
    variables: unenrollingId,
  } = useMutation({
    ...unenrollMfaMutationOptions,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["auth", "mfa-factors"] })
      toast.success("Two-factor authentication removed")
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Failed to remove 2FA")
    },
  })

  function cancelEnroll() {
    setEnrollState({ step: "idle" })
    verifyForm.reset()
  }

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Two-factor authentication</CardTitle>
        <CardDescription>
          Add an extra layer of security using a TOTP authenticator app.
        </CardDescription>
      </CardHeader>

      <CardContent className="divide-y p-0">
        {isLoading ? (
          <div className="px-6 py-4 text-sm text-muted-foreground">
            Loading…
          </div>
        ) : verifiedFactors.length === 0 && enrollState.step === "idle" ? (
          <div className="flex items-center gap-3 px-6 py-4">
            <ShieldOffIcon className="size-5 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              Two-factor authentication is not enabled.
            </p>
          </div>
        ) : (
          verifiedFactors.map((factor) => (
            <div
              key={factor.id}
              className="flex items-center justify-between px-6 py-4"
            >
              <div className="flex items-center gap-3">
                <div className="flex size-9 shrink-0 items-center justify-center rounded-md border">
                  <ShieldCheckIcon className="size-5" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-medium">
                      {factor.friendly_name ?? "Authenticator app"}
                    </p>
                    <Badge variant="secondary" className="text-xs">
                      Active
                    </Badge>
                  </div>
                  <p className="text-xs text-muted-foreground capitalize">
                    {factor.factor_type} · TOTP
                  </p>
                </div>
              </div>
              <Button
                size="sm"
                variant="outline"
                className="text-destructive hover:text-destructive"
                disabled={isUnenrolling && unenrollingId === factor.id}
                onClick={() => unenroll(factor.id)}
              >
                <ShieldOffIcon className="size-3.5" />
                {isUnenrolling && unenrollingId === factor.id
                  ? "Removing…"
                  : "Remove"}
              </Button>
            </div>
          ))
        )}

        {enrollState.step !== "idle" && (
          <>
            <Separator />
            <div className="space-y-4 px-6 py-4">
              <div className="flex items-center justify-between">
                <p className="text-sm font-medium">Set up authenticator app</p>
                <Button
                  size="icon"
                  variant="ghost"
                  className="size-7"
                  onClick={cancelEnroll}
                >
                  <XIcon className="size-4" />
                </Button>
              </div>

              {enrollState.step === "setup" && (
                <>
                  <div className="flex flex-col items-center gap-3">
                    <div className="rounded-lg border p-2">
                      <img
                        src={enrollState.qrCode}
                        alt="Scan this QR code with your authenticator app"
                        className="size-40"
                      />
                    </div>
                    <p className="text-center text-xs text-muted-foreground">
                      Scan the QR code with your authenticator app, or enter the
                      key manually.
                    </p>
                    <div className="w-full rounded-md bg-muted px-3 py-2 text-center font-mono text-xs tracking-widest select-all">
                      {enrollState.secret}
                    </div>
                  </div>
                  <Button
                    size="sm"
                    variant="outline"
                    className="w-full"
                    onClick={() =>
                      setEnrollState({
                        step: "verify",
                        factorId: enrollState.factorId,
                      })
                    }
                  >
                    <ScanQrCodeIcon className="size-3.5" />
                    I've scanned the QR code
                  </Button>
                </>
              )}

              {enrollState.step === "verify" && (
                <form
                  onSubmit={(e) => {
                    e.preventDefault()
                    verifyForm.handleSubmit()
                  }}
                  className="space-y-3"
                >
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
                      <div className="space-y-1.5">
                        <Label htmlFor={field.name}>
                          Enter the 6-digit code from your app
                        </Label>
                        <Input
                          id={field.name}
                          inputMode="numeric"
                          autoComplete="one-time-code"
                          maxLength={6}
                          placeholder="000000"
                          value={field.state.value}
                          onBlur={field.handleBlur}
                          onChange={(e) =>
                            field.handleChange(
                              e.target.value.replace(/\D/g, "")
                            )
                          }
                          className="font-mono tracking-widest"
                        />
                      </div>
                    )}
                  </verifyForm.Field>
                  <div className="flex gap-2">
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      onClick={() =>
                        setEnrollState({
                          step: "setup",
                          factorId: enrollState.factorId,
                          qrCode: "",
                          secret: "",
                        })
                      }
                    >
                      Back
                    </Button>
                    <verifyForm.Subscribe selector={(s) => s.values.code}>
                      {(code) => (
                        <Button
                          type="submit"
                          size="sm"
                          disabled={code.length < 6 || isVerifying}
                          className="flex-1"
                        >
                          {isVerifying ? "Verifying…" : "Verify & enable"}
                        </Button>
                      )}
                    </verifyForm.Subscribe>
                  </div>
                </form>
              )}
            </div>
          </>
        )}
      </CardContent>

      {enrollState.step === "idle" && verifiedFactors.length === 0 && (
        <CardFooter className="justify-end">
          <Button size="sm" disabled={isEnrolling} onClick={() => enrollTotp()}>
            <ShieldCheckIcon className="size-3.5" />
            {isEnrolling ? "Starting…" : "Enable 2FA"}
          </Button>
        </CardFooter>
      )}
    </Card>
  )
}
