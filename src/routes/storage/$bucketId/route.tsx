import {
  Outlet,
  createFileRoute,
  notFound,
  useParams,
} from "@tanstack/react-router"

import { DefaultHeader } from "#/components/layouts/default-header"
import { StorageExplorer } from "#/components/storage/storage-explorer"
import { Skeleton } from "#/components/ui/skeleton"
import { pageTitle } from "#/lib/page-title"
import { storageBucketsQueryOptions } from "#/lib/supabase/data/storage"

export const Route = createFileRoute("/storage/$bucketId")({
  loader: async ({ context, params: { bucketId } }) => {
    const buckets = await context.queryClient.query({
      ...storageBucketsQueryOptions,
      staleTime: "static",
    })
    const bucket = buckets.find((b) => b.id === bucketId)
    if (!bucket) throw notFound()
    return { bucket }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`${params.bucketId} | Storage`) }],
  }),
  pendingComponent: PendingComponent,
  component: RouteComponent,
})

function PendingComponent() {
  const { bucketId } = Route.useParams()
  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Storage", url: "/storage" },
          { title: bucketId },
        ]}
      />
      <div className="flex flex-1 flex-col gap-3 p-2">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="h-8 w-full max-w-sm" />
        <div className="space-y-2">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton key={i} className="h-10 w-full" />
          ))}
        </div>
      </div>
    </>
  )
}

function RouteComponent() {
  const { bucketId } = Route.useParams()
  const { bucket } = Route.useLoaderData()
  const { _splat } = useParams({ strict: false })

  const segments = (_splat ?? "").split("/").filter(Boolean)
  const initialPath = _splat ? segments.slice(0, -1) : []

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Storage", url: "/storage" },
          { title: bucketId },
        ]}
      />
      <div className="flex flex-1 flex-col gap-3 p-2">
        <StorageExplorer
          bucketId={bucketId}
          isPublic={bucket.isPublic}
          initialPath={initialPath}
        />
      </div>
      <Outlet />
    </>
  )
}
