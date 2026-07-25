import { Link } from "@tanstack/react-router"

import * as LucideIcons from "lucide-react"
import type { LucideIcon } from "lucide-react"

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import type {
  DatabaseSchemas,
  TableMetadata,
  ViewMetadata,
} from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"

export type Resource = {
  name: string
  id: never
  schema: DatabaseSchemas
  type: "table" | "view"
  meta: TableMetadata | ViewMetadata
}

function ResourceIcon({
  item,
}: {
  item: { type: "table" | "view"; meta: { icon: string | undefined } }
}) {
  const iconName = (item.meta?.icon ||
    (item.type === "table" ? "Table2" : "Eye")) as keyof typeof LucideIcons
  const Icon = LucideIcons[iconName] as LucideIcon
  return <Icon className="size-4 shrink-0 text-muted-foreground" />
}

export function ResourceCard({ resource }: { resource: Resource }) {
  const description =
    resource.meta?.description ??
    `A ${resource.type} in the ${formatTitle(resource.schema)} module`

  return (
    <Link
      to="/$schema/resource/$resource"
      params={{ schema: resource.schema, resource: resource.id }}
    >
      <Card size="sm" className="transition-colors hover:bg-accent/50">
        <CardHeader>
          <div className="flex items-center gap-2.5">
            <ResourceIcon
              item={{ type: resource.type, meta: { icon: resource.meta.icon } }}
            />
            <CardTitle className="truncate">
              {resource.meta?.name ?? formatTitle(resource.name)}
            </CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          <CardDescription className="truncate text-xs">
            {description}
          </CardDescription>
        </CardContent>
      </Card>
    </Link>
  )
}
