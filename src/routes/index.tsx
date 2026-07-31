import { Link, createFileRoute } from "@tanstack/react-router"

import {
  ArrowRightIcon,
  DatabaseIcon,
  HardDriveIcon,
  KeyRoundIcon,
  MailIcon,
} from "lucide-react"

import { Header } from "#/components/layouts/header"
import { Avatar, AvatarFallback } from "#/components/ui/avatar"
import { Badge } from "#/components/ui/badge"
import { Separator } from "#/components/ui/separator"
import { Skeleton } from "#/components/ui/skeleton"
import { useUser } from "#/hooks/use-user"
import { pageTitle } from "#/lib/page-title"
import { schemasQueryOptions } from "#/lib/supabase/data/meta"

export const Route = createFileRoute("/")({
  head: () => ({ meta: [{ title: pageTitle("Home") }] }),
  loader: async ({ context }) => {
    const schemas =
      await context.queryClient.ensureQueryData(schemasQueryOptions)
    return { schemas }
  },
  pendingComponent: HomePageSkeleton,
  component: HomePage,
})

function HomePageSkeleton() {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <Header />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-10 sm:px-6">
        <div className="flex flex-col gap-8">
          {/* Profile section */}
          <div className="flex items-center gap-5">
            <Skeleton className="size-16 rounded-full" />
            <div className="flex flex-col gap-2">
              <Skeleton className="h-7 w-40" />
              <Skeleton className="h-4 w-56" />
            </div>
          </div>

          <Separator />

          {/* Info grid */}
          <div className="grid gap-4 sm:grid-cols-2">
            {Array.from({ length: 2 }).map((_, i) => (
              <div
                key={i}
                className="flex flex-col gap-1.5 rounded-xl border bg-card p-4"
              >
                <Skeleton className="h-4 w-16" />
                <Skeleton className="h-4 w-48" />
              </div>
            ))}
          </div>

          <Separator />

          {/* Schemas */}
          <div className="flex flex-col gap-4">
            <Skeleton className="h-6 w-24" />
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="rounded-xl border bg-card p-4">
                  <div className="flex items-center gap-3">
                    <Skeleton className="size-9 rounded-lg" />
                    <Skeleton className="h-4 w-24" />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}

function HomePage() {
  const user = useUser()
  const { schemas } = Route.useLoaderData()

  if (!user) return null

  const initials = user.name.slice(0, 2).toUpperCase()
  const shortId = `${user.id.slice(0, 8)}...${user.id.slice(-4)}`

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <Header />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-10 sm:px-6">
        {/* Profile section */}
        <div className="flex flex-col gap-8">
          <div className="flex items-center gap-5">
            <Avatar size="lg" className="size-16 text-lg">
              <AvatarFallback>{initials}</AvatarFallback>
            </Avatar>

            <div className="flex flex-col gap-1">
              <h1 className="text-2xl font-semibold tracking-tight">
                {user.name}
              </h1>
              <p className="text-sm text-muted-foreground">{user.email}</p>
            </div>
          </div>

          <Separator />

          {/* Info grid */}
          <div className="grid gap-4 sm:grid-cols-2">
            <InfoItem
              icon={<MailIcon className="size-4" />}
              label="Email"
              value={user.email ?? "—"}
            />
            <InfoItem
              icon={<KeyRoundIcon className="size-4" />}
              label="User ID"
              value={
                <Badge variant="secondary" className="font-mono text-xs">
                  {shortId}
                </Badge>
              }
            />
          </div>

          <Separator />

          {/* Schemas */}
          <div className="flex flex-col gap-4">
            <h2 className="text-lg font-semibold">Modules</h2>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Link
                to="/storage"
                className="group rounded-xl border bg-card p-4 transition-colors hover:bg-accent"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="flex size-9 items-center justify-center rounded-lg border bg-background">
                      <HardDriveIcon className="size-4 text-muted-foreground" />
                    </div>
                    <span className="text-sm font-medium">Storage</span>
                  </div>
                  <ArrowRightIcon className="size-4 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" />
                </div>
              </Link>
              {schemas.map((s) => (
                <Link
                  key={s.schema}
                  to={"/$schema"}
                  params={{ schema: s.schema }}
                  className="group rounded-xl border bg-card p-4 transition-colors hover:bg-accent"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <div className="flex size-9 items-center justify-center rounded-lg border bg-background">
                        <DatabaseIcon className="size-4 text-muted-foreground" />
                      </div>
                      <span className="text-sm font-medium capitalize">
                        {s.schema}
                      </span>
                    </div>
                    <ArrowRightIcon className="size-4 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" />
                  </div>
                </Link>
              ))}
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}

function InfoItem({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: React.ReactNode
}) {
  return (
    <div className="flex flex-col gap-1.5 rounded-xl border bg-card p-4">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        {icon}
        {label}
      </div>
      <div className="text-sm font-medium">{value}</div>
    </div>
  )
}
