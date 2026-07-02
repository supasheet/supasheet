import { useQuery } from "@tanstack/react-query"

import {
  FileIcon,
  FileTextIcon,
  ImageIcon,
  VideoIcon,
  XIcon,
} from "lucide-react"

import { Button } from "#/components/ui/button"
import { Separator } from "#/components/ui/separator"
import {
  Sheet,
  SheetClose,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "#/components/ui/sheet"
import { Skeleton } from "#/components/ui/skeleton"
import { useIsMobile } from "#/hooks/use-mobile"
import { formatFileSize } from "#/lib/files"
import { formatDate } from "#/lib/format"
import { createSignedUrl, getPublicUrl } from "#/lib/supabase/data/storage"
import type { FileObject } from "#/lib/supabase/data/storage"
import { cn } from "#/lib/utils"

import { FileActionsMenu } from "./file-actions-menu"

interface FilePreviewSheetProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  bucketId: string
  isPublic: boolean
  file: FileObject | null
  filePath: string
  onSuccess?: () => void
}

export function FilePreviewSheet({
  open,
  onOpenChange,
  bucketId,
  isPublic,
  file,
  filePath,
  onSuccess,
}: FilePreviewSheetProps) {
  const isMobile = useIsMobile()
  const side = isMobile ? "bottom" : "right"

  const mime: string = file?.metadata?.mimetype ?? ""
  const isImage = mime.startsWith("image/")
  const isVideo = mime.startsWith("video/")

  const segments = filePath.split("/").filter(Boolean)
  const fileName = segments[segments.length - 1]
  const currentPath = segments.slice(0, -1)

  const { data: previewUrl } = useQuery({
    queryKey: ["storage", "preview-url", bucketId, filePath],
    queryFn: () =>
      isPublic
        ? Promise.resolve(getPublicUrl(bucketId, filePath))
        : createSignedUrl(bucketId, filePath),
    enabled: (isImage || isVideo) && !!file,
    staleTime: 1000 * 50 * 60,
  })

  const size = file?.metadata?.size

  const fileIconEl = isImage ? (
    <ImageIcon className="size-12 text-blue-500 opacity-50" />
  ) : isVideo ? (
    <VideoIcon className="size-12 text-purple-400 opacity-50" />
  ) : mime.startsWith("text/") ? (
    <FileTextIcon className="size-12 text-green-400 opacity-50" />
  ) : (
    <FileIcon className="size-12 text-muted-foreground opacity-50" />
  )

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side={side}
        showCloseButton={false}
        className={cn(
          "flex flex-col gap-0 p-0",
          side === "right" && "sm:max-w-md",
          side === "bottom" && "max-h-[80vh] overflow-hidden"
        )}
      >
        <SheetHeader className="flex flex-row items-center justify-between p-4 pb-3">
          <div className="min-w-0 flex-1">
            <SheetTitle className="truncate text-sm">{fileName}</SheetTitle>
            {mime && (
              <SheetDescription className="truncate text-xs">
                {mime}
              </SheetDescription>
            )}
          </div>
          <div className="flex shrink-0 items-center gap-1">
            {file && (
              <FileActionsMenu
                bucketId={bucketId}
                isPublic={isPublic}
                item={file}
                currentPath={currentPath}
                onNavigate={onSuccess}
              />
            )}
            <SheetClose render={<Button variant="ghost" size="icon-sm" />}>
              <XIcon className="size-4" />
              <span className="sr-only">Close</span>
            </SheetClose>
          </div>
        </SheetHeader>

        <Separator />

        <div className="flex max-h-72 min-h-48 items-center justify-center bg-muted/30">
          {!file ? (
            <Skeleton className="h-full w-full" />
          ) : isImage && previewUrl ? (
            <img
              src={previewUrl}
              alt={fileName}
              className="max-h-72 max-w-full object-contain"
            />
          ) : isVideo && previewUrl ? (
            <video src={previewUrl} controls className="max-h-72 max-w-full" />
          ) : (
            <div className="flex flex-col items-center gap-2 p-8 text-center">
              {fileIconEl}
              <span className="text-xs text-muted-foreground">
                No preview available
              </span>
            </div>
          )}
        </div>

        <Separator />

        <div className="space-y-3 p-4 text-sm">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Size</span>
            {file ? (
              <span>{size === undefined ? "—" : formatFileSize(size)}</span>
            ) : (
              <Skeleton className="h-4 w-16" />
            )}
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Modified</span>
            {file ? (
              <span>
                {file.updated_at
                  ? formatDate(file.updated_at, {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })
                  : "—"}
              </span>
            ) : (
              <Skeleton className="h-4 w-28" />
            )}
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Created</span>
            {file ? (
              <span>
                {file.created_at
                  ? formatDate(file.created_at, {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })
                  : "—"}
              </span>
            ) : (
              <Skeleton className="h-4 w-28" />
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
