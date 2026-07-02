"use client"

import { useCallback, useState } from "react"

import { CircleUserRoundIcon, XIcon } from "lucide-react"
import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import { useFileUpload } from "#/hooks/use-file-upload"
import type { FileMetadata, FileWithPreview } from "#/hooks/use-file-upload"
import type { AvatarColumnMetadata } from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"
import type { FileFieldProps, FileObject, UploadProgress } from "#/types/fields"

import { useFieldContext } from "../form-hook"
import {
  deleteFileFromStorage,
  uploadFileToStorage,
} from "./file-field-storage"

export function AvatarField({ columnMetadata, columnSchema }: FileFieldProps) {
  const field = useFieldContext<unknown>()
  const config = JSON.parse(
    columnSchema.comment ?? "{}"
  ) as AvatarColumnMetadata
  const maxSize = config.maxSize ?? 5 * 1024 * 1024

  const [uploadProgress, setUploadProgress] = useState<UploadProgress | null>(
    null
  )

  const storagePath = `${columnSchema.schema}/${columnSchema.table}/${columnSchema.name}`

  const currentValue = field.state.value as FileObject | null

  const loadInitialFile = useCallback((): FileMetadata[] => {
    if (!currentValue || typeof currentValue !== "object") return []

    return [
      {
        name: currentValue.name,
        size: currentValue.size,
        type: currentValue.type,
        url: currentValue.url,
        id: currentValue.url,
      },
    ]
  }, [currentValue])

  const handleFileAdded = useCallback(
    (addedFiles: FileWithPreview[]) => {
      const fileWithPreview = addedFiles[0]
      if (!fileWithPreview || !(fileWithPreview.file instanceof File)) return

      const file = fileWithPreview.file
      const fileId = fileWithPreview.id

      setUploadProgress({ fileId, progress: 0, completed: false })
      ;(async () => {
        try {
          const url = await uploadFileToStorage(
            supabase,
            file,
            storagePath,
            (progress) => {
              setUploadProgress({ fileId, progress, completed: false })
            }
          )

          field.handleChange({
            name: file.name,
            type: file.type,
            size: file.size,
            url,
            last_modified: new Date(file.lastModified).toISOString(),
          })

          setUploadProgress({ fileId, progress: 100, completed: true })
          setTimeout(() => setUploadProgress(null), 1000)
        } catch (error) {
          setUploadProgress({
            fileId,
            progress: 0,
            completed: false,
            error: error instanceof Error ? error.message : "Upload failed",
          })
        }
      })()
    },
    [storagePath, field]
  )

  const handleFileRemoved = useCallback(
    async (fileUrl?: string) => {
      setUploadProgress(null)

      if (!fileUrl) {
        field.handleChange(null)
        return
      }

      try {
        await deleteFileFromStorage(supabase, fileUrl)

        field.handleChange(null)
      } catch (error) {
        console.error("Failed to delete avatar:", error)
        toast.error("Failed to delete avatar")
      }
    },
    [field]
  )

  const [
    { files, isDragging },
    {
      handleDragEnter,
      handleDragLeave,
      handleDragOver,
      handleDrop,
      openFileDialog,
      removeFile,
      getInputProps,
    },
  ] = useFileUpload({
    multiple: false,
    maxSize,
    maxFiles: 1,
    accept: "image/*",
    initialFiles: loadInitialFile(),
    onFilesAdded: handleFileAdded,
  })

  const previewUrl = files[0]?.preview || currentValue?.url || null

  return (
    <div className="flex flex-col items-start gap-2">
      <div className="relative inline-flex">
        <button
          type="button"
          className="relative flex size-24 items-center justify-center overflow-hidden rounded-full border border-dashed border-input transition-colors outline-none hover:bg-accent/50 focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 has-[img]:border-none data-[dragging=true]:bg-accent/50"
          onClick={openFileDialog}
          onDragEnter={handleDragEnter}
          onDragLeave={handleDragLeave}
          onDragOver={handleDragOver}
          onDrop={handleDrop}
          data-dragging={isDragging || undefined}
          disabled={columnMetadata.disabled}
          aria-label={previewUrl ? "Change avatar" : "Upload avatar"}
        >
          {previewUrl ? (
            <img
              className="size-full object-cover"
              src={previewUrl}
              alt="Avatar"
              width={96}
              height={96}
              style={{ objectFit: "cover" }}
            />
          ) : (
            <div aria-hidden="true">
              <CircleUserRoundIcon className="size-6 opacity-60" />
            </div>
          )}

          {uploadProgress && !uploadProgress.completed && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/50">
              <div className="text-xs text-white">
                {uploadProgress.progress}%
              </div>
            </div>
          )}
        </button>

        {previewUrl && !columnMetadata.disabled && (
          <Button
            type="button"
            onClick={() => {
              const file = files[0]
              const fileUrl =
                file && !(file.file instanceof File)
                  ? file.file.url
                  : currentValue?.url
              handleFileRemoved(fileUrl || undefined)
              if (file) removeFile(file.id)
            }}
            size="icon"
            className="absolute -top-1 -right-1 size-6 rounded-full border-2 border-background shadow-none focus-visible:border-background"
            aria-label="Remove avatar"
          >
            <XIcon className="size-3.5" />
          </Button>
        )}

        <input
          {...getInputProps()}
          disabled={columnMetadata.disabled}
          className="sr-only"
          aria-label="Upload avatar image file"
          tabIndex={-1}
        />
      </div>

      {uploadProgress?.error && (
        <p className="text-xs text-destructive" role="alert">
          {uploadProgress.error}
        </p>
      )}
    </div>
  )
}
