import { Link } from "@tanstack/react-router"

import { buttonVariants } from "#/components/ui/button"
import type { AuthConfig } from "#/lib/supabase/data/auth"

export type AuthMethod = "password" | "magic-link" | "email-otp" | "phone-otp"

const METHOD_ROUTES: Record<
  AuthMethod,
  {
    to:
      | "/auth/sign-in"
      | "/auth/magic-link"
      | "/auth/email-otp"
      | "/auth/phone-otp"
    label: string
  }
> = {
  password: { to: "/auth/sign-in", label: "Password" },
  "magic-link": { to: "/auth/magic-link", label: "Magic link" },
  "email-otp": { to: "/auth/email-otp", label: "Email code" },
  "phone-otp": { to: "/auth/phone-otp", label: "Phone code" },
}

export function AuthMethodLinks({
  authConfig,
  exclude,
  redirect,
}: {
  authConfig: AuthConfig
  exclude: AuthMethod
  redirect?: string
}) {
  const available: AuthMethod[] = []
  if (authConfig.emailEnabled)
    available.push("password", "magic-link", "email-otp")
  if (authConfig.phoneEnabled) available.push("phone-otp")

  const others = available.filter((method) => method !== exclude)
  if (others.length === 0) return null

  return (
    <div className="flex gap-2">
      {others.map((method) => (
        <Link
          key={method}
          to={METHOD_ROUTES[method].to}
          search={{ redirect }}
          className={buttonVariants({
            variant: "secondary",
            className: "flex-1",
          })}
        >
          {METHOD_ROUTES[method].label}
        </Link>
      ))}
    </div>
  )
}
