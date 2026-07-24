import { ResourceCard } from "./resource-card"
import type { Resource } from "./resource-card"

export function ResourceCardGrid({ resources }: { resources: Resource[] }) {
  const hasGroups = resources.some((r) => r.meta?.collapsible_group)

  if (!hasGroups) {
    return (
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {resources.map((resource) => (
          <ResourceCard key={resource.id} resource={resource} />
        ))}
      </div>
    )
  }

  const grouped: Record<string, Resource[]> = {}
  for (const resource of resources) {
    const key = resource.meta?.collapsible_group ?? ""
    grouped[key] = grouped[key] ?? []
    grouped[key].push(resource)
  }

  const ungrouped = grouped[""] ?? []
  const namedGroups = Object.entries(grouped).filter(([key]) => key !== "")

  return (
    <div className="space-y-6">
      {ungrouped.length > 0 && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {ungrouped.map((resource) => (
            <ResourceCard key={resource.id} resource={resource} />
          ))}
        </div>
      )}
      {namedGroups.map(([group, groupResources]) => (
        <div key={group}>
          <h3 className="mb-3 text-sm font-medium text-muted-foreground">
            {group}
          </h3>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {groupResources.map((resource) => (
              <ResourceCard key={resource.id} resource={resource} />
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
