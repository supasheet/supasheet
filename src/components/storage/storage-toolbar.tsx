import { useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { RefreshCwIcon, SearchIcon, TrashIcon } from "lucide-react"
import { toast } from "sonner"

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "#/components/ui/alert-dialog"
import { Button } from "#/components/ui/button"
import { Input } from "#/components/ui/input"
import { storageDeleteMutationOptions } from "#/lib/supabase/data/storage"

import { CreateFolderDialog } from "./create-folder-dialog"
import { UploadDialog } from "./upload-dialog"

interface StorageToolbarProps {
  bucketId: string
  currentPath: string[]
  selectedItems: Set<string>
  onClearSelection: () => void
  search: string
  onSearchChange: (value: string) => void
}

export function StorageToolbar({
  bucketId,
  currentPath,
  selectedItems,
  onClearSelection,
  search,
  onSearchChange,
}: StorageToolbarProps) {
  const [deleteOpen, setDeleteOpen] = useState(false)
  const queryClient = useQueryClient()

  const { mutateAsync: deleteFiles, isPending: isDeleting } = useMutation(
    storageDeleteMutationOptions
  )

  const handleDeleteSelected = async () => {
    const folderPath = currentPath.join("/")
    const paths = Array.from(selectedItems).map((name) =>
      folderPath ? `${folderPath}/${name}` : name
    )
    try {
      await deleteFiles({ bucketId, paths })
      await queryClient.invalidateQueries({
        queryKey: ["storage", "files", bucketId],
      })
      toast.success(`${paths.length} item(s) deleted`)
      onClearSelection()
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Delete failed")
    } finally {
      setDeleteOpen(false)
    }
  }

  const handleRefresh = () => {
    queryClient.invalidateQueries({ queryKey: ["storage", "files", bucketId] })
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative max-w-sm min-w-48 flex-1">
          <SearchIcon className="absolute top-1/2 left-2.5 size-3.5 -translate-y-1/2 text-muted-foreground" />
          <Input
            className="h-8 pl-8 text-sm"
            placeholder="Search files…"
            value={search}
            onChange={(e) => onSearchChange(e.target.value)}
          />
        </div>
        <div className="ml-auto flex items-center gap-1.5">
          {selectedItems.size > 0 && (
            <Button
              size="sm"
              variant="destructive"
              onClick={() => setDeleteOpen(true)}
            >
              <TrashIcon className="mr-1.5 size-3.5" />
              Delete ({selectedItems.size})
            </Button>
          )}
          <UploadDialog bucketId={bucketId} path={currentPath} />
          <CreateFolderDialog bucketId={bucketId} path={currentPath} />
          <Button size="sm" variant="ghost" onClick={handleRefresh}>
            <RefreshCwIcon className="size-3.5" />
          </Button>
        </div>
      </div>

      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Delete {selectedItems.size} item(s)?
            </AlertDialogTitle>
            <AlertDialogDescription>
              This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDeleteOpen(false)}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={handleDeleteSelected}
              disabled={isDeleting}
            >
              {isDeleting ? "Deleting…" : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
