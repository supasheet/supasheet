import { Suspense } from "react"

import { Outlet } from "@tanstack/react-router"

import { DataTableSkeleton } from "#/components/data-table/data-table-skeleton"
import type {
  ManyRelation,
  OneToOneRelation,
} from "#/components/resource/detail/classify-relationships"
import {
  OneToOneDetail,
  OneToOneDetailSkeleton,
} from "#/components/resource/detail/one-to-one-detail"
import { OneToOneUnlinked } from "#/components/resource/detail/one-to-one-unlinked"
import { ResourceForeignTable } from "#/components/resource/detail/resource-foreign-table"

type Props = {
  schema: string
  resource: string
  resourceId: string
  parentRecord: Record<string, unknown> | null | undefined
  oneToOne: OneToOneRelation | undefined
  many: ManyRelation | undefined
  canUpdateOneToOne: boolean
  canUpdateParent: boolean
}

export function ResourceDetailTab({
  schema,
  resource,
  resourceId,
  parentRecord,
  oneToOne,
  many,
  canUpdateOneToOne,
  canUpdateParent,
}: Props) {
  if (oneToOne) {
    const matchValue = parentRecord?.[oneToOne.__parentMatchColumn]

    // No FK value on the parent record → nothing to fetch; it is unlinked.
    if (matchValue == null) {
      return (
        <>
          <OneToOneUnlinked
            schema={schema}
            resource={resource}
            resourceId={resourceId}
            oneToOne={oneToOne}
            canUpdateParent={canUpdateParent}
          />
          <Outlet />
        </>
      )
    }

    return (
      <>
        <Suspense fallback={<OneToOneDetailSkeleton />}>
          <OneToOneDetail
            schema={schema}
            resource={resource}
            resourceId={resourceId}
            oneToOne={oneToOne}
            matchValue={matchValue}
            canUpdateOneToOne={canUpdateOneToOne}
            canUpdateParent={canUpdateParent}
          />
        </Suspense>
        <Outlet />
      </>
    )
  }

  if (!many) return null

  const {
    columns,
    __parentColumn,
    __targetColumn,
    __selectClause,
    ...resourceSchema
  } = many

  const parentValue = parentRecord?.[__targetColumn]

  return (
    <>
      <Suspense fallback={<DataTableSkeleton columnCount={10} />}>
        <ResourceForeignTable
          parentResource={resource}
          parentColumn={__parentColumn}
          parentValue={parentValue}
          resourceSchema={resourceSchema}
          columnsSchema={columns ?? []}
          selectClause={__selectClause}
        />
      </Suspense>
      <Outlet />
    </>
  )
}
