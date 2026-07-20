"use client"

import * as React from "react"

import { useNavigate } from "@tanstack/react-router"

import * as LucideIcons from "lucide-react"
import type { LucideIcon } from "lucide-react"
import { HomeIcon, SearchIcon } from "lucide-react"

import {
  Command,
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "#/components/ui/command"
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "#/components/ui/sidebar"
import { formatTitle } from "#/lib/format"

type ResourceItem = {
  id: string
  name: string
  url: string
  type: "table" | "view"
  meta?: { label?: string; icon?: string } | null
}

function ResourceIcon({ item }: { item: ResourceItem }) {
  const iconName = (item.meta?.icon ||
    (item.type === "table" ? "Table2" : "Eye")) as keyof typeof LucideIcons
  const Icon = LucideIcons[iconName] as LucideIcon
  return <Icon className="size-4 shrink-0" />
}

export function QuickSearch({
  schema,
  items,
  resourceItems,
}: {
  schema: string
  items: {
    title: string
    url: string
    icon?: React.ReactNode
  }[]
  resourceItems?: ResourceItem[]
}) {
  const [open, setOpen] = React.useState(false)
  const navigate = useNavigate()

  React.useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault()
        setOpen((prev) => !prev)
      }
    }
    document.addEventListener("keydown", handleKeyDown)
    return () => document.removeEventListener("keydown", handleKeyDown)
  }, [])

  const handleSelect = (url: string) => {
    setOpen(false)
    navigate({ to: url as never })
  }

  return (
    <>
      <SidebarMenu>
        <SidebarMenuItem>
          <SidebarMenuButton
            tooltip="Quick Search"
            onClick={() => setOpen(true)}
          >
            <SearchIcon />
            <span>Quick Search</span>
          </SidebarMenuButton>
        </SidebarMenuItem>
      </SidebarMenu>

      <CommandDialog
        open={open}
        onOpenChange={setOpen}
        title="Quick Search"
        description="Search sidebar items"
      >
        <Command>
          <CommandInput placeholder="Search..." />
          <CommandList>
            <CommandEmpty>No results found.</CommandEmpty>
            <CommandGroup heading="Navigation">
              <CommandItem
                value="Overview"
                onSelect={() => handleSelect(`/${schema}`)}
              >
                <HomeIcon />
                <span>Overview</span>
              </CommandItem>
              {items.map((item) => (
                <CommandItem
                  key={item.url}
                  value={item.title}
                  onSelect={() => handleSelect(`/${schema}/${item.url}`)}
                >
                  {item.icon}
                  <span>{item.title}</span>
                </CommandItem>
              ))}
            </CommandGroup>
            {resourceItems && resourceItems.length > 0 && (
              <CommandGroup heading="Resources">
                {resourceItems.map((item) => (
                  <CommandItem
                    key={item.id}
                    value={formatTitle(item.name)}
                    onSelect={() => handleSelect(item.url)}
                  >
                    <ResourceIcon item={item} />
                    <span>{formatTitle(item.name)}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            )}
          </CommandList>
        </Command>
      </CommandDialog>
    </>
  )
}
