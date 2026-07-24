import type { DragEvent } from "react"

import { CloudUploadIcon, UploadIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { cn } from "#/lib/utils"

export function UploadDropzone({
  isDragging,
  openFileDialog,
  onDragEnter,
  onDragLeave,
  onDragOver,
  onDrop,
}: {
  isDragging: boolean
  openFileDialog: () => void
  onDragEnter: (e: DragEvent<HTMLElement>) => void
  onDragLeave: (e: DragEvent<HTMLElement>) => void
  onDragOver: (e: DragEvent<HTMLElement>) => void
  onDrop: (e: DragEvent<HTMLElement>) => void
}) {
  return (
    <div
      className={cn(
        "flex h-fit rounded-lg border border-dashed transition-colors",
        isDragging
          ? "border-primary bg-primary/5"
          : "border-muted-foreground/25"
      )}
      onDragEnter={onDragEnter}
      onDragLeave={onDragLeave}
      onDragOver={onDragOver}
      onDrop={onDrop}
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
  )
}
