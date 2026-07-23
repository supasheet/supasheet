import { Suspense } from "react"

import type { DatabaseSchemas } from "#/lib/database-meta.types"
import type { DashboardWidgetSchema } from "#/lib/supabase/data/dashboard"

import { Card1, Card1Skeleton } from "./card-1"
import { Card2, Card2Skeleton } from "./card-2"
import { Card3, Card3Skeleton } from "./card-3"
import { Card4, Card4Skeleton } from "./card-4"
import { Card5, Card5Skeleton } from "./card-5"
import { Card6, Card6Skeleton } from "./card-6"
import { List1Skeleton, List1Widget } from "./list-1"
import { List2Skeleton, List2Widget } from "./list-2"
import { List3Skeleton, List3Widget } from "./list-3"
import { List4Skeleton, List4Widget } from "./list-4"
import { Table1Skeleton, Table1Widget } from "./table-1"
import { Table2Skeleton, Table2Widget } from "./table-2"

export function DashboardWidget<S extends DatabaseSchemas>({
  widget,
}: {
  widget: DashboardWidgetSchema<S>
}) {
  switch (widget.widget_type) {
    case "card_1":
      return (
        <Suspense fallback={<Card1Skeleton />}>
          <Card1 widget={widget} />
        </Suspense>
      )
    case "card_2":
      return (
        <Suspense fallback={<Card2Skeleton />}>
          <Card2 widget={widget} />
        </Suspense>
      )
    case "card_3":
      return (
        <Suspense fallback={<Card3Skeleton />}>
          <Card3 widget={widget} />
        </Suspense>
      )
    case "card_4":
      return (
        <Suspense fallback={<Card4Skeleton />}>
          <Card4 widget={widget} />
        </Suspense>
      )
    case "card_5":
      return (
        <Suspense fallback={<Card5Skeleton />}>
          <Card5 widget={widget} />
        </Suspense>
      )
    case "card_6":
      return (
        <Suspense fallback={<Card6Skeleton />}>
          <Card6 widget={widget} />
        </Suspense>
      )
    case "table_1":
      return (
        <Suspense fallback={<Table1Skeleton />}>
          <Table1Widget widget={widget} />
        </Suspense>
      )
    case "table_2":
      return (
        <Suspense fallback={<Table2Skeleton />}>
          <Table2Widget widget={widget} />
        </Suspense>
      )
    case "list_1":
      return (
        <Suspense fallback={<List1Skeleton />}>
          <List1Widget widget={widget} />
        </Suspense>
      )
    case "list_2":
      return (
        <Suspense fallback={<List2Skeleton />}>
          <List2Widget widget={widget} />
        </Suspense>
      )
    case "list_3":
      return (
        <Suspense fallback={<List3Skeleton />}>
          <List3Widget widget={widget} />
        </Suspense>
      )
    case "list_4":
      return (
        <Suspense fallback={<List4Skeleton />}>
          <List4Widget widget={widget} />
        </Suspense>
      )
    default:
      return null
  }
}
