import type { LucideIcon } from "lucide-react"
import * as LucideIcons from "lucide-react"

import { Badge } from "#/components/ui/badge"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "#/components/ui/tooltip"
import type { EnumColumnMetadata } from "#/lib/database-meta.types"
import type { ColumnFieldMetadata } from "#/types/fields"

function LucideIconComponent({
  iconName,
}: {
  iconName: keyof typeof LucideIcons
}) {
  const Icon = LucideIcons[iconName] as LucideIcon

  return <Icon className="me-1 size-4 shrink-0" />
}

export function SelectCell({
  value,
  columnMetadata,
}: {
  value: string | null
  columnMetadata: ColumnFieldMetadata
}) {
  if (!value) {
    return null
  }

  const enumMeta = JSON.parse(
    columnMetadata.comment ?? "{}"
  ) as EnumColumnMetadata

  if (enumMeta?.enums && enumMeta.enums[value]) {
    const { icon, variant } = enumMeta.enums[value]

    if (enumMeta.iconOnly && icon) {
      return (
        <Tooltip>
          <TooltipTrigger>
            <Badge variant={variant ?? "secondary"} className="[&>svg]:me-0">
              <LucideIconComponent iconName={icon} />
            </Badge>
          </TooltipTrigger>
          <TooltipContent>{value}</TooltipContent>
        </Tooltip>
      )
    }

    return (
      <Badge variant={variant ?? "secondary"}>
        {icon && <LucideIconComponent iconName={icon} />}
        {value}
      </Badge>
    )
  }

  return <Badge variant={"secondary"}>{value}</Badge>
}
