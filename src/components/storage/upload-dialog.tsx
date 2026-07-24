import { useEffect, useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { CircleAlertIcon, UploadIcon } from "lucide-react"
import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "#/components/ui/sheet"
import { useFileUpload } from "#/hooks/use-file-upload"
import { useIsMobile } from "#/hooks/use-mobile"
import {
  sanitizeStorageKey,
  storageUploadMutationOptions,
} from "#/lib/supabase/data/storage"
import { cn } from "#/lib/utils"

import { UploadDropzone } from "./upload-dropzone"
import { UploadFilesPanel } from "./upload-files-panel"

interface UploadDialogProps {
  bucketId: string
  path: string[]
  onSuccess?: () => void
}

export function UploadDialog({ bucketId, path, onSuccess }: UploadDialogProps) {
  const [open, setOpen] = useState(false)
  const queryClient = useQueryClient()
  const isMobile = useIsMobile()
  const side = isMobile ? "bottom" : "right"

  const { mutateAsync: upload, isPending } = useMutation(
    storageUploadMutationOptions
  )

  const [
    { files, isDragging, errors },
    {
      removeFile,
      clearFiles,
      handleDragEnter,
      handleDragLeave,
      handleDragOver,
      handleDrop,
      openFileDialog,
      getInputProps,
    },
  ] = useFileUpload({ multiple: true })

  // Reset files when sheet closes
  useEffect(() => {
    if (!open) clearFiles()
  }, [open])

  const handleUpload = async () => {
    if (!files.length) return
    const folderPath = path.join("/")
    try {
      await Promise.all(
        files.map(({ file }) => {
          if (!(file instanceof File)) return Promise.resolve()
          const safeName = sanitizeStorageKey(file.name)
          const filePath = folderPath ? `${folderPath}/${safeName}` : safeName
          return upload({ bucketId, path: filePath, file, upsert: true })
        })
      )
      await queryClient.invalidateQueries({
        queryKey: ["storage", "files", bucketId],
      })
      toast.success(
        `${files.length} ${files.length === 1 ? "file" : "files"} uploaded`
      )
      setOpen(false)
      onSuccess?.()
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to upload files")
    }
  }

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger render={<Button size="sm" variant="outline" />}>
        <UploadIcon className="mr-1.5 size-3.5" />
        Upload
      </SheetTrigger>
      <SheetContent
        side={side}
        className={cn(
          "flex flex-col",
          side === "right" && "w-full! sm:max-w-lg!",
          side === "bottom" && "max-h-[80vh] overflow-hidden"
        )}
      >
        <SheetHeader>
          <SheetTitle>Upload Files</SheetTitle>
        </SheetHeader>

        <div className="flex flex-1 flex-col gap-4 overflow-y-auto px-4 pb-2">
          <input {...getInputProps()} className="sr-only" />

          {files.length === 0 && (
            <UploadDropzone
              isDragging={isDragging}
              openFileDialog={openFileDialog}
              onDragEnter={handleDragEnter}
              onDragLeave={handleDragLeave}
              onDragOver={handleDragOver}
              onDrop={handleDrop}
            />
          )}

          {files.length > 0 && (
            <UploadFilesPanel
              files={files}
              onRemoveFile={removeFile}
              onAddFiles={openFileDialog}
              onClearFiles={clearFiles}
              onDragEnter={handleDragEnter}
              onDragLeave={handleDragLeave}
              onDragOver={handleDragOver}
              onDrop={handleDrop}
            />
          )}

          {errors.length > 0 && (
            <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-destructive">
              <div className="flex items-start gap-2">
                <CircleAlertIcon className="mt-0.5 size-4 shrink-0" />
                <div className="space-y-1">
                  {errors.map((error, i) => (
                    <p key={i}>{error}</p>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>

        <SheetFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Cancel
          </Button>
          <Button onClick={handleUpload} disabled={!files.length || isPending}>
            {isPending ? "Uploading…" : "Upload"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  )
}
