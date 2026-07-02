import { Link, useRouter } from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"

/**
 * Router-wide default error boundary. Applied via `defaultErrorComponent` so
 * every route without its own `errorComponent` renders a scoped error inside
 * its parent's <Outlet> (preserving the surrounding layout) instead of falling
 * through to the full-page root error screen.
 */
export function RouteErrorComponent({ error }: ErrorComponentProps) {
  const router = useRouter()
  return (
    <div className="flex flex-1 items-center justify-center p-8">
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <AlertCircleIcon />
          </EmptyMedia>
          <EmptyTitle>Something went wrong</EmptyTitle>
          <EmptyDescription>
            {error?.message ?? "An unexpected error occurred."}
          </EmptyDescription>
        </EmptyHeader>
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="outline"
            onClick={() => router.invalidate()}
          >
            Retry
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => router.navigate({ to: "/" })}
          >
            Go Home
          </Button>
        </div>
      </Empty>
    </div>
  )
}

/** Router-wide default not-found boundary. */
export function RouteNotFoundComponent() {
  return (
    <div className="flex flex-1 items-center justify-center p-8">
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <FileXIcon />
          </EmptyMedia>
          <EmptyTitle>Page not found</EmptyTitle>
          <EmptyDescription>
            This page doesn't exist. <Link to="/">Go home</Link>
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    </div>
  )
}
