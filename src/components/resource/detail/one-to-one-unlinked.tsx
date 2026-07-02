import { Link } from "@tanstack/react-router"

import { LinkIcon } from "lucide-react"

import type { OneToOneRelation } from "#/components/resource/detail/classify-relationships"
import { buttonVariants } from "#/components/ui/button"
import { Card, CardContent } from "#/components/ui/card"
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { formatTitle } from "#/lib/format"

export function OneToOneUnlinked({
  schema,
  resource,
  resourceId,
  oneToOne,
  canUpdateParent,
}: {
  schema: string
  resource: string
  resourceId: string
  oneToOne: OneToOneRelation
  canUpdateParent: boolean
}) {
  const relatedName = formatTitle(oneToOne.name)
  const parentName = formatTitle(resource)
  const parentDetailHref = `/${schema}/resource/${resource}/${resourceId}/detail`

  return (
    <div className="mx-auto w-full max-w-5xl space-y-4">
      <Card>
        <CardContent className="py-8">
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <LinkIcon />
              </EmptyMedia>
              <EmptyTitle>No linked {relatedName}</EmptyTitle>
              <EmptyDescription>
                This {parentName} record is not linked to a {relatedName}.
                {canUpdateParent
                  ? ` Edit this record and set "${oneToOne.__fkColumn}" to link one.`
                  : null}
              </EmptyDescription>
            </EmptyHeader>
            {canUpdateParent ? (
              <EmptyContent>
                <Link
                  to={parentDetailHref}
                  className={buttonVariants({
                    size: "sm",
                    variant: "outline",
                  })}
                >
                  Edit {parentName}
                </Link>
              </EmptyContent>
            ) : null}
          </Empty>
        </CardContent>
      </Card>
    </div>
  )
}
