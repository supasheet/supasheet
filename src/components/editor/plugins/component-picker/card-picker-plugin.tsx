import { useMemo } from "react"

import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext"
import { $getRoot, $getSelection } from "lexical"
import { LayoutPanelTop } from "lucide-react"

import { INSERT_CARD_COMMAND } from "#/components/editor/extensions/card.ts"
import { useComponentPickerItems } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import type { ComponentPickerItem } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"

export function CardPickerPlugin() {
  const [editor] = useLexicalComposerContext()
  const { t } = useTranslation()

  const items = useMemo<ComponentPickerItem[]>(
    () => [
      {
        value: "card",
        label: t.insertCard,
        icon: <LayoutPanelTop className="text-muted-foreground" />,
        keywords: ["card", "panel", "container", "box"],
        onSelect: () => {
          editor.update(() => {
            if (!$getSelection()) {
              $getRoot().selectEnd()
            }
          })
          editor.dispatchCommand(INSERT_CARD_COMMAND, undefined)
        },
      },
    ],
    [editor, t]
  )

  useComponentPickerItems(items)

  return null
}
