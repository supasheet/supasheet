import { useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "#/components/ui/dialog"
import { Input } from "#/components/ui/input"
import { Label } from "#/components/ui/label"
import {
  storageMoveMutationOptions,
  storageRenameFolderMutationOptions,
} from "#/lib/supabase/data/storage"

interface RenameDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  bucketId: string
  currentPath: string
  currentName: string
  isFolder?: boolean
  onSuccess?: () => void
}

export function RenameDialog({
  open,
  onOpenChange,
  bucketId,
  currentPath,
  currentName,
  isFolder = false,
  onSuccess,
}: RenameDialogProps) {
  const [name, setName] = useState(currentName)
  const queryClient = useQueryClient()

  const { mutateAsync: moveFile, isPending: isMoving } = useMutation(
    storageMoveMutationOptions
  )
  const { mutateAsync: renameFolder, isPending: isRenamingFolder } =
    useMutation(storageRenameFolderMutationOptions)
  const isPending = isMoving || isRenamingFolder

  const handleRename = async () => {
    const trimmed = name.trim()
    if (!trimmed || trimmed === currentName) {
      onOpenChange(false)
      return
    }
    const dir = currentPath.substring(0, currentPath.lastIndexOf("/"))
    const toPath = dir ? `${dir}/${trimmed}` : trimmed
    try {
      if (isFolder) {
        await renameFolder({
          bucketId,
          fromFolder: currentPath,
          toFolder: toPath,
        })
      } else {
        await moveFile({ bucketId, fromPath: currentPath, toPath })
      }
      await queryClient.invalidateQueries({
        queryKey: ["storage", "files", bucketId],
      })
      toast.success("Item renamed")
      onOpenChange(false)
      onSuccess?.()
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to rename item")
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Rename</DialogTitle>
        </DialogHeader>
        <div className="space-y-2">
          <Label htmlFor="rename-input">New name</Label>
          <Input
            id="rename-input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") handleRename()
            }}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleRename} disabled={!name.trim() || isPending}>
            {isPending ? "Renaming…" : "Rename"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
