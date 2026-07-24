import {
  Link,
  Outlet,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { useSuspenseQuery } from "@tanstack/react-query"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { ResourceActions } from "#/components/resource/resource-actions"
import { ResourceGallery } from "#/components/resource/resource-gallery"
import type { GalleryViewData } from "#/components/resource/resource-gallery"
import { ResourceViewSwitcher } from "#/components/resource/resource-view-switcher"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import {
  hasResourcePermission,
  useHasPermission,
} from "#/hooks/use-permissions"
import type { GalleryLayout, TableMetadata } from "#/lib/database-meta.types"
import { isTableSchema } from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { resourceDataQueryOptions } from "#/lib/supabase/data/resource"

export const Route = createFileRoute(
  "/$schema/resource/$resource/gallery/$galleryId"
)({
  beforeLoad: ({ context, params: { schema, resource } }) => {
    const hasPermission = hasResourcePermission(context.permissions, {
      schema,
      resource,
      action: "select",
    })
    const hasPrivilege = context.privileges?.includes("select")
    const canSelect = context.authUser
      ? hasPermission && hasPrivilege
      : hasPrivilege
    if (!canSelect) throw notFound()
  },
  loader: async ({ context, params }) => {
    const { schema, resource, galleryId } = params

    const meta = JSON.parse(
      context.resourceSchema.comment ?? "{}"
    ) as TableMetadata
    const galleryView = meta.views?.find(
      (item): item is GalleryLayout =>
        item.id === galleryId && item.type === "gallery"
    )
    if (!galleryView) throw notFound()

    context.queryClient.ensureQueryData(
      resourceDataQueryOptions(schema, resource, meta.query)
    )

    return { galleryView }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Gallery | ${formatTitle(params.resource)}`) }],
  }),
  pendingComponent: () => {
    const { schema, resource } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            {
              title: formatTitle(resource),
              url: `/${schema}/resource/${resource}`,
            },
            { title: "Gallery" },
          ]}
        />
        <div className="flex flex-1 flex-col gap-4 px-4 py-4">
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <div
                key={i}
                className="rounded-lg bg-card shadow-xs ring-1 ring-foreground/10"
              >
                {/* Cover image area */}
                <div className="p-4 pb-0">
                  <Skeleton className="aspect-4/3 w-full rounded-md" />
                </div>
                {/* Card content */}
                <div className="flex flex-col gap-2 p-4">
                  <Skeleton className="h-4 w-3/4" />
                  <Skeleton className="h-3 w-full" />
                  <Skeleton className="h-3 w-2/3" />
                </div>
              </div>
            ))}
          </div>
        </div>
      </>
    )
  },
  component: RouteComponent,
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema, resource } = Route.useParams()
    const router = useRouter()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            {
              title: formatTitle(resource),
              url: `/${schema}/resource/${resource}`,
            },
            { title: "Gallery" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <AlertCircleIcon />
              </EmptyMedia>
              <EmptyTitle>Something went wrong</EmptyTitle>
              <EmptyDescription>
                {error?.message ?? "An unexpected error occurred."}
              </EmptyDescription>
            </EmptyHeader>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() =>
                  router.navigate({ to: `/${schema}/resource/${resource}` })
                }
              >
                Go Back
              </Button>
            </div>
          </Empty>
        </div>
      </>
    )
  },
  notFoundComponent: () => {
    const { schema, resource } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            {
              title: formatTitle(resource),
              url: `/${schema}/resource/${resource}`,
            },
            { title: "Gallery" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Gallery view not found</EmptyTitle>
              <EmptyDescription>
                <Link
                  to="/$schema/resource/$resource"
                  params={{ schema, resource }}
                >
                  Back to {formatTitle(resource)}
                </Link>
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        </div>
      </>
    )
  },
})

function RouteComponent() {
  const { schema, resource } = Route.useParams()
  const { galleryView } = Route.useLoaderData()
  const { resourceSchema, columnsSchema } = Route.useRouteContext()

  const meta = JSON.parse(resourceSchema.comment ?? "{}") as TableMetadata
  const { data: resourceData } = useSuspenseQuery(
    resourceDataQueryOptions(schema, resource, meta.query)
  )

  const titleField = galleryView.title
  const coverField = galleryView.cover
  const descriptionField = galleryView.description
  const badgeField = galleryView.badge

  const data: GalleryViewData[] = (resourceData?.result ?? []).map((row) => ({
    cover:
      coverField && row[coverField] != null ? String(row[coverField]) : null,
    title:
      titleField && row[titleField] != null ? String(row[titleField]) : null,
    description:
      descriptionField && row[descriptionField] != null
        ? String(row[descriptionField])
        : null,
    badge:
      badgeField && row[badgeField] != null ? String(row[badgeField]) : null,
    data: row,
  }))

  const metaItems = meta.views ?? []
  const isTable = isTableSchema(resourceSchema)
  const canInsert = useHasPermission({ schema, resource, action: "insert" })

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: meta.name ?? formatTitle(resource),
            url: `/${schema}/resource/${resource}`,
          },
          { title: formatTitle(galleryView.id) },
        ]}
      >
        <ResourceViewSwitcher
          schema={schema}
          resource={resource}
          metaItems={metaItems}
          currentViewId={galleryView.id}
        />
        {isTable && canInsert && (
          <ResourceActions
            schema={schema}
            resource={resource}
            columnsSchema={columnsSchema ?? []}
          />
        )}
      </DefaultHeader>
      <div className="flex flex-1 flex-col px-4 py-4">
        <ResourceGallery data={data} resourceSchema={resourceSchema} />
      </div>
      <Outlet />
    </>
  )
}
