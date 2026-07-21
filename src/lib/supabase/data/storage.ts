import { mutationOptions, queryOptions } from "@tanstack/react-query"

import type { FileObject, SearchOptions } from "@supabase/storage-js"

import type { IconName } from "#/lib/database-meta.types"
import { supabase } from "#/lib/supabase/client"

export type { FileObject }

// Supabase Storage allows: word chars, /, !, -, ., *, ', (, ), space, &, $, @, =, ;, :, +, ,, ?
// macOS screenshot filenames use U+202F (narrow no-break space) before AM/PM — NFKC
// normalizes that to a regular space; anything else outside the allowed set becomes "_".
export function sanitizeStorageKey(key: string): string {
  return key.normalize("NFKC").replace(/[^\w!\-.*'() &$@=;:+,?/]/g, "_")
}

export const storageBucketsQueryOptions = queryOptions({
  queryKey: ["storage", "buckets"],
  queryFn: async () => {
    const { data, error } = await supabase.storage.listBuckets()
    if (error) throw error

    return (data ?? []).map((bucket) => {
      const icon: IconName = bucket.public ? "FolderOpenIcon" : "FolderLockIcon"
      return {
        name: bucket.name,
        id: bucket.id,
        schema: "storage",
        type: "table" as const,
        meta: {
          label: bucket.name,
          icon,
        },
        isPublic: bucket.public,
      }
    })
  },
  staleTime: 1000 * 60 * 5,
})

export const storageFilesQueryOptions = (
  bucketId: string,
  path: string,
  opts?: SearchOptions
) =>
  queryOptions({
    queryKey: ["storage", "files", bucketId, path, opts],
    queryFn: async () => {
      const { data, error } = await supabase.storage
        .from(bucketId)
        .list(path || undefined, {
          limit: 100,
          offset: 0,
          sortBy: { column: "name", order: "asc" },
          ...opts,
        })
      if (error) throw error
      return data ?? []
    },
    staleTime: 1000 * 30,
    enabled: !!bucketId,
  })

export const storageUploadMutationOptions = mutationOptions({
  mutationFn: async ({
    bucketId,
    path,
    file,
    upsert = false,
  }: {
    bucketId: string
    path: string
    file: File
    upsert?: boolean
  }) => {
    const { data, error } = await supabase.storage
      .from(bucketId)
      .upload(path, file, { upsert })
    if (error) throw error
    return data
  },
})

export const storageDeleteMutationOptions = mutationOptions({
  mutationFn: async ({
    bucketId,
    paths,
  }: {
    bucketId: string
    paths: string[]
  }) => {
    const { data, error } = await supabase.storage.from(bucketId).remove(paths)
    if (error) throw error
    return data
  },
})

export const storageMoveMutationOptions = mutationOptions({
  mutationFn: async ({
    bucketId,
    fromPath,
    toPath,
  }: {
    bucketId: string
    fromPath: string
    toPath: string
  }) => {
    const { data, error } = await supabase.storage
      .from(bucketId)
      .move(fromPath, toPath)
    if (error) throw error
    return data
  },
})

async function renameFolderRecursive(
  bucketId: string,
  fromFolder: string,
  toFolder: string
): Promise<void> {
  const { data, error } = await supabase.storage
    .from(bucketId)
    .list(fromFolder, { limit: 1000 })
  if (error) throw error

  await Promise.all(
    (data ?? []).map(async (item) => {
      const fromPath = `${fromFolder}/${item.name}`
      const toPath = `${toFolder}/${item.name}`
      if (!item.id) {
        await renameFolderRecursive(bucketId, fromPath, toPath)
      } else {
        const { error: moveError } = await supabase.storage
          .from(bucketId)
          .move(fromPath, toPath)
        if (moveError) throw moveError
      }
    })
  )
}

export const storageRenameFolderMutationOptions = mutationOptions({
  mutationFn: async ({
    bucketId,
    fromFolder,
    toFolder,
  }: {
    bucketId: string
    fromFolder: string
    toFolder: string
  }) => {
    await renameFolderRecursive(bucketId, fromFolder, toFolder)
  },
})

export const storageCopyMutationOptions = mutationOptions({
  mutationFn: async ({
    bucketId,
    fromPath,
    toPath,
  }: {
    bucketId: string
    fromPath: string
    toPath: string
  }) => {
    const { data, error } = await supabase.storage
      .from(bucketId)
      .copy(fromPath, toPath)
    if (error) throw error
    return data
  },
})

export const storageCreateFolderMutationOptions = mutationOptions({
  mutationFn: async ({
    bucketId,
    folderPath,
  }: {
    bucketId: string
    folderPath: string
  }) => {
    const keepPath = folderPath.endsWith("/")
      ? `${folderPath}.keep`
      : `${folderPath}/.keep`
    const { data, error } = await supabase.storage
      .from(bucketId)
      .upload(keepPath, new Blob([""]), { contentType: "text/plain" })
    if (error) throw error
    return data
  },
})

export function getPublicUrl(bucketId: string, path: string) {
  const { data } = supabase.storage.from(bucketId).getPublicUrl(path)
  return data.publicUrl
}

export async function createSignedUrl(
  bucketId: string,
  path: string,
  expiresIn = 3600
) {
  const { data, error } = await supabase.storage
    .from(bucketId)
    .createSignedUrl(path, expiresIn)
  if (error) throw error
  return data.signedUrl
}

export async function downloadFile(bucketId: string, path: string) {
  const { data, error } = await supabase.storage.from(bucketId).download(path)
  if (error) throw error
  return data
}
