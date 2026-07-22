import { Suspense } from "react"

import { Outlet, createFileRoute, redirect } from "@tanstack/react-router"

import { TableIcon } from "lucide-react"

import { useAppConfig } from "#/hooks/use-app-config"

export const Route = createFileRoute("/auth")({
  beforeLoad: ({ context, location }) => {
    if (
      context.user &&
      location.pathname !== "/auth/update-password" &&
      location.pathname !== "/auth/mfa"
    )
      throw redirect({ to: "/" })
  },
  component: AuthLayout,
})

function AuthLayout() {
  const { name, description } = useAppConfig()

  return (
    <div className="relative grid min-h-screen lg:grid-cols-2">
      {/* Left panel — hidden on mobile */}
      <div className="relative hidden flex-col justify-between p-10 lg:flex">
        <div className="absolute inset-0 bg-primary/5" />

        <div className="relative z-10 flex items-center gap-2 text-lg font-medium">
          <TableIcon className="size-5" />
          <span>{name}</span>
        </div>

        <div className="relative z-10">
          <blockquote className="space-y-2">
            <p className="leading-relaxed text-balance">{description}</p>
          </blockquote>
        </div>
      </div>

      {/* Right panel — form area */}
      <div className="flex items-center justify-center p-6 lg:p-10">
        <div className="w-full max-w-sm">
          <Suspense fallback={<div>Loading…</div>}>
            <Outlet />
          </Suspense>
        </div>
      </div>
    </div>
  )
}
