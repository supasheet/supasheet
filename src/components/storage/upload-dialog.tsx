import { useEffect, useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import {
  CircleAlertIcon,
  CloudUploadIcon,
  FileArchiveIcon,
  FileSpreadsheetIcon,
  FileTextIcon,
  HeadphonesIcon,
  ImageIcon,
  Trash2Icon,
  UploadIcon,
  VideoIcon,
} from "lucide-react"
import { toast } from "sonner"

import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import {
  Sheet,
  SheetContent,
  SheetFooter,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "#/components/ui/sheet"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import { formatBytes, useFileUpload } from "#/hooks/use-file-upload"
import type { FileWithPreview } from "#/hooks/use-file-upload"
import { useIsMobile } from "#/hooks/use-mobile"
import {
  sanitizeStorageKey,
  storageUploadMutationOptions,
} from "#/lib/supabase/data/storage"
import { cn } from "#/lib/utils"

interface UploadDialogProps {
  bucketId: string
  path: string[]
  onSuccess?: () => void
}

function getFileIcon(file: File) {
  if (file.type.startsWith("image/")) return <ImageIcon className="size-4" />
  if (file.type.startsWith("video/")) return <VideoIcon className="size-4" />
  if (file.type.startsWith("audio/"))
    return <HeadphonesIcon className="size-4" />
  if (file.type.includes("pdf")) return <FileTextIcon className="size-4" />
  if (file.type.includes("word") || file.type.includes("doc"))
    return <FileTextIcon className="size-4" />
  if (file.type.includes("excel") || file.type.includes("sheet"))
    return <FileSpreadsheetIcon className="size-4" />
  if (file.type.includes("zip") || file.type.includes("rar"))
    return <FileArchiveIcon className="size-4" />
  return <FileTextIcon className="size-4" />
}

function getFileTypeLabel(file: File) {
  if (file.type.startsWith("image/")) return "Image"
  if (file.type.startsWith("video/")) return "Video"
  if (file.type.startsWith("audio/")) return "Audio"
  if (file.type.includes("pdf")) return "PDF"
  if (file.type.includes("word") || file.type.includes("doc")) return "Word"
  if (file.type.includes("excel") || file.type.includes("sheet")) return "Excel"
  if (file.type.includes("zip") || file.type.includes("rar")) return "Archive"
  if (file.type.includes("json")) return "JSON"
  if (file.type.includes("text")) return "Text"
  return "File"
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

          {/* Empty state */}
          {files.length === 0 && (
            <div
              className={cn(
                "flex h-fit rounded-lg border border-dashed transition-colors",
                isDragging
                  ? "border-primary bg-primary/5"
                  : "border-muted-foreground/25"
              )}
              onDragEnter={handleDragEnter}
              onDragLeave={handleDragLeave}
              onDragOver={handleDragOver}
              onDrop={handleDrop}
            >
              <Empty>
                <EmptyMedia
                  className={cn(
                    "size-12 rounded-full transition-colors",
                    isDragging ? "bg-primary/10" : "bg-muted"
                  )}
                >
                  <UploadIcon className="size-5 text-muted-foreground" />
                </EmptyMedia>
                <EmptyContent>
                  <EmptyTitle>Drop files here</EmptyTitle>
                  <EmptyDescription>
                    Drag & drop or{" "}
                    <button
                      type="button"
                      onClick={openFileDialog}
                      className="cursor-pointer text-primary underline-offset-4 hover:underline"
                    >
                      browse files
                    </button>{" "}
                    to upload
                  </EmptyDescription>
                  <Button
                    onClick={openFileDialog}
                    variant="outline"
                    size="sm"
                    className="mt-1"
                  >
                    <CloudUploadIcon className="size-4" />
                    Add files
                  </Button>
                </EmptyContent>
              </Empty>
            </div>
          )}

          {/* Files table */}
          {files.length > 0 && (
            <div
              className="space-y-3"
              onDragEnter={handleDragEnter}
              onDragLeave={handleDragLeave}
              onDragOver={handleDragOver}
              onDrop={handleDrop}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">
                  Files ({files.length})
                </span>
                <div className="flex gap-2">
                  <Button onClick={openFileDialog} variant="outline" size="sm">
                    <CloudUploadIcon className="size-4" />
                    Add files
                  </Button>
                  <Button onClick={clearFiles} variant="outline" size="sm">
                    <Trash2Icon className="size-4" />
                    Remove all
                  </Button>
                </div>
              </div>

              <div className="rounded-lg border">
                <Table>
                  <TableHeader>
                    <TableRow className="text-xs">
                      <TableHead className="h-9 ps-4">Name</TableHead>
                      <TableHead className="h-9">Type</TableHead>
                      <TableHead className="h-9">Size</TableHead>
                      <TableHead className="h-9 w-12" />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {files.map(({ id, file }: FileWithPreview) => {
                      if (!(file instanceof File)) return null
                      return (
                        <TableRow key={id}>
                          <TableCell className="py-2 ps-4">
                            <div className="flex items-center gap-2">
                              <span className="text-muted-foreground">
                                {getFileIcon(file)}
                              </span>
                              <span className="truncate text-sm font-medium">
                                {file.name}
                              </span>
                            </div>
                          </TableCell>
                          <TableCell className="py-2">
                            <Badge variant="secondary" className="text-xs">
                              {getFileTypeLabel(file)}
                            </Badge>
                          </TableCell>
                          <TableCell className="py-2 text-sm text-muted-foreground">
                            {formatBytes(file.size)}
                          </TableCell>
                          <TableCell className="py-2">
                            <Button
                              onClick={() => removeFile(id)}
                              variant="ghost"
                              size="icon"
                              className="size-8"
                            >
                              <Trash2Icon className="size-3.5" />
                            </Button>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            </div>
          )}

          {/* Errors */}
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
