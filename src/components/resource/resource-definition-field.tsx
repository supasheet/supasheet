import { KeyIcon } from "lucide-react"

import { Badge } from "#/components/ui/badge"

import type { FieldRow } from "./resource-definition-utils"
import { DynamicIcon } from "./resource-definition-utils"

interface ResourceDefinitionFieldProps {
  field: FieldRow
}

export function ResourceDefinitionField({
  field,
}: ResourceDefinitionFieldProps) {
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3">
      <div className="flex min-w-0 items-center gap-2">
        {field.icon ? (
          <DynamicIcon
            iconName={field.icon}
            className="size-4 shrink-0 text-muted-foreground"
          />
        ) : field.isIdentifier ? (
          <KeyIcon className="size-4 shrink-0 text-muted-foreground" />
        ) : null}
        <span className="truncate text-sm font-medium">{field.label}</span>
        {field.description && (
          <span
            className="truncate text-sm text-muted-foreground"
            title={field.description}
          >
            — {field.description}
          </span>
        )}
      </div>
      <div className="flex shrink-0 items-center gap-1.5">
        <Badge variant="outline">{field.type}</Badge>
        {field.isIdentifier ? (
          <Badge variant="outline" className="border-blue-600 text-blue-600">
            Identifier
          </Badge>
        ) : field.required ? (
          <Badge
            variant="outline"
            className="border-orange-600 text-orange-600"
          >
            Required
          </Badge>
        ) : (
          <Badge variant="ghost">Optional</Badge>
        )}
        {field.unique && !field.isIdentifier && (
          <Badge variant="outline" className="border-green-600 text-green-600">
            Unique
          </Badge>
        )}
      </div>
    </div>
  )
}
