import {
  Link,
  createFileRoute,
  notFound,
  useRouter,
} from "@tanstack/react-router"
import type {
  ErrorComponentProps,
  SearchSchemaInput,
} from "@tanstack/react-router"

import type { ColumnFiltersState, SortingState } from "@tanstack/react-table"

import { AlertCircleIcon, FileXIcon, LayoutTemplateIcon } from "lucide-react"
import z from "zod"

import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import { DefaultHeader } from "#/components/layouts/default-header"
import { ReportTable } from "#/components/report/report-table"
import { ApplyTemplateDialog } from "#/components/template/apply-template-dialog"
import { Button } from "#/components/ui/button"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import type {
  DatabaseSchemas,
  DatabaseTables,
  DatabaseViews,
} from "#/lib/database-meta.types"
import { formatTitle } from "#/lib/format"
import { pageTitle } from "#/lib/page-title"
import { columnsSchemaQueryOptions } from "#/lib/supabase/data/resource"
import {
  templateDataQueryOptions,
  templatesQueryOptions,
} from "#/lib/supabase/data/template"

export const Route = createFileRoute("/$schema/template/$template/")({
  params: z.object({
    schema: z.string<DatabaseSchemas>(),
    template: z.string<
      DatabaseTables<DatabaseSchemas> | DatabaseViews<DatabaseSchemas>
    >(),
  }),
  validateSearch: (
    search: {
      sortId?: string
      sortDesc?: boolean
      page?: number
      pageSize?: number
      filters?: ColumnFiltersState
    } & SearchSchemaInput
  ) => ({
    sortId: search.sortId,
    sortDesc: search.sortDesc ?? false,
    page: search.page ?? 1,
    pageSize: search.pageSize ?? 20,
    filters: search.filters ?? [],
  }),
  loaderDeps: ({ search: { sortId, sortDesc, page, pageSize, filters } }) => ({
    sortId,
    sortDesc,
    page,
    pageSize,
    filters,
  }),
  loader: async ({
    context,
    params,
    deps: { sortId, sortDesc, page, pageSize, filters },
  }) => {
    const [templates, columnsSchema] = await Promise.all([
      context.queryClient.ensureQueryData(templatesQueryOptions(params.schema)),
      context.queryClient.ensureQueryData(
        columnsSchemaQueryOptions(params.schema, params.template)
      ),
    ])

    const template = templates.find((t) => t.view_name === params.template)
    if (!template || !columnsSchema?.length) throw notFound()

    const templateData = await context.queryClient.ensureQueryData(
      templateDataQueryOptions(
        params.schema,
        params.template,
        page,
        pageSize,
        sortId,
        sortDesc,
        filters
      )
    )
    return { templateData, columnsSchema, template }
  },
  head: ({ params }) => ({
    meta: [{ title: pageTitle(`${formatTitle(params.template)} | Templates`) }],
  }),
  pendingComponent: () => {
    const { schema, template } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            { title: "Template", url: `/${schema}/template` },
            { title: formatTitle(template) },
          ]}
        />
        <div className="flex flex-1 flex-col">
          <div className="flex flex-col gap-4 px-4 py-4">
            <DataTableSkeleton columnCount={5} />
          </div>
        </div>
      </>
    )
  },
  component: RouteComponent,
  errorComponent: ({ error }: ErrorComponentProps) => {
    const { schema, template } = Route.useParams()
    const router = useRouter()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            { title: "Template", url: `/${schema}/template` },
            { title: formatTitle(template) },
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
                onClick={() => router.navigate({ to: `/${schema}/template` })}
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
    const { schema, template } = Route.useParams()
    return (
      <>
        <DefaultHeader
          breadcrumbs={[
            { title: "Template", url: `/${schema}/template` },
            { title: formatTitle(template) },
          ]}
        />
        <div className="flex flex-1 items-center justify-center p-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <FileXIcon />
              </EmptyMedia>
              <EmptyTitle>Template not found</EmptyTitle>
              <EmptyDescription>
                <Link to="/$schema/template" params={{ schema }}>
                  Back to templates
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
  const params = Route.useParams()
  const { sortId, sortDesc, page, pageSize, filters } = Route.useSearch()

  const { templateData, columnsSchema, template } = Route.useLoaderData()

  const sorting = (
    sortId ? [{ id: sortId, desc: sortDesc }] : []
  ) as SortingState
  const pagination = { pageIndex: page - 1, pageSize }
  const pageCount = Math.ceil((templateData?.count ?? 0) / pageSize)

  return (
    <>
      <DefaultHeader
        breadcrumbs={[
          { title: "Template", url: `/${params.schema}/template` },
          { title: formatTitle(params.template) },
        ]}
      >
        <ApplyTemplateDialog
          schema={params.schema}
          templateName={params.template}
          defaultTargetTable={template.target_table}
          trigger={
            <Button size="sm">
              <LayoutTemplateIcon className="mr-1.5 size-3.5" />
              Apply to Table
            </Button>
          }
        />
      </DefaultHeader>
      <div className="flex flex-1 flex-col">
        <div className="flex flex-col gap-4 px-4 py-4">
          <ReportTable
            data={templateData?.result ?? []}
            columnsSchema={columnsSchema ?? []}
            sorting={sorting}
            pagination={pagination}
            columnFilters={filters}
            pageCount={pageCount}
            filename={params.template}
          />
        </div>
      </div>
    </>
  )
}
