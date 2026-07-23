import { Link, useRouterState } from "@tanstack/react-router"

import { LogInIcon } from "lucide-react"

import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "#/components/ui/breadcrumb"
import { Button } from "#/components/ui/button"
import { Separator } from "#/components/ui/separator"
import { SidebarTrigger } from "#/components/ui/sidebar"
import { useAuthUser } from "#/hooks/use-user"

export function DefaultHeader({
  breadcrumbs,
  children,
}: {
  breadcrumbs: {
    title: string
    url?: string
  }[]
  children?: React.ReactNode
}) {
  const authUser = useAuthUser()
  const redirect = useRouterState({ select: (state) => state.location.href })
  const items = breadcrumbs.slice(0, -1)
  const lastItem = breadcrumbs.at(-1)

  return (
    <div className="w-full">
      <header className="flex h-12 shrink-0 items-center gap-2 border-b px-4">
        <div className="flex flex-1 items-center gap-2">
          {authUser && <SidebarTrigger />}
          {lastItem && (
            <>
              {authUser && (
                <Separator
                  orientation="vertical"
                  className="mt-1.5 mr-2 data-[orientation=vertical]:!h-4"
                />
              )}
              <Breadcrumb>
                <BreadcrumbList>
                  {items.map((item) => (
                    <BreadcrumbItem key={item.title} className="hidden lg:flex">
                      {item.url ? (
                        <BreadcrumbLink render={<Link to={item.url} />}>
                          {item.title}
                        </BreadcrumbLink>
                      ) : (
                        item.title
                      )}
                      <BreadcrumbSeparator />
                    </BreadcrumbItem>
                  ))}
                  <BreadcrumbItem>
                    <BreadcrumbPage>{lastItem.title}</BreadcrumbPage>
                  </BreadcrumbItem>
                </BreadcrumbList>
              </Breadcrumb>
            </>
          )}
        </div>
        {children}
        {!authUser && (
          <Button
            size="sm"
            nativeButton={false}
            render={<Link to="/auth/sign-in" search={{ redirect }} />}
          >
            <LogInIcon />
            Sign in
          </Button>
        )}
      </header>
    </div>
  )
}
