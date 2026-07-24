import { useQuery } from "@tanstack/react-query"

import { ShieldAlertIcon, ShieldIcon } from "lucide-react"

import { Badge } from "#/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import {
  userPermissionsQueryOptions,
  whoamiQueryOptions,
} from "#/lib/supabase/data/core"

export function RolesPermissionsCard() {
  const { data: whoami, isLoading: isWhoamiLoading } =
    useQuery(whoamiQueryOptions)
  const { data: grouped = {}, isLoading: isPermissionsLoading } = useQuery(
    userPermissionsQueryOptions()
  )
  const isLoading = isWhoamiLoading || isPermissionsLoading
  const role = whoami?.role

  return (
    <Card>
      <CardHeader className="border-b">
        <CardTitle>Roles & permissions</CardTitle>
        <CardDescription>
          Your assigned role and the permissions it grants.
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        {isLoading ? (
          <div className="px-6 py-4 text-sm text-muted-foreground">
            Loading…
          </div>
        ) : !role ? (
          <div className="flex items-center gap-3 px-6 py-4">
            <ShieldAlertIcon className="size-5 shrink-0 text-muted-foreground" />
            <p className="text-sm text-muted-foreground">
              No role assigned to your account.
            </p>
          </div>
        ) : (
          <div className="flex items-start gap-3 px-6 py-4">
            <div className="flex size-9 shrink-0 items-center justify-center rounded-md border">
              <ShieldIcon className="size-5" />
            </div>
            <div className="flex-1 space-y-3 pt-1">
              <p className="text-sm leading-none font-medium">{role}</p>
              {Object.keys(grouped).length > 0 ? (
                <div className="overflow-hidden rounded-md border divide-y">
                  {Object.entries(grouped).flatMap(([schema, tables]) => [
                    <div
                      key={`${schema}-header`}
                      className="bg-muted/50 px-3 py-1.5"
                    >
                      <span className="text-xs font-medium text-muted-foreground">
                        {schema}
                      </span>
                    </div>,
                    ...Object.entries(tables).map(([table, operations]) => (
                      <div
                        key={`${schema}.${table}`}
                        className="flex items-center gap-3 px-3 py-2"
                      >
                        <span className="w-36 shrink-0 text-xs font-medium">
                          {table}
                        </span>
                        <div className="flex flex-wrap gap-1">
                          {operations.map((op) => (
                            <Badge
                              key={op}
                              variant="secondary"
                              className="text-xs"
                            >
                              {op}
                            </Badge>
                          ))}
                        </div>
                      </div>
                    )),
                  ])}
                </div>
              ) : (
                <p className="text-xs text-muted-foreground">
                  No permissions assigned to this role.
                </p>
              )}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
