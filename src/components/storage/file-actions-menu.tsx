import { useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import {
  CopyIcon,
  DownloadIcon,
  ExternalLinkIcon,
  LinkIcon,
  MoreHorizontalIcon,
  PencilIcon,
  TrashIcon,
} from "lucide-react"
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
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import {
  createSignedUrl,
  downloadFile,
  getPublicUrl,
  storageDeleteMutationOptions,
} from "#/lib/supabase/data/storage"
import type { FileObject } from "#/lib/supabase/data/storage"

import { RenameDialog } from "./rename-dialog"

interface FileActionsMenuProps {
  bucketId: string
  isPublic: boolean
  item: FileObject
  currentPath: string[]
  onNavigate?: () => void
}

export function FileActionsMenu({
  bucketId,
  isPublic,
  item,
  currentPath,
  onNavigate,
}: FileActionsMenuProps) {
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [renameOpen, setRenameOpen] = useState(false)
  const isFolder = !item.id
  const fullPath = [...currentPath, item.name].join("/")

  const queryClient = useQueryClient()
  const { mutateAsync: deleteFiles, isPending: isDeleting } = useMutation(
    storageDeleteMutationOptions
  )

  const handleDelete = async () => {
    const paths = isFolder ? [`${fullPath}/.keep`] : [fullPath]
    try {
      await deleteFiles({ bucketId, paths })
      await queryClient.invalidateQueries({
        queryKey: ["storage", "files", bucketId],
      })
      toast.success(`"${item.name}" deleted`)
      onNavigate?.()
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to delete item")
    } finally {
      setDeleteOpen(false)
    }
  }

  const handleCopyPublicUrl = () => {
    const url = getPublicUrl(bucketId, fullPath)
    navigator.clipboard.writeText(url)
    toast.success("Public URL copied")
  }

  const handleCopySignedUrl = async () => {
    try {
      const url = await createSignedUrl(bucketId, fullPath)
      navigator.clipboard.writeText(url)
      toast.success("Signed URL copied (1 hour)")
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to create signed URL"
      )
    }
  }

  const handleDownload = async () => {
    try {
      const blob = await downloadFile(bucketId, fullPath)
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = item.name
      a.click()
      URL.revokeObjectURL(url)
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to download item"
      )
    }
  }

  const handleOpenPublicUrl = () => {
    const url = getPublicUrl(bucketId, fullPath)
    window.open(url, "_blank")
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button
              variant="ghost"
              size="icon"
              className="size-7 opacity-0 group-hover/row:opacity-100"
            />
          }
        >
          <MoreHorizontalIcon className="size-4" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-44">
          {!isFolder && (
            <>
              <DropdownMenuItem onClick={handleDownload}>
                <DownloadIcon className="mr-2 size-3.5" />
                Download
              </DropdownMenuItem>
              {isPublic && (
                <DropdownMenuItem onClick={handleOpenPublicUrl}>
                  <ExternalLinkIcon className="mr-2 size-3.5" />
                  Open in tab
                </DropdownMenuItem>
              )}
              {isPublic && (
                <DropdownMenuItem onClick={handleCopyPublicUrl}>
                  <CopyIcon className="mr-2 size-3.5" />
                  Copy public URL
                </DropdownMenuItem>
              )}
              <DropdownMenuItem onClick={handleCopySignedUrl}>
                <LinkIcon className="mr-2 size-3.5" />
                Copy signed URL
              </DropdownMenuItem>
              <DropdownMenuSeparator />
            </>
          )}
          <DropdownMenuItem onClick={() => setRenameOpen(true)}>
            <PencilIcon className="mr-2 size-3.5" />
            Rename
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            className="text-destructive focus:text-destructive"
            onClick={() => setDeleteOpen(true)}
          >
            <TrashIcon className="mr-2 size-3.5" />
            Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <RenameDialog
        open={renameOpen}
        onOpenChange={setRenameOpen}
        bucketId={bucketId}
        currentPath={fullPath}
        currentName={item.name}
        isFolder={isFolder}
      />

      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete "{item.name}"?</AlertDialogTitle>
            <AlertDialogDescription>
              This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setDeleteOpen(false)}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={handleDelete}
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
