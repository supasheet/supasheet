import { ChevronDownIcon } from "lucide-react"

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
  TableMetadata,
  TableSchema,
} from "#/lib/database-meta.types"

import { ResourceFormField } from "./fields/resource-form-field"
import type { ResourceFormApi } from "./form-hook"
import type { ResolvedFieldSection } from "./resource-form-utils"
import {
  evaluateConditionalField,
  getColumnFieldSpan,
} from "./resource-form-utils"

export function FieldWithBehavior({
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

export function SectionCard({
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
