import { useSuspenseQuery } from "@tanstack/react-query"

import type { OneToOneRelation } from "#/components/resource/detail/classify-relationships"
import { OneToOneUnlinked } from "#/components/resource/detail/one-to-one-unlinked"
import { ResourceFullDetail } from "#/components/resource/detail/resource-full-detail"
import { ResourceUpdateForm } from "#/components/resource/resource-update-form"
import { Card, CardContent } from "#/components/ui/card"
import { Skeleton } from "#/components/ui/skeleton"
import { singleForeignTableDataQueryOptions } from "#/lib/supabase/data/resource"

export function OneToOneDetail({
  schema,
  resource,
  resourceId,
  oneToOne,
  matchValue,
  canUpdateOneToOne,
  canUpdateParent,
}: {
  schema: string
  resource: string
  resourceId: string
  oneToOne: OneToOneRelation
  matchValue: unknown
  canUpdateOneToOne: boolean
  canUpdateParent: boolean
}) {
  const { data: embedded } = useSuspenseQuery(
    singleForeignTableDataQueryOptions(oneToOne.schema, oneToOne.name, {
      [oneToOne.__foreignMatchColumn]: matchValue,
    })
  )

  const primaryKeys = oneToOne.primary_keys ?? []
  const hasPkValues =
    primaryKeys.length > 0 &&
    primaryKeys.every((k) => embedded != null && embedded[k.name] != null)

  if (embedded == null || !hasPkValues) {
    return (
      <OneToOneUnlinked
        schema={schema}
        resource={resource}
        resourceId={resourceId}
        oneToOne={oneToOne}
        canUpdateParent={canUpdateParent}
      />
    )
  }

  if (canUpdateOneToOne) {
    return (
      <ResourceUpdateForm
        columnsSchema={oneToOne.columns ?? []}
        primaryKeys={primaryKeys}
        record={embedded}
        tableSchema={oneToOne}
        saveOnly
      />
    )
  }

  return (
    <ResourceFullDetail
      resourceSchema={{
        ...oneToOne,
        name: oneToOne.__embedKey as never,
      }}
      columnsSchema={oneToOne.columns ?? []}
      record={embedded}
    />
  )
}

export function OneToOneDetailSkeleton() {
  return (
    <div className="mx-auto w-full max-w-5xl space-y-4">
      <Card>
        <CardContent className="space-y-4 py-6">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="space-y-2">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-9 w-full" />
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}
