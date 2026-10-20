import { format, formatDistanceToNow } from "date-fns"
import {
  AlertCircle,
  CheckCircle,
  Database,
  FileJson,
  Mail,
  Shield,
  Table,
  User,
  XCircle,
} from "lucide-react"

import { Avatar, AvatarFallback, AvatarImage } from "#/components/ui/avatar"
import { Badge } from "#/components/ui/badge"
import { ScrollArea } from "#/components/ui/scroll-area"
import { Separator } from "#/components/ui/separator"
import type { ResourceAuditLog } from "#/lib/supabase/data/resource"

export const opVariant = (op: string) => {
  if (op === "INSERT") return "default" as const
  if (op === "UPDATE") return "secondary" as const
  if (op === "DELETE") return "destructive" as const
  return "outline" as const
}

function Field({
  label,
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <div className="space-y-1">
      <p className="text-xs font-medium tracking-wide text-muted-foreground uppercase">
        {label}
      </p>
      {children}
    </div>
  )
}

export function ResourceAuditLogDetail({ data }: { data: ResourceAuditLog }) {
  const initials = data.created_by_name
    ? data.created_by_name
        .split(" ")
        .map((n) => n[0])
        .join("")
        .toUpperCase()
        .slice(0, 2)
    : "?"

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-4">
        <div>
          <div className="flex items-center justify-between">
            <p className="text-sm font-semibold">Audit Log Details</p>
            {data.is_error ? (
              <Badge variant="destructive" className="gap-1">
                <XCircle className="h-3 w-3" />
                Error
              </Badge>
            ) : (
              <Badge
                variant="outline"
                className="gap-1 border-green-600 text-green-600"
              >
                <CheckCircle className="h-3 w-3" />
                Success
              </Badge>
            )}
          </div>
          <p className="text-xs text-muted-foreground">
            {formatDistanceToNow(new Date(data.created_at), {
              addSuffix: true,
            })}
          </p>
        </div>
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <Field label="ID">
              <p className="font-mono text-sm break-all">{data.id}</p>
            </Field>
            <Field label="Operation">
              <Badge variant={opVariant(data.operation)} className="w-fit">
                {data.operation}
              </Badge>
            </Field>
            <Field label="Schema">
              <p className="flex items-center gap-1 font-mono text-sm">
                <Database className="h-3 w-3 shrink-0 text-muted-foreground" />
                {data.schema_name}
              </p>
            </Field>
            <Field label="Table">
              <p className="flex items-center gap-1 font-mono text-sm">
                <Table className="h-3 w-3 shrink-0 text-muted-foreground" />
                {data.table_name}
              </p>
            </Field>
            <Field label="Record ID">
              <p className="font-mono text-sm">{data.record_id ?? "—"}</p>
            </Field>
            <Field label="Created At">
              <p className="text-sm text-muted-foreground">
                {format(new Date(data.created_at), "PPpp")}
              </p>
            </Field>
            <Field label="Role">
              <p className="flex items-center gap-1 text-sm">
                <Shield className="h-3 w-3 shrink-0 text-muted-foreground" />
                {data.role ? (
                  <Badge variant="outline" className="w-fit">
                    {data.role}
                  </Badge>
                ) : (
                  "—"
                )}
              </p>
            </Field>
            <Field label="User Type">
              <Badge
                variant={data.user_type === "system" ? "secondary" : "outline"}
                className="w-fit capitalize"
              >
                {data.user_type.replace("_", " ")}
              </Badge>
            </Field>
          </div>

          <Separator />

          <Field label="Created By">
            {data.created_by ? (
              <div className="flex items-center gap-2 pt-0.5">
                <Avatar className="h-7 w-7">
                  <AvatarImage src={data.created_by_picture_url ?? undefined} />
                  <AvatarFallback className="text-xs">
                    {initials}
                  </AvatarFallback>
                </Avatar>
                <div className="flex flex-col">
                  <span className="text-sm leading-none font-medium">
                    {data.created_by_name ?? (
                      <span className="font-mono text-xs text-muted-foreground">
                        {data.created_by}
                      </span>
                    )}
                  </span>
                  {data.created_by_email && (
                    <span className="flex items-center gap-1 text-xs text-muted-foreground">
                      <Mail className="h-3 w-3" />
                      {data.created_by_email}
                    </span>
                  )}
                </div>
              </div>
            ) : (
              <p className="flex items-center gap-1 text-sm text-muted-foreground">
                <User className="h-3 w-3" />
                System
              </p>
            )}
          </Field>

          {data.is_error && (data.error_code || data.error_message) && (
            <>
              <Separator />
              <div className="flex flex-col gap-2">
                <p className="flex items-center gap-2 text-sm font-semibold text-destructive">
                  <AlertCircle className="h-4 w-4" />
                  Error Details
                </p>
                <div className="rounded-lg bg-destructive/10 p-3">
                  {data.error_code && (
                    <p className="text-sm font-medium text-destructive">
                      {data.error_code}
                    </p>
                  )}
                  {data.error_message && (
                    <p className="mt-1 text-sm text-muted-foreground">
                      {data.error_message}
                    </p>
                  )}
                </div>
              </div>
            </>
          )}

          {data.changed_fields && data.changed_fields.length > 0 && (
            <>
              <Separator />
              <div className="flex flex-col gap-2">
                <p className="text-sm font-semibold">Changed Fields</p>
                <div className="flex flex-wrap gap-1">
                  {data.changed_fields.map((f) => (
                    <Badge
                      key={f}
                      variant="outline"
                      className="font-mono text-xs"
                    >
                      {f}
                    </Badge>
                  ))}
                </div>
              </div>
            </>
          )}

          {data.metadata &&
            typeof data.metadata === "object" &&
            Object.keys(data.metadata).length > 0 && (
              <>
                <Separator />
                <div className="flex flex-col gap-2">
                  <p className="flex items-center gap-2 text-sm font-semibold">
                    <FileJson className="h-4 w-4" />
                    Metadata
                  </p>
                  <ScrollArea className="max-h-32 w-full rounded-md border p-2">
                    <pre className="text-xs">
                      {JSON.stringify(data.metadata, null, 2)}
                    </pre>
                  </ScrollArea>
                </div>
              </>
            )}
        </div>
      </div>

      {(data.old_data || data.new_data) && (
        <div className="flex flex-col gap-4">
          <div>
            <p className="text-sm font-semibold">Data Changes</p>
            <p className="text-xs text-muted-foreground">
              {data.operation === "INSERT" && "New data created"}
              {data.operation === "UPDATE" && "Data modifications"}
              {data.operation === "DELETE" && "Data removed"}
            </p>
          </div>
          <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-2">
              <p className="text-sm font-semibold">Old Data</p>
              {data.old_data ? (
                <ScrollArea className="max-h-64 w-full overflow-auto rounded-md border">
                  <pre className="p-3 text-xs">
                    {JSON.stringify(data.old_data, null, 2)}
                  </pre>
                </ScrollArea>
              ) : (
                <div className="flex h-20 items-center justify-center rounded-md border border-dashed">
                  <p className="text-xs text-muted-foreground">No data</p>
                </div>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <p className="text-sm font-semibold">New Data</p>
              {data.new_data ? (
                <ScrollArea className="max-h-64 w-full overflow-auto rounded-md border">
                  <pre className="p-3 text-xs">
                    {JSON.stringify(data.new_data, null, 2)}
                  </pre>
                </ScrollArea>
              ) : (
                <div className="flex h-20 items-center justify-center rounded-md border border-dashed">
                  <p className="text-xs text-muted-foreground">No data</p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
