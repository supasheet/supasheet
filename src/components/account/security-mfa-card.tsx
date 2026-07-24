import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { ShieldCheckIcon, ShieldOffIcon } from "lucide-react"
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
import {
  mfaFactorsQueryOptions,
  unenrollMfaMutationOptions,
} from "#/lib/supabase/data/security"

import { SecurityMfaEnrollPanel, useMfaEnroll } from "./security-mfa-enroll"

export function SecurityMfaCard() {
  const queryClient = useQueryClient()
  const { data: factors, isLoading } = useQuery(mfaFactorsQueryOptions)
  const {
    enrollState,
    setEnrollState,
    isEnrolling,
    enrollTotp,
    verifyForm,
    isVerifying,
    cancelEnroll,
  } = useMfaEnroll()

  const verifiedFactors = factors?.totp ?? []

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

        <SecurityMfaEnrollPanel
          enrollState={enrollState}
          setEnrollState={setEnrollState}
          verifyForm={verifyForm}
          isVerifying={isVerifying}
          cancelEnroll={cancelEnroll}
        />
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
