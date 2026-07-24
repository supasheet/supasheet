import {
  FileArchiveIcon,
  FileAudioIcon,
  FileIcon,
  FileImageIcon,
  FileSpreadsheetIcon,
  FileTextIcon,
  FileVideoIcon,
  PresentationIcon,
} from "lucide-react"

export function formatFileSize(bytes: number): string {
  if (bytes === 0) return "0 B"
  const k = 1024
  const sizes = ["B", "KB", "MB", "GB"]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${Number.parseFloat((bytes / k ** i).toFixed(1))} ${sizes[i]}`
}

export function getFileIcon(
  type: string
): React.ComponentType<React.SVGProps<SVGSVGElement>> {
  if (type.startsWith("image/")) return FileImageIcon
  if (type.startsWith("video/")) return FileVideoIcon
  if (type.startsWith("audio/")) return FileAudioIcon
  if (type.includes("pdf")) return FileTextIcon
  if (type.includes("zip") || type.includes("rar")) return FileArchiveIcon
  if (
    type.includes("word") ||
    type.includes("document") ||
    type.includes("doc")
  )
    return FileTextIcon
  if (type.includes("sheet") || type.includes("excel") || type.includes("xls"))
    return FileSpreadsheetIcon
  if (
    type.includes("presentation") ||
    type.includes("powerpoint") ||
    type.includes("ppt")
  )
    return PresentationIcon
  return FileIcon
}

export function getFileTypeLabel(type: string): string {
  if (type.startsWith("image/")) return "Image"
  if (type.startsWith("video/")) return "Video"
  if (type.startsWith("audio/")) return "Audio"
  if (type.includes("pdf")) return "PDF"
  if (type.includes("zip") || type.includes("rar")) return "Archive"
  if (
    type.includes("word") ||
    type.includes("document") ||
    type.includes("doc")
  )
    return "Word"
  if (type.includes("sheet") || type.includes("excel") || type.includes("xls"))
    return "Excel"
  if (
    type.includes("presentation") ||
    type.includes("powerpoint") ||
    type.includes("ppt")
  )
    return "PowerPoint"
  if (type.includes("json")) return "JSON"
  if (type.includes("text")) return "Text"
  return "File"
}
