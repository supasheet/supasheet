import { useMemo } from "react"

import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext"
import { $getRoot, $getSelection } from "lexical"
import { Star } from "lucide-react"

import { INSERT_REVIEW_COMMAND } from "#/components/editor/extensions/review.ts"
import { useComponentPickerItems } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import type { ComponentPickerItem } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"

export function ReviewPickerPlugin() {
  const [editor] = useLexicalComposerContext()
  const { t } = useTranslation()

  const items = useMemo<ComponentPickerItem[]>(
    () => [
      {
        value: "review",
        label: t.insertReview,
        icon: <Star className="text-muted-foreground" />,
        keywords: ["review", "rating", "stars", "testimonial"],
        onSelect: () => {
          editor.update(() => {
            if (!$getSelection()) {
              $getRoot().selectEnd()
            }
          })
          editor.dispatchCommand(INSERT_REVIEW_COMMAND, undefined)
        },
      },
    ],
    [editor, t]
  )

  useComponentPickerItems(items)

  return null
}
