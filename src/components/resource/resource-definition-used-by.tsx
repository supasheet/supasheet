import { Link } from "@tanstack/react-router"

import { ExternalLinkIcon } from "lucide-react"

import { Badge } from "#/components/ui/badge"

import type { LinkedResource } from "./resource-definition-utils"

interface ResourceDefinitionUsedByProps {
  resources: LinkedResource[]
}

export function ResourceDefinitionUsedBy({
  resources,
}: ResourceDefinitionUsedByProps) {
  if (resources.length === 0) return null
  return (
    <div className="flex flex-wrap items-center gap-2 px-4 py-3">
      <span className="text-xs font-medium tracking-wide text-muted-foreground uppercase">
        Used by
      </span>
      {resources.map((r) => (
        <Link
          key={`${r.schema}.${r.name}`}
          to="/$schema/resource/$resource"
          params={{ schema: r.schema, resource: r.name } as never}
        >
          <Badge variant="outline" className="cursor-pointer gap-1">
            <ExternalLinkIcon className="size-3" />
            {r.label}
          </Badge>
        </Link>
      ))}
    </div>
  )
}
