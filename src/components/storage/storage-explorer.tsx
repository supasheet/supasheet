import { useMemo, useState } from "react"

import { useQuery } from "@tanstack/react-query"

import { Skeleton } from "#/components/ui/skeleton"
import { storageFilesQueryOptions } from "#/lib/supabase/data/storage"

import { StorageBreadcrumb } from "./storage-breadcrumb"
import { StorageList } from "./storage-list"
import { StorageToolbar } from "./storage-toolbar"

interface StorageExplorerProps {
  bucketId: string
  isPublic: boolean
  initialPath?: string[]
}

export function StorageExplorer({
  bucketId,
  isPublic,
  initialPath,
}: StorageExplorerProps) {
  const [path, setPath] = useState<string[]>(() => initialPath ?? [])
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set())
  const [search, setSearch] = useState("")

  const currentPathStr = path.join("/")

  const { data: items = [], isLoading } = useQuery(
    storageFilesQueryOptions(bucketId, currentPathStr)
  )

  const filtered = useMemo(() => {
    if (!search.trim()) return items
    return items.filter((i) =>
      i.name.toLowerCase().includes(search.toLowerCase())
    )
  }, [items, search])

  const navigateInto = (folderName: string) => {
    setPath((prev) => [...prev, folderName])
    setSelectedItems(new Set())
    setSearch("")
  }

  const navigateTo = (index: number) => {
    // index = -1 means bucket root, otherwise navigate to that path segment
    setPath((prev) => (index === -1 ? [] : prev.slice(0, index + 1)))
    setSelectedItems(new Set())
    setSearch("")
  }

  const handleSelectItem = (name: string, selected: boolean) => {
    setSelectedItems((prev) => {
      const next = new Set(prev)
      if (selected) next.add(name)
      else next.delete(name)
      return next
    })
  }

  const handleSelectAll = (selected: boolean) => {
    if (selected) {
      setSelectedItems(
        new Set(filtered.filter((i) => i.name !== ".keep").map((i) => i.name))
      )
    } else {
      setSelectedItems(new Set())
    }
  }

  return (
    <div className="flex h-full flex-col gap-3">
      <StorageBreadcrumb
        bucketId={bucketId}
        path={path}
        onNavigate={navigateTo}
      />
      <StorageToolbar
        bucketId={bucketId}
        currentPath={path}
        items={filtered}
        selectedItems={selectedItems}
        onClearSelection={() => setSelectedItems(new Set())}
        search={search}
        onSearchChange={setSearch}
      />
      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </div>
      ) : (
        <StorageList
          bucketId={bucketId}
          isPublic={isPublic}
          items={filtered}
          currentPath={path}
          selectedItems={selectedItems}
          onSelectItem={handleSelectItem}
          onSelectAll={handleSelectAll}
          onNavigate={navigateInto}
        />
      )}
    </div>
  )
}
