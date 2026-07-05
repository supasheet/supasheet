import { FileXIcon } from "lucide-react"

import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import type { ColumnSchema, ResourceSchema } from "#/lib/database-meta.types"

import { ResourceFullDetail } from "./detail/resource-full-detail"

interface ResourceSingleProps {
  resourceSchema: ResourceSchema
  columnsSchema: ColumnSchema[]
  record?: Record<string, unknown>
}

export function ResourceSingle({
  resourceSchema,
  columnsSchema,
  record,
}: ResourceSingleProps) {
  if (!record) {
    return (
      <div className="flex flex-1 items-center justify-center p-8">
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <FileXIcon />
            </EmptyMedia>
            <EmptyTitle>No record found</EmptyTitle>
            <EmptyDescription>
              This resource has no data to display.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      </div>
    )
  }

  return (
    <div className="mx-auto w-full max-w-5xl">
      <ResourceFullDetail
        resourceSchema={resourceSchema}
        columnsSchema={columnsSchema}
        record={record}
      />
    </div>
  )
}
