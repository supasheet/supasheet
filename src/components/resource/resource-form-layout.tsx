import { useMemo } from "react"

import { useNavigate } from "@tanstack/react-router"

import { ChevronDownIcon } from "lucide-react"

import { Button } from "#/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "#/components/ui/collapsible"
import type {
  ColumnSchema,
  EnumColumnMetadata,
  FormMode,
  TableMetadata,
  TableSchema,
} from "#/lib/database-meta.types"

import { ResourceProgressField } from "./detail/resource-progress-field"
import { ResourceFormField } from "./fields/resource-form-field"
import type { ResourceFormApi } from "./form-hook"
import type { ResolvedFieldSection } from "./resource-form-utils"
import {
  buildLayoutPlan,
  evaluateConditionalField,
  getColumnFieldSpan,
  getProgressFields,
} from "./resource-form-utils"

type ResourceFormLayoutProps = {
  tableSchema: TableSchema
  writableCols: ColumnSchema[]
  form: ResourceFormApi
  mode: FormMode
  headerTitle: string
  saveOnly?: boolean
}

export function ResourceFormLayout({
  tableSchema,
  writableCols,
  form,
  mode,
  headerTitle,
  saveOnly,
}: ResourceFormLayoutProps) {
  const navigate = useNavigate()
  const schema = tableSchema?.schema
  const resource = tableSchema?.name
  const primaryKeys = tableSchema?.primary_keys ?? []
  const showSecondary = primaryKeys.length > 0

  const tableMeta = useMemo(
    () => JSON.parse(tableSchema?.comment ?? "{}") as TableMetadata,
    [tableSchema?.comment]
  )
  const { plan, colByName, progressFields } = useMemo(() => {
    const writableNames = new Set(writableCols.map((c) => c.name ?? c.id ?? ""))

    return {
      plan: buildLayoutPlan(tableMeta.fields?.sections, writableNames, mode),
      colByName: new Map(writableCols.map((c) => [c.name ?? c.id ?? "", c])),
      progressFields: getProgressFields(writableCols),
    }
  }, [tableMeta.fields?.sections, writableCols, mode])

  const handleCancel = () => {
    if (!schema || !resource) return
    navigate({
      to: "/$schema/resource/$resource",
      params: { schema, resource },
    })
  }

  const handlePrimary = () => {
    void form.handleSubmit({ target: "stay" } as never)
  }

  const handleSecondary = () => {
    void form.handleSubmit({ target: "close" } as never)
  }

  const submitButtons = (
    <form.Subscribe
      selector={(s) => ({
        isSubmitting: s.isSubmitting,
        canSubmit: s.canSubmit,
      })}
    >
      {({ isSubmitting, canSubmit }) => (
        <>
          <Button
            type="button"
            variant={!saveOnly && showSecondary ? "outline" : "default"}
            disabled={!canSubmit || isSubmitting}
            onClick={handlePrimary}
          >
            {isSubmitting ? "Saving…" : "Save"}
          </Button>
          {!saveOnly && showSecondary ? (
            <Button
              type="button"
              disabled={!canSubmit || isSubmitting}
              onClick={handleSecondary}
            >
              {isSubmitting ? "Saving…" : "Save & Close"}
            </Button>
          ) : null}
        </>
      )}
    </form.Subscribe>
  )

  const footer = (
    <div className="flex flex-wrap justify-end gap-2 pt-4">
      {!saveOnly ? (
        <Button type="button" variant="outline" onClick={handleCancel}>
          Cancel
        </Button>
      ) : null}
      {submitButtons}
    </div>
  )

  if (!plan) {
    return (
      <div className="mx-auto w-full max-w-5xl space-y-4">
        {progressFields.map(({ col, meta }) => (
          <ProgressFieldPreview
            key={col.id}
            column={col}
            enumMeta={meta}
            form={form}
          />
        ))}
        <Card>
          <CardHeader>
            <CardTitle>{headerTitle}</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
            {writableCols.map((col) => {
              const span = getColumnFieldSpan(col, tableSchema)
              const spanClass = span === 2 ? "md:col-span-2" : undefined
              return (
                <FieldWithBehavior
                  key={col.id}
                  col={col}
                  spanClass={spanClass}
                  tableSchema={tableSchema}
                  form={form}
                />
              )
            })}
          </CardContent>
        </Card>
        {footer}
      </div>
    )
  }

  return (
    <div className="mx-auto w-full max-w-5xl space-y-4">
      {progressFields.map(({ col, meta }) => (
        <ProgressFieldPreview
          key={col.id}
          column={col}
          enumMeta={meta}
          form={form}
        />
      ))}
      {plan.sections.map((s) => (
        <SectionCard
          key={s.id}
          section={s}
          colByName={colByName}
          tableSchema={tableSchema}
          form={form}
        />
      ))}
      {footer}
    </div>
  )
}

function ProgressFieldPreview({
  column,
  enumMeta,
  form,
}: {
  column: ColumnSchema
  enumMeta: EnumColumnMetadata
  form: ResourceFormApi
}) {
  return (
    <form.Subscribe selector={(s) => s.values[column.name] as string | null}>
      {(value) => (
        <ResourceProgressField
          column={column}
          value={value ?? null}
          enumMeta={enumMeta}
        />
      )}
    </form.Subscribe>
  )
}

function FieldWithBehavior({
  col,
  spanClass,
  tableSchema,
  form,
}: {
  col: ColumnSchema
  spanClass?: string
  tableSchema: TableSchema
  form: ResourceFormApi
}) {
  const behavior = (JSON.parse(tableSchema.comment ?? "{}") as TableMetadata)
    .fields?.behavior?.[col.name ?? col.id ?? ""]

  const allCondIds = new Set([
    ...(behavior?.visible?.map((c) => c.id) ?? []),
    ...(behavior?.required?.map((c) => c.id) ?? []),
    ...(behavior?.read_only?.map((c) => c.id) ?? []),
  ])

  if (!allCondIds.size) {
    return (
      <div className={spanClass}>
        <ResourceFormField
          columnSchema={col}
          tableSchema={tableSchema}
          form={form}
        />
      </div>
    )
  }

  const watchedIds = [...allCondIds]

  return (
    <form.Subscribe
      selector={(s) =>
        watchedIds.reduce<Record<string, unknown>>((acc, id) => {
          acc[id] = s.values[id]
          return acc
        }, {})
      }
    >
      {(watchedValues) => {
        if (
          behavior?.visible?.length &&
          !evaluateConditionalField(behavior.visible, watchedValues)
        )
          return null
        const isRequired = behavior?.required?.length
          ? evaluateConditionalField(behavior.required, watchedValues)
          : undefined
        const isReadOnly = behavior?.read_only?.length
          ? evaluateConditionalField(behavior.read_only, watchedValues)
          : undefined
        return (
          <div className={spanClass}>
            <ResourceFormField
              columnSchema={col}
              tableSchema={tableSchema}
              form={form}
              isRequired={isRequired}
              isReadOnly={isReadOnly}
            />
          </div>
        )
      }}
    </form.Subscribe>
  )
}

function SectionCard({
  section,
  colByName,
  tableSchema,
  form,
}: {
  section: ResolvedFieldSection
  colByName: Map<string, ColumnSchema>
  tableSchema: TableSchema
  form: ResourceFormApi
}) {
  const body = (
    <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
      {section.fields.map((name) => {
        const col = colByName.get(name)
        if (!col) return null
        const span = getColumnFieldSpan(col, tableSchema)
        const spanClass = span === 2 ? "md:col-span-2" : undefined
        return (
          <FieldWithBehavior
            key={col.id}
            col={col}
            spanClass={spanClass}
            tableSchema={tableSchema}
            form={form}
          />
        )
      })}
    </CardContent>
  )

  if (!section.collapsible) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{section.title}</CardTitle>
          {section.description ? (
            <CardDescription>{section.description}</CardDescription>
          ) : null}
        </CardHeader>
        {body}
      </Card>
    )
  }

  return (
    <Collapsible defaultOpen={false}>
      <Card>
        <CollapsibleTrigger
          render={
            <button
              type="button"
              className="group/section-trigger w-full cursor-pointer text-left"
            />
          }
        >
          <CardHeader className="flex flex-row items-start justify-between gap-2">
            <div className="flex flex-col gap-1">
              <CardTitle>{section.title}</CardTitle>
              {section.description ? (
                <CardDescription>{section.description}</CardDescription>
              ) : null}
            </div>
            <ChevronDownIcon className="mt-1 size-4 shrink-0 text-muted-foreground transition-transform group-data-[panel-open]/section-trigger:rotate-180" />
          </CardHeader>
        </CollapsibleTrigger>
        <CollapsibleContent>{body}</CollapsibleContent>
      </Card>
    </Collapsible>
  )
}
