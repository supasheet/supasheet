import { useState } from "react"

import { useRouter } from "@tanstack/react-router"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { CircleAlertIcon, UserIcon, XIcon } from "lucide-react"
import { toast } from "sonner"

import { Alert, AlertDescription, AlertTitle } from "#/components/ui/alert"
import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { formatBytes, useFileUpload } from "#/hooks/use-file-upload"
import type { FileWithPreview } from "#/hooks/use-file-upload"
import { useAuthUser, useUser } from "#/hooks/use-user"
import {
  removeAccountAvatarMutationOptions,
  uploadAccountAvatarMutationOptions,
} from "#/lib/supabase/data/users"
import { cn } from "#/lib/utils"

const MAX_SIZE = 2 * 1024 * 1024

export function ProfileAvatarCard() {
  const user = useUser()
  const authUser = useAuthUser()
  const queryClient = useQueryClient()
  const router = useRouter()
  const [pendingFile, setPendingFile] = useState<FileWithPreview | null>(null)

  const [
    { files, isDragging, errors },
    {
      removeFile,
      handleDragEnter,
      handleDragLeave,
      handleDragOver,
      handleDrop,
      openFileDialog,
      getInputProps,
    },
  ] = useFileUpload({
    maxFiles: 1,
    maxSize: MAX_SIZE,
    accept: "image/*",
    multiple: false,
    onFilesChange: (updatedFiles) => setPendingFile(updatedFiles[0] ?? null),
  })

  const currentFile = files[0] as (typeof files)[0] | undefined
  const previewUrl = currentFile?.preview ?? user?.picture_url ?? undefined

  const { mutate: saveAvatar, isPending: isSaving } = useMutation({
    ...uploadAccountAvatarMutationOptions(authUser!.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({
        queryKey: ["supasheet", "user", authUser!.id],
      })
      await router.invalidate()
      setPendingFile(null)
      toast.success("Avatar updated")
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Failed to update avatar"
      )
    },
  })

  const { mutate: removeAvatar, isPending: isRemoving } = useMutation({
    ...removeAccountAvatarMutationOptions(authUser!.id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({
        queryKey: ["supasheet", "user", authUser!.id],
      })
      await router.invalidate()
      toast.success("Avatar removed")
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Failed to remove avatar"
      )
    },
  })

  const isPending = isSaving || isRemoving

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Avatar</CardTitle>
        <CardDescription>
          Upload a profile picture. PNG or JPG up to {formatBytes(MAX_SIZE)}.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col items-center gap-4 pt-4">
        <div className="relative">
          <div
            className={cn(
              "group/avatar relative h-24 w-24 cursor-pointer overflow-hidden rounded-full border border-dashed transition-colors",
              isDragging
                ? "border-primary bg-primary/5"
                : "border-muted-foreground/25 hover:border-muted-foreground/50",
              previewUrl && "border-solid"
            )}
            onDragEnter={handleDragEnter}
            onDragLeave={handleDragLeave}
            onDragOver={handleDragOver}
            onDrop={handleDrop}
            onClick={openFileDialog}
          >
            <input {...getInputProps()} className="sr-only" />
            {previewUrl ? (
              <img
                src={previewUrl}
                alt="Avatar"
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center">
                <UserIcon className="size-6 text-muted-foreground" />
              </div>
            )}
          </div>
          {currentFile && (
            <Button
              size="icon"
              variant="outline"
              onClick={() => removeFile(currentFile.id)}
              className="absolute end-0.5 top-0.5 z-10 size-6 rounded-full dark:bg-zinc-800 hover:dark:bg-zinc-700"
              aria-label="Remove avatar"
            >
              <XIcon className="size-3.5" />
            </Button>
          )}
        </div>
        <div className="space-y-0.5 text-center">
          <p className="text-sm font-medium">
            {currentFile ? "Avatar ready to save" : "Upload avatar"}
          </p>
          <p className="text-xs text-muted-foreground">
            PNG, JPG up to {formatBytes(MAX_SIZE)}
          </p>
        </div>
        {errors.length > 0 && (
          <Alert variant="destructive">
            <CircleAlertIcon />
            <AlertTitle>Upload error</AlertTitle>
            <AlertDescription>
              {errors.map((e, i) => (
                <p key={i}>{e}</p>
              ))}
            </AlertDescription>
          </Alert>
        )}
      </CardContent>
      <CardFooter className="justify-end gap-2">
        {user?.picture_url && !pendingFile && (
          <Button
            size="sm"
            variant="outline"
            disabled={isPending}
            onClick={() => removeAvatar(user.picture_url!)}
          >
            {isRemoving ? "Removing…" : "Remove avatar"}
          </Button>
        )}
        <Button
          size="sm"
          disabled={!pendingFile || isPending}
          onClick={() => {
            if (pendingFile?.file instanceof File) saveAvatar(pendingFile.file)
          }}
        >
          {isSaving ? "Saving…" : "Save avatar"}
        </Button>
      </CardFooter>
    </Card>
  )
}
