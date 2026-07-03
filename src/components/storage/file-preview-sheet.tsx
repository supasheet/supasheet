import { useQuery } from "@tanstack/react-query"

import {
  FileAudioIcon,
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

const MAX_TEXT_PREVIEW_BYTES = 1024 * 1024

// prettier-ignore
const IMAGE_EXTS = new Set(["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "ico"])
const VIDEO_EXTS = new Set(["mp4", "webm", "mov", "mkv", "avi", "m4v"])
const AUDIO_EXTS = new Set(["mp3", "wav", "ogg", "m4a", "flac", "aac"])
// prettier-ignore
const TEXT_EXTS = new Set(["txt", "md", "markdown", "json", "csv", "tsv", "log", "xml", "yml", "yaml", "html", "css", "js", "ts", "jsx", "tsx", "sql", "sh", "toml", "ini", "env"])

type PreviewKind = "image" | "video" | "audio" | "pdf" | "text" | null

// Supabase Storage defaults the content type to text/plain when an upload
// doesn't set one, so the stored mimetype can't be trusted on its own —
// prefer the file extension and only fall back to the mimetype.
function getPreviewKind(fileName: string, mime: string): PreviewKind {
  const ext = fileName.includes(".")
    ? fileName.split(".").pop()!.toLowerCase()
    : ""
  if (IMAGE_EXTS.has(ext)) return "image"
  if (VIDEO_EXTS.has(ext)) return "video"
  if (AUDIO_EXTS.has(ext)) return "audio"
  if (ext === "pdf") return "pdf"
  if (TEXT_EXTS.has(ext)) return "text"
  if (mime.startsWith("image/")) return "image"
  if (mime.startsWith("video/")) return "video"
  if (mime.startsWith("audio/")) return "audio"
  if (mime === "application/pdf") return "pdf"
  if (mime.startsWith("text/") || mime === "application/json") return "text"
  return null
}

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

  const segments = filePath.split("/").filter(Boolean)
  const fileName = segments[segments.length - 1]
  const currentPath = segments.slice(0, -1)

  const mime: string = file?.metadata?.mimetype ?? ""
  const kind = getPreviewKind(fileName, mime)
  const isImage = kind === "image"
  const isVideo = kind === "video"
  const isAudio = kind === "audio"
  const isPdf = kind === "pdf"
  const isText = kind === "text"

  const size = file?.metadata?.size
  // Only fetch text content for reasonably small files
  const isTextPreviewable = isText && (size ?? 0) <= MAX_TEXT_PREVIEW_BYTES
  const hasPreview = isImage || isVideo || isAudio || isPdf || isTextPreviewable

  const { data: previewUrl } = useQuery({
    queryKey: ["storage", "preview-url", bucketId, filePath],
    queryFn: () =>
      isPublic
        ? Promise.resolve(getPublicUrl(bucketId, filePath))
        : createSignedUrl(bucketId, filePath),
    enabled: hasPreview && !!file,
    staleTime: 1000 * 50 * 60,
  })

  const { data: textContent } = useQuery({
    queryKey: ["storage", "preview-text", bucketId, filePath],
    queryFn: async () => {
      const res = await fetch(previewUrl!)
      if (!res.ok) throw new Error("Failed to load file content")
      const text = await res.text()
      // Backstop for binary files mislabeled as text: invalid UTF-8
      // decodes to replacement characters
      return text.includes("�") ? null : text
    },
    enabled: isTextPreviewable && !!previewUrl,
    staleTime: 1000 * 50 * 60,
  })

  const fileIconEl = isImage ? (
    <ImageIcon className="size-12 text-blue-500 opacity-50" />
  ) : isVideo ? (
    <VideoIcon className="size-12 text-purple-400 opacity-50" />
  ) : isAudio ? (
    <FileAudioIcon className="size-12 text-amber-400 opacity-50" />
  ) : isText || isPdf ? (
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
          ) : isAudio && previewUrl ? (
            <div className="flex w-full flex-col items-center gap-4 p-8">
              {fileIconEl}
              <audio src={previewUrl} controls className="w-full" />
            </div>
          ) : isPdf && previewUrl ? (
            <iframe src={previewUrl} title={fileName} className="h-72 w-full" />
          ) : isTextPreviewable && typeof textContent === "string" ? (
            <pre className="h-72 w-full overflow-auto p-4 font-mono text-xs whitespace-pre-wrap">
              {textContent}
            </pre>
          ) : hasPreview &&
            (!previewUrl ||
              (isTextPreviewable && textContent === undefined)) ? (
            <Skeleton className="h-full min-h-48 w-full" />
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
