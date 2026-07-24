import * as React from "react"

import { UploadIcon } from "lucide-react"

import { IMPORT_FILE_ACCEPT } from "#/lib/import"

export function ResourceImportDropzone({
  onFile,
}: {
  onFile: (file: File) => void
}) {
  const fileInputRef = React.useRef<HTMLInputElement>(null)

  function handleDrop(e: React.DragEvent) {
    e.preventDefault()
    const file = e.dataTransfer.files[0]
    if (file) onFile(file)
  }

  return (
    <div
      className="flex flex-1 flex-col items-center justify-center gap-3 rounded-lg border-2 border-dashed p-10 text-center transition-colors hover:border-primary/50"
      onDragOver={(e) => e.preventDefault()}
      onDrop={handleDrop}
    >
      <UploadIcon className="text-muted-foreground size-8" />
      <div className="text-sm">
        <span className="text-muted-foreground">
          Drag & drop a file here, or{" "}
        </span>
        <button
          type="button"
          className="text-primary underline-offset-4 hover:underline"
          onClick={() => fileInputRef.current?.click()}
        >
          browse
        </button>
      </div>
      <p className="text-muted-foreground text-xs">
        Supports .csv, .tsv, and .json files
      </p>
      <input
        ref={fileInputRef}
        type="file"
        accept={IMPORT_FILE_ACCEPT}
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0]
          if (file) onFile(file)
          e.target.value = ""
        }}
      />
    </div>
  )
}
