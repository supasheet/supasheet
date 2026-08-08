"use client"

import { useCallback, useState } from "react"

import { User, XIcon } from "lucide-react"
import { toast } from "sonner"

import {
  Avatar,
  AvatarBadge,
  AvatarFallback,
  AvatarImage,
} from "#/components/ui/avatar"
import { Input } from "#/components/ui/input"
import type { AvatarColumnMetadata } from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"
import type { FileFieldProps, FileObject } from "#/types/fields"

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
  const maxSize = config.max_size ?? 5 * 1024 * 1024

  const [error, setError] = useState<string | null>(null)

  const storagePath = `${columnSchema.schema}/${columnSchema.table}/${columnSchema.name}`

  const currentValue = field.state.value as FileObject | null

  const handleFileChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0]
      if (!file) return

      if (file.size > maxSize) {
        toast.error("File is too large")
        event.target.value = ""
        return
      }

      setError(null)
      ;(async () => {
        try {
          const url = await uploadFileToStorage(supabase, file, storagePath)

          field.handleChange({
            name: file.name,
            type: file.type,
            size: file.size,
            url,
            last_modified: new Date(file.lastModified).toISOString(),
          })
        } catch (uploadError) {
          setError(
            uploadError instanceof Error ? uploadError.message : "Upload failed"
          )
        }
      })()
    },
    [maxSize, storagePath, field]
  )

  const handleRemoveClick = useCallback(async () => {
    setError(null)

    if (!currentValue?.url) {
      field.handleChange(null)
      return
    }

    try {
      await deleteFileFromStorage(supabase, currentValue.url)
      field.handleChange(null)
    } catch (deleteError) {
      console.error("Failed to delete avatar:", deleteError)
      toast.error("Failed to delete avatar")
    }
  }, [currentValue, field])

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        {currentValue ? (
          <>
            <Avatar>
              <AvatarImage src={currentValue.url} alt={currentValue.name} />
              <AvatarFallback>
                <User className="size-4" />
              </AvatarFallback>
              {!columnMetadata.disabled && (
                <AvatarBadge
                  role="button"
                  tabIndex={0}
                  className="cursor-pointer bg-destructive"
                  onClick={handleRemoveClick}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" || event.key === " ") {
                      event.preventDefault()
                      handleRemoveClick()
                    }
                  }}
                  aria-label={`Remove ${currentValue.name}`}
                >
                  <XIcon />
                </AvatarBadge>
              )}
            </Avatar>
            <p className="truncate text-sm text-muted-foreground">
              {currentValue.name}
            </p>
          </>
        ) : (
          <Input
            type="file"
            accept="image/*"
            disabled={columnMetadata.disabled}
            onChange={handleFileChange}
          />
        )}
      </div>

      {error && (
        <p className="text-xs text-destructive" role="alert">
          {error}
        </p>
      )}
    </div>
  )
}
