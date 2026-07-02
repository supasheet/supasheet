import { Link } from "@tanstack/react-router"

import {
  FileIcon,
  FileTextIcon,
  FolderIcon,
  ImageIcon,
  VideoIcon,
} from "lucide-react"

import { Checkbox } from "#/components/ui/checkbox"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import { formatFileSize } from "#/lib/files"
import { formatDate } from "#/lib/format"
import type { FileObject } from "#/lib/supabase/data/storage"

import { FileActionsMenu } from "./file-actions-menu"

interface StorageListProps {
  bucketId: string
  isPublic: boolean
  items: FileObject[]
  currentPath: string[]
  selectedItems: Set<string>
  onSelectItem: (name: string, selected: boolean) => void
  onSelectAll: (selected: boolean) => void
  onNavigate: (name: string) => void
}

function fileIcon(item: FileObject) {
  if (!item.id) return <FolderIcon className="size-4 text-muted-foreground" />
  const mime: string = item.metadata?.mimetype ?? ""
  if (mime.startsWith("image/"))
    return <ImageIcon className="size-4 text-blue-500" />
  if (mime.startsWith("video/"))
    return <VideoIcon className="size-4 text-purple-500" />
  if (mime.startsWith("text/"))
    return <FileTextIcon className="size-4 text-green-500" />
  return <FileIcon className="size-4 text-muted-foreground" />
}

export function StorageList({
  bucketId,
  isPublic,
  items,
  currentPath,
  selectedItems,
  onSelectItem,
  onSelectAll,
  onNavigate,
}: StorageListProps) {
  const files = items.filter((i) => i.name !== ".keep")
  const allSelected =
    files.length > 0 && files.every((i) => selectedItems.has(i.name))
  const someSelected = files.some((i) => selectedItems.has(i.name))

  if (files.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia>
            <FolderIcon className="opacity-30" />
          </EmptyMedia>
          <EmptyTitle>This folder is empty</EmptyTitle>
          <EmptyDescription>
            Upload files or create a folder to get started.
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="w-10 ps-4">
            <Checkbox
              checked={allSelected}
              indeterminate={someSelected && !allSelected}
              onCheckedChange={(checked) => onSelectAll(!!checked)}
              aria-label="Select all"
            />
          </TableHead>
          <TableHead>Name</TableHead>
          <TableHead className="w-28">Size</TableHead>
          <TableHead className="hidden w-44 md:table-cell">
            Last modified
          </TableHead>
          <TableHead className="w-10" />
        </TableRow>
      </TableHeader>
      <TableBody>
        {files.map((item) => {
          const isFolder = !item.id
          const size = item.metadata?.size
          const updatedAt = item.updated_at ?? undefined

          return (
            <TableRow key={item.name} className="group/row">
              <TableCell className="ps-4">
                <Checkbox
                  checked={selectedItems.has(item.name)}
                  onCheckedChange={(checked) =>
                    onSelectItem(item.name, !!checked)
                  }
                  aria-label={`Select ${item.name}`}
                />
              </TableCell>
              <TableCell>
                {isFolder ? (
                  <button
                    className="flex items-center gap-2 hover:underline"
                    onClick={() => onNavigate(item.name)}
                  >
                    {fileIcon(item)}
                    <span className="max-w-xs truncate">{item.name}</span>
                  </button>
                ) : (
                  <Link
                    to="/storage/$bucketId/$"
                    params={{
                      bucketId,
                      _splat: [...currentPath, item.name].join("/"),
                    }}
                    mask={{ to: "/storage/$bucketId", params: { bucketId } }}
                    className="flex items-center gap-2 hover:underline"
                  >
                    {fileIcon(item)}
                    <span className="max-w-xs truncate">{item.name}</span>
                  </Link>
                )}
              </TableCell>
              <TableCell className="text-muted-foreground tabular-nums">
                {isFolder ? "—" : size === undefined ? "—" : formatFileSize(size)}
              </TableCell>
              <TableCell className="hidden text-muted-foreground md:table-cell">
                {updatedAt
                  ? formatDate(updatedAt, {
                      dateStyle: "medium",
                      timeStyle: "short",
                    })
                  : "—"}
              </TableCell>
              <TableCell>
                <FileActionsMenu
                  bucketId={bucketId}
                  isPublic={isPublic}
                  item={item}
                  currentPath={currentPath}
                />
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
    </Table>
  )
}
