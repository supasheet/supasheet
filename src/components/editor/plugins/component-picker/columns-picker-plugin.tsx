import { useMemo } from "react"

import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext"
import { $getRoot, $getSelection } from "lexical"
import { Columns2, Columns3, RectangleVertical } from "lucide-react"
import type { LucideIcon } from "lucide-react"

import { INSERT_LAYOUT_COMMAND } from "#/components/editor/extensions/layout.ts"
import type { Locale } from "#/components/editor/locales.ts"
import { useComponentPickerItems } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import type { ComponentPickerItem } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"

const COLUMN_ITEMS: {
  value: string
  labelKey: keyof Locale
  icon: LucideIcon
  templateColumns: string
}[] = [
  {
    value: "columns-one",
    labelKey: "columnsOne",
    icon: RectangleVertical,
    templateColumns: "1fr",
  },
  {
    value: "columns-two",
    labelKey: "columnsTwo",
    icon: Columns2,
    templateColumns: "1fr 1fr",
  },
  {
    value: "columns-three",
    labelKey: "columnsThree",
    icon: Columns3,
    templateColumns: "1fr 1fr 1fr",
  },
]

export function ColumnsPickerPlugin() {
  const [editor] = useLexicalComposerContext()
  const { t } = useTranslation()

  const items = useMemo<ComponentPickerItem[]>(
    () =>
      COLUMN_ITEMS.map(({ value, labelKey, icon: Icon, templateColumns }) => ({
        value,
        label: t[labelKey],
        icon: <Icon className="text-muted-foreground" />,
        keywords: ["columns", "layout", "grid"],
        onSelect: () => {
          editor.update(() => {
            if (!$getSelection()) {
              $getRoot().selectEnd()
            }
          })
          editor.dispatchCommand(INSERT_LAYOUT_COMMAND, templateColumns)
        },
      })),
    [editor, t]
  )

  useComponentPickerItems(items)

  return null
}
