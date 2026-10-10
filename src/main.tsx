import { RouterProvider, createRouter } from "@tanstack/react-router"

import ReactDOM from "react-dom/client"

import {
  RouteErrorComponent,
  RouteNotFoundComponent,
} from "./components/layouts/route-error"
import { getContext } from "./integrations/tanstack-query/root-provider"
import { routeTree } from "./routeTree.gen"

const router = createRouter({
  routeTree,
  context: getContext(),
  scrollRestoration: true,
  defaultPreload: "intent",
  defaultPreloadStaleTime: 0,
  defaultErrorComponent: RouteErrorComponent,
  defaultNotFoundComponent: RouteNotFoundComponent,
})

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router
  }
}

const rootElement = document.getElementById("app")!

if (!rootElement.innerHTML) {
  const root = ReactDOM.createRoot(rootElement)
  root.render(<RouterProvider router={router} />)
}
