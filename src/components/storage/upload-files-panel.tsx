import type { DragEvent } from "react"

import { CloudUploadIcon, Trash2Icon } from "lucide-react"

import { Badge } from "#/components/ui/badge"
import { Button } from "#/components/ui/button"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import { formatBytes } from "#/hooks/use-file-upload"
import type { FileWithPreview } from "#/hooks/use-file-upload"
import { getFileIcon, getFileTypeLabel } from "#/lib/files"

export function UploadFilesPanel({
  files,
  onRemoveFile,
  onAddFiles,
  onClearFiles,
  onDragEnter,
  onDragLeave,
  onDragOver,
  onDrop,
}: {
  files: FileWithPreview[]
  onRemoveFile: (id: string) => void
  onAddFiles: () => void
  onClearFiles: () => void
  onDragEnter: (e: DragEvent<HTMLElement>) => void
  onDragLeave: (e: DragEvent<HTMLElement>) => void
  onDragOver: (e: DragEvent<HTMLElement>) => void
  onDrop: (e: DragEvent<HTMLElement>) => void
}) {
  return (
    <div
      className="space-y-3"
      onDragEnter={onDragEnter}
      onDragLeave={onDragLeave}
      onDragOver={onDragOver}
      onDrop={onDrop}
    >
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium">Files ({files.length})</span>
        <div className="flex gap-2">
          <Button onClick={onAddFiles} variant="outline" size="sm">
            <CloudUploadIcon className="size-4" />
            Add files
          </Button>
          <Button onClick={onClearFiles} variant="outline" size="sm">
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
              const Icon = getFileIcon(file.type)
              return (
                <TableRow key={id}>
                  <TableCell className="py-2 ps-4">
                    <div className="flex items-center gap-2">
                      <span className="text-muted-foreground">
                        <Icon className="size-4" />
                      </span>
                      <span className="truncate text-sm font-medium">
                        {file.name}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell className="py-2">
                    <Badge variant="secondary" className="text-xs">
                      {getFileTypeLabel(file.type)}
                    </Badge>
                  </TableCell>
                  <TableCell className="py-2 text-sm text-muted-foreground">
                    {formatBytes(file.size)}
                  </TableCell>
                  <TableCell className="py-2">
                    <Button
                      onClick={() => onRemoveFile(id)}
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
  )
}
