import { useMemo } from "react"

import { useNavigate } from "@tanstack/react-router"

import { Button } from "#/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "#/components/ui/card"
import type {
  ColumnSchema,
  FormMode,
  TableMetadata,
  TableSchema,
} from "#/lib/database-meta.types"

import type { ResourceFormApi } from "./form-hook"
import { ProgressFieldPreview } from "./resource-form-progress-preview"
import { FieldWithBehavior, SectionCard } from "./resource-form-section"
import {
  buildLayoutPlan,
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
