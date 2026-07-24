"use client"

import { useCallback, useState } from "react"

import { AlertCircleIcon, FileUpIcon, XIcon } from "lucide-react"
import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import { useFileUpload } from "#/hooks/use-file-upload"
import type { FileMetadata, FileWithPreview } from "#/hooks/use-file-upload"
import type { FileColumnMetadata } from "#/lib/database-meta.types"
import { formatFileSize, getFileIcon } from "#/lib/files"
import { supabase } from "#/lib/supabase/client"
import { cn } from "#/lib/utils"
import type { FileFieldProps, FileObject, UploadProgress } from "#/types/fields"

import { useFieldContext } from "../form-hook"
import {
  deleteFileFromStorage,
  uploadFileToStorage,
} from "./file-field-storage"

export function FileField({ columnMetadata, columnSchema }: FileFieldProps) {
  const field = useFieldContext<FileObject[]>()
  const config = JSON.parse(columnSchema.comment ?? "{}") as FileColumnMetadata
  const maxSize = config.max_size ?? 5 * 1024 * 1024
  const maxFiles = config.max_files ?? 1
  const accept = config.accept ?? "*"

  const storagePath = `${columnSchema.schema}/${columnSchema.table}/${columnSchema.name}`

  const [_, setUploadProgress] = useState<UploadProgress[]>([])

  const currentFiles = field.state.value as FileObject[] | null

  const loadInitialFiles = useCallback((): FileMetadata[] => {
    if (!currentFiles?.length) return []

    return currentFiles
      .map((file) => {
        if (!file || typeof file !== "object") return null
        return {
          name: file.name,
          size: file.size,
          type: file.type,
          url: file.url,
          id: file.url,
        }
      })
      .filter((item): item is FileMetadata => item !== null)
  }, [currentFiles])

  const handleFilesAdded = useCallback(
    (addedFiles: FileWithPreview[]) => {
      const newProgressItems = addedFiles.map((file) => ({
        fileId: file.id,
        progress: 0,
        completed: false,
      }))
      setUploadProgress((prev) => [...prev, ...newProgressItems])

      addedFiles.forEach(async (fileWithPreview) => {
        if (!(fileWithPreview.file instanceof File)) return

        try {
          const url = await uploadFileToStorage(
            supabase,
            fileWithPreview.file,
            storagePath,
            (progress) => {
              setUploadProgress((prev) =>
                prev.map((item) =>
                  item.fileId === fileWithPreview.id
                    ? { ...item, progress }
                    : item
                )
              )
            }
          )

          field.pushValue({
            name: fileWithPreview.file.name,
            type: fileWithPreview.file.type,
            size: fileWithPreview.file.size,
            url,
            last_modified: new Date(
              fileWithPreview.file.lastModified
            ).toISOString(),
          })

          setUploadProgress((prev) =>
            prev.map((item) =>
              item.fileId === fileWithPreview.id
                ? { ...item, completed: true }
                : item
            )
          )
        } catch (error) {
          setUploadProgress((prev) =>
            prev.map((item) =>
              item.fileId === fileWithPreview.id
                ? {
                    ...item,
                    error:
                      error instanceof Error ? error.message : "Upload failed",
                  }
                : item
            )
          )
        }
      })
    },
    [storagePath, field]
  )

  const handleFileRemoved = useCallback(
    async (fileId: string, fileUrl?: string) => {
      setUploadProgress((prev) => prev.filter((item) => item.fileId !== fileId))

      if (!fileUrl) return

      try {
        await deleteFileFromStorage(supabase, fileUrl)

        const files = field.state.value as FileObject[] | null
        const index = files?.findIndex((file) => file?.url === fileUrl) ?? -1

        if (index !== -1) {
          if (files!.length === 1) {
            field.handleChange(null as unknown as FileObject[])
          } else {
            field.removeValue(index)
          }
        }
      } catch (error) {
        console.error("Failed to delete file:", error)
        toast.error("Failed to delete file")
      }
    },
    [field]
  )

  const [
    { files, isDragging, errors },
    {
      handleDragEnter,
      handleDragLeave,
      handleDragOver,
      handleDrop,
      openFileDialog,
      removeFile,
      clearFiles,
      getInputProps,
    },
  ] = useFileUpload({
    multiple: maxFiles > 1,
    maxSize,
    maxFiles,
    accept,
    initialFiles: loadInitialFiles(),
    onFilesAdded: handleFilesAdded,
  })

  const handleRemoveAll = useCallback(async () => {
    await Promise.all(
      files.map((file) => {
        if (!(file.file instanceof File)) {
          const fileUrl = file.file.url
          return deleteFileFromStorage(supabase, fileUrl).catch(console.error)
        }
        return Promise.resolve()
      })
    )

    setUploadProgress([])
    field.handleChange(null as unknown as FileObject[])
    clearFiles()
  }, [field, files, clearFiles])

  return (
    <div className="flex flex-col gap-2 rounded-md border border-border p-3">
      <div
        onDragEnter={handleDragEnter}
        onDragLeave={handleDragLeave}
        onDragOver={handleDragOver}
        onDrop={handleDrop}
        onClick={openFileDialog}
        data-dragging={isDragging || undefined}
        data-files={files.length > 0 || undefined}
        className={cn(
          "flex cursor-pointer flex-col items-center justify-center gap-2 rounded-md border border-dashed border-input p-6 transition-colors outline-none hover:bg-accent/30 focus-visible:border-ring/50",
          isDragging
            ? "border-primary bg-primary/5"
            : "border-muted-foreground/25"
        )}
      >
        <div className="flex flex-col items-center justify-center text-center">
          <div
            className="mb-2 flex size-11 shrink-0 items-center justify-center rounded-full border bg-background"
            aria-hidden="true"
          >
            <FileUpIcon className="size-4 opacity-60" />
          </div>
          <p className="mb-1.5 text-sm font-medium">Upload files</p>
          <p className="mb-2 text-xs text-muted-foreground">
            Drag & drop or click to browse
          </p>
          <div className="flex flex-wrap justify-center gap-1 text-xs text-muted-foreground/70">
            <span>All files</span>
            <span>∙</span>
            <span>Max {maxFiles} files</span>
            <span>∙</span>
            <span>Up to {formatFileSize(maxSize)}</span>
          </div>
        </div>
      </div>
      <input
        {...getInputProps()}
        disabled={columnMetadata.disabled}
        className="sr-only"
        aria-label="Upload files"
      />

      {errors.length > 0 && (
        <div
          className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive"
          role="alert"
        >
          <AlertCircleIcon className="size-3 shrink-0" />
          <span>{errors[0]}</span>
        </div>
      )}
      {files.length > 0 && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <p className="text-xs font-medium text-muted-foreground">
              {files.length} {files.length === 1 ? "file" : "files"}
            </p>
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="h-6 text-xs text-muted-foreground"
              onClick={handleRemoveAll}
            >
              Clear all
            </Button>
          </div>
          <div className="max-h-[200px] space-y-1 overflow-y-auto">
            {files.map((file) => {
              const FileIcon = getFileIcon(file.file.type)
              const isImage = file.file.type?.startsWith("image/")

              return (
                <div
                  key={file.id}
                  className="flex items-center gap-2 rounded-md border bg-muted/50 px-2 py-1.5"
                >
                  <div className="flex size-10 shrink-0 items-center justify-center overflow-hidden rounded-md border bg-background">
                    {isImage && file.preview ? (
                      <img
                        src={file.preview}
                        alt={file.file.name}
                        className="size-full object-cover"
                      />
                    ) : (
                      <FileIcon className="size-4 text-muted-foreground" />
                    )}
                  </div>
                  <div className="flex-1 overflow-hidden">
                    <p className="truncate text-sm">{file.file.name}</p>
                    <p className="text-xs text-muted-foreground">
                      {formatFileSize(file.file.size)}
                    </p>
                  </div>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="size-5 rounded-sm"
                    onClick={() => {
                      removeFile(file.id)
                      handleFileRemoved(
                        file.id,
                        !(file.file instanceof File) ? file.file.url : undefined
                      )
                    }}
                  >
                    <XIcon className="size-3" />
                  </Button>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
