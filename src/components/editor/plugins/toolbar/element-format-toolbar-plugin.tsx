import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext"
import { useLexicalEditable } from "@lexical/react/useLexicalEditable"
import { FORMAT_ELEMENT_COMMAND } from "lexical"
import type { ElementFormatType } from "lexical"
import {
  AlignCenter,
  AlignJustify,
  AlignLeft,
  AlignRight,
  PilcrowLeft,
  PilcrowRight,
} from "lucide-react"
import type { LucideIcon } from "lucide-react"

import { useFormatStateValue } from "#/components/editor/extensions/format-state.tsx"
import type { Locale } from "#/components/editor/locales.ts"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"
import { ToggleGroup, ToggleGroupItem } from "#/components/ui/toggle-group.tsx"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "#/components/ui/tooltip.tsx"

type AlignItem = {
  value: Exclude<ElementFormatType, "">
  labelKey: keyof Locale
  icon: LucideIcon
}

function AlignToggleGroup({ items }: { items: AlignItem[] }) {
  const [editor] = useLexicalComposerContext()
  const { t } = useTranslation()
  const elementFormat = useFormatStateValue("elementFormat")
  const isEditable = useLexicalEditable()
  return (
    <ToggleGroup
      variant="outline"
      size="sm"
      spacing={0}
      disabled={!isEditable}
      value={[elementFormat]}
      onValueChange={(value) => {
        const next = value[0] as Exclude<ElementFormatType, ""> | undefined
        if (next) {
          editor.dispatchCommand(FORMAT_ELEMENT_COMMAND, next)
        }
      }}
    >
      {items.map(({ value, labelKey, icon: Icon }) => (
        <Tooltip key={value}>
          <TooltipTrigger
            render={
              <ToggleGroupItem value={value} aria-label={t[labelKey]}>
                <Icon />
              </ToggleGroupItem>
            }
          />
          <TooltipContent>{t[labelKey]}</TooltipContent>
        </Tooltip>
      ))}
    </ToggleGroup>
  )
}

export function ElementFormatToolbarPlugin({
  formats = "all",
}: {
  formats?: "basic" | "all"
}) {
  const { dir } = useTranslation()
  const isRtl = dir === "rtl"

  const alignGroups: AlignItem[][] = [
    [
      { value: "left", icon: AlignLeft, labelKey: "alignLeft" },
      { value: "center", icon: AlignCenter, labelKey: "alignCenter" },
      { value: "right", icon: AlignRight, labelKey: "alignRight" },
      { value: "justify", icon: AlignJustify, labelKey: "alignJustify" },
    ],
    [
      {
        value: "start",
        icon: isRtl ? PilcrowRight : PilcrowLeft,
        labelKey: "alignStart",
      },
      {
        value: "end",
        icon: isRtl ? PilcrowLeft : PilcrowRight,
        labelKey: "alignEnd",
      },
    ],
  ]

  const groups = formats === "basic" ? alignGroups.slice(0, 1) : alignGroups

  return (
    <>
      {groups.map((items, groupIndex) => (
        <AlignToggleGroup key={groupIndex} items={items} />
      ))}
    </>
  )
}
