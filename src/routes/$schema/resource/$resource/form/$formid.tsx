import {
  Link,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type { ErrorComponentProps } from "@tanstack/react-router"

import { AlertCircleIcon, FileXIcon } from "lucide-react"

import { DefaultHeader } from "#/components/layouts/default-header"
import { CustomForm } from "#/components/resource/custom-form"
import { Button } from "#/components/ui/button"
import { Card, CardContent, CardHeader } from "#/components/ui/card"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Skeleton } from "#/components/ui/skeleton"
import { getFormMeta } from "#/hooks/use-custom-form"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import {
  resourceFormFieldsQueryOptions,
  resourceFormsQueryOptions,
} from "#/lib/supabase/data/form"

export const Route = createFileRoute(
  "/$schema/resource/$resource/form/$formid"
)({
  loader: async ({ context, params: { schema, resource, formid } }) => {
    const forms = await context.queryClient.ensureQueryData(
      resourceFormsQueryOptions(schema, resource)
    )
    const formRow = forms.find((form) => form.name === formid)
    if (!formRow) throw notFound()

    const fieldsSchema = await context.queryClient.ensureQueryData(
      resourceFormFieldsQueryOptions(schema, formid)
    )

    return { formRow, fieldsSchema }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`Form | ${formatTitle(params.resource)}`) }],
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
            { title: "Form" },
          ]}
        />
        <div className="flex flex-1 flex-col">
          <div className="mx-auto w-full max-w-5xl px-4 py-4">
            <Card>
              <CardHeader>
                <Skeleton className="h-5 w-40" />
              </CardHeader>
              <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
                {Array.from({ length: 4 }).map((_, i) => (
                  <div key={i} className="space-y-1.5">
                    <Skeleton className="h-4 w-28" />
                    <Skeleton className="h-9 w-full" />
                  </div>
                ))}
              </CardContent>
            </Card>
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
            { title: "Form" },
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
            { title: "Form" },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Form not found</EmptyTitle>
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
  const { formRow, fieldsSchema } = Route.useLoaderData()
  const meta = getFormMeta(formRow)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          {
            title: formatTitle(resource),
            url: `/${schema}/resource/${resource}`,
          },
          { title: meta.name },
        ]}
      />
      <div className="flex flex-1 flex-col">
        <div className="mx-auto w-full max-w-5xl px-4 py-4">
          <CustomForm
            schema={schema}
            resource={resource}
            form={formRow}
            fieldsSchema={fieldsSchema}
          />
        </div>
      </div>
    </>
  )
}
