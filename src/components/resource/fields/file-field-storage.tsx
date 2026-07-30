import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "#/lib/database.types"

export const UPLOADS_BUCKET = "uploads"

export async function uploadFileToStorage(
  client: SupabaseClient<Database>,
  file: File,
  storagePath: string,
  onProgress?: (progress: number) => void
): Promise<string> {
  const bucket = client.storage.from(UPLOADS_BUCKET)
  const extension = file.name.split(".").pop()
  const { nanoid } = await import("nanoid")
  const uniqueId = nanoid(16)
  const fileName = `${storagePath}/${file.name.split(".")[0]}-${uniqueId}.${extension}`

  onProgress?.(50)
  const result = await bucket.upload(fileName, file, {
    contentType: file.type,
  })
  onProgress?.(100)

  if (result.error) throw result.error

  return bucket.getPublicUrl(fileName).data.publicUrl
}

export async function deleteFileFromStorage(
  client: SupabaseClient<Database>,
  url: string
): Promise<void> {
  const bucket = client.storage.from(UPLOADS_BUCKET)
  const urlParts = url.split(`${UPLOADS_BUCKET}/`)
  if (urlParts.length < 2) return

  const filePath = urlParts[1].split("?")[0]
  await bucket.remove([filePath])
}
