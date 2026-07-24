import {
  HeadContent,
  Outlet,
  createRootRouteWithContext,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import type { QueryClient } from "@tanstack/react-query"

import { TanStackDevtools } from "@tanstack/react-devtools"
import { TanStackRouterDevtoolsPanel } from "@tanstack/react-router-devtools"

import { InstallPromptBanner } from "#/components/pwa/install-prompt-banner"
import { ThemeProvider } from "#/components/theme-provider"
import { Button } from "#/components/ui/button"
import { Toaster } from "#/components/ui/sonner"
import { Spinner } from "#/components/ui/spinner"
import { TooltipProvider } from "#/components/ui/tooltip"
import { authUserQueryOptions } from "#/lib/supabase/data/auth"
import {
  DEFAULT_APP_CONFIG,
  appConfigQueryOptions,
} from "#/lib/supabase/data/config"
import { userQueryOptions } from "#/lib/supabase/data/users"

import TanStackQueryDevtools from "../integrations/tanstack-query/devtools"
import TanStackQueryProvider from "../integrations/tanstack-query/root-provider"
import "../styles.css"

interface RouterContext {
  queryClient: QueryClient
}

export const Route = createRootRouteWithContext<RouterContext>()({
  beforeLoad: async ({ context, location }) => {
    const [authUser, appConfig] = await Promise.all([
      context.queryClient.ensureQueryData(authUserQueryOptions),
      context.queryClient.ensureQueryData(appConfigQueryOptions()),
    ])
    if (!authUser && !location.pathname.startsWith("/auth")) {
      const segment = location.pathname.split("/")[1] ?? ""
      const isSchemaRoute =
        segment !== "" && !["account", "core", "storage"].includes(segment)
      if (!isSchemaRoute) {
        window.location.href = `/auth/sign-in?redirect=${encodeURIComponent(location.href)}`
        await new Promise<never>(() => {})
      }
    }
    const user = authUser
      ? await context.queryClient.ensureQueryData(userQueryOptions(authUser.id))
      : null
    return { authUser, user, appConfig }
  },
  loader: ({ context }) => ({ appConfig: context.appConfig }),
  head: ({ loaderData }) => {
    const appConfig = loaderData?.appConfig ?? DEFAULT_APP_CONFIG
    return {
      meta: [
        { title: appConfig.name },
        { name: "description", content: appConfig.description },
      ],
    }
  },
  pendingMs: 0,
  pendingComponent: LoadingScreen,
  component: RootComponent,
  errorComponent: ErrorScreen,
})

function ErrorScreen({ error, reset }: ErrorComponentProps) {
  const router = useRouter()

  return (
    <div className="flex h-svh flex-col items-center justify-center gap-4">
      <p className="text-sm text-muted-foreground">
        {error?.message ?? "An unexpected error occurred."}
      </p>
      <div className="flex gap-2">
        <Button
          variant="outline"
          onClick={() => {
            reset()
            router.invalidate()
          }}
        >
          Try again
        </Button>
        <Button variant="ghost" onClick={() => router.navigate({ to: "/" })}>
          Go home
        </Button>
      </div>
    </div>
  )
}

function LoadingScreen() {
  return (
    <div className="flex h-svh items-center justify-center">
      <Spinner className="size-6" />
    </div>
  )
}

function RootComponent() {
  return (
    <>
      <HeadContent />
      <TanStackQueryProvider>
        <ThemeProvider>
          <TooltipProvider>
            <Outlet />
            <Toaster />
            <InstallPromptBanner />
          </TooltipProvider>
        </ThemeProvider>
      </TanStackQueryProvider>
      <TanStackDevtools
        config={{
          position: "bottom-right",
        }}
        plugins={[
          {
            name: "TanStack Router",
            render: <TanStackRouterDevtoolsPanel />,
          },
          TanStackQueryDevtools,
        ]}
      />
    </>
  )
}
