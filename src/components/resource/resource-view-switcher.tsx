import { Fragment, useMemo } from "react"

import { useNavigate } from "@tanstack/react-router"

import { ChevronDownIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import type {
  DatabaseSchemas,
  DatabaseTables,
  TableMetadata,
} from "#/lib/database-meta.types"
import { getAvailableViews } from "#/lib/resource-view"

export function ResourceViewSwitcher<S extends DatabaseSchemas>({
  schema,
  resource,
  meta,
  currentViewId,
}: {
  schema: S
  resource: DatabaseTables<S>
  meta: TableMetadata
  currentViewId: string
}) {
  const navigate = useNavigate()

  const availableViews = useMemo(
    () => getAvailableViews(schema, resource, meta),
    [schema, resource, meta]
  )
  const currentView = availableViews.find((view) => view.id === currentViewId)
  const CurrentIcon = currentView?.icon

  function handleViewChange(value: string) {
    const view = availableViews.find((v) => v.id === value)
    if (!view) return
    navigate(view.target)
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button size="sm" variant="outline" />}>
        {CurrentIcon && <CurrentIcon className="size-3.5" />}
        <span className="truncate font-medium">
          {currentView?.label ?? "View"}
        </span>
        <ChevronDownIcon className="size-3.5 opacity-50" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-fit rounded-lg">
        <DropdownMenuGroup>
          <DropdownMenuLabel>Views</DropdownMenuLabel>
        </DropdownMenuGroup>
        <DropdownMenuRadioGroup
          value={currentViewId}
          onValueChange={handleViewChange}
        >
          {availableViews.map((view, index) => (
            <Fragment key={view.id}>
              {index > 0 &&
                view.builtIn !== availableViews[index - 1].builtIn && (
                  <DropdownMenuSeparator />
                )}
              <DropdownMenuRadioItem value={view.id}>
                <view.icon className="size-3.5" />
                {view.label}
              </DropdownMenuRadioItem>
            </Fragment>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
