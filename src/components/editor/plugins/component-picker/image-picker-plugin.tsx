import { useMemo } from "react"

import { Image } from "lucide-react"

import { useImageFilePicker } from "#/components/editor/plugins/block-insert/insert-image-plugin.tsx"
import { useComponentPickerItems } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import type { ComponentPickerItem } from "#/components/editor/plugins/component-picker/component-picker-plugin.tsx"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"

export function ImagePickerPlugin() {
  const { t } = useTranslation()
  const { pick, input } = useImageFilePicker()

  const items = useMemo<ComponentPickerItem[]>(
    () => [
      {
        value: "image",
        label: t.insertImage,
        icon: <Image className="text-muted-foreground" />,
        keywords: ["image", "photo", "picture", "file", "img"],
        onSelect: pick,
      },
    ],
    [t, pick]
  )

  useComponentPickerItems(items)

  return input
}
