import { createRouter as createTanStackRouter } from "@tanstack/react-router"

import {
  RouteErrorComponent,
  RouteNotFoundComponent,
} from "./components/layouts/route-error"
import { getContext } from "./integrations/tanstack-query/root-provider"
import { routeTree } from "./routeTree.gen"

export function getRouter() {
  const router = createTanStackRouter({
    routeTree,

    context: getContext(),

    scrollRestoration: true,
    defaultPreload: "intent",
    defaultPreloadStaleTime: 0,
    defaultErrorComponent: RouteErrorComponent,
    defaultNotFoundComponent: RouteNotFoundComponent,
  })

  return router
}

declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof getRouter>
  }
}
