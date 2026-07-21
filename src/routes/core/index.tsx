import { Link, createFileRoute } from "@tanstack/react-router"

import { ClipboardListIcon, ShieldCheckIcon, UsersIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { pageTitle } from "#/lib/page-title"

export const Route = createFileRoute("/core/")({
  head: () => ({ meta: [{ title: pageTitle("Core") }] }),
  component: RouteComponent,
})

const sections = [
  {
    title: "Users",
    description: "Manage user accounts, invite members, and control access.",
    url: "/core/users",
    icon: <UsersIcon className="size-5" />,
  },
  {
    title: "Audit Logs",
    description: "Review a full history of actions taken across the system.",
    url: "/core/audit_logs",
    icon: <ClipboardListIcon className="size-5" />,
  },
]

function RouteComponent() {
  return (
    <div className="w-full flex-1">
      <DefaultHeader breadcrumbs={[{ title: "Core" }]} />
      <div className="mx-auto max-w-6xl space-y-8 p-6">
        {/* Core title */}
        <div className="flex items-center gap-3">
          <ShieldCheckIcon className="size-6 text-muted-foreground" />
          <div>
            <h1 className="text-xl font-semibold capitalize">Core</h1>
            <p className="text-sm text-muted-foreground">
              {sections.length} section{sections.length !== 1 ? "s" : ""}
            </p>
          </div>
        </div>

        {/* Sections */}
        <section>
          <h2 className="mb-3 text-sm font-medium tracking-wide text-muted-foreground uppercase">
            Sections
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {sections.map((section) => (
              <Link key={section.url} to={section.url} className="h-full">
                <Card className="h-full transition-colors hover:bg-accent/50">
                  <CardHeader>
                    <div className="flex items-center gap-3">
                      <span className="text-muted-foreground">
                        {section.icon}
                      </span>
                      <div>
                        <CardTitle className="text-sm">
                          {section.title}
                        </CardTitle>
                        <CardDescription className="mt-0.5 text-xs">
                          {section.description}
                        </CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                </Card>
              </Link>
            ))}
          </div>
        </section>
      </div>
    </div>
  )
}
