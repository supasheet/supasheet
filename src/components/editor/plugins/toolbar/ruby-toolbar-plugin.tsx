import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext"
import { useLexicalEditable } from "@lexical/react/useLexicalEditable"
import { Languages } from "lucide-react"

import { toggleRubyEditor } from "#/components/editor/extensions/ruby.ts"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"
import { ButtonGroup } from "#/components/ui/button-group.tsx"
import { Button } from "#/components/ui/button.tsx"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "#/components/ui/tooltip.tsx"

export function RubyToolbarPlugin() {
  const [editor] = useLexicalComposerContext()
  const isEditable = useLexicalEditable()
  const { t } = useTranslation()

  return (
    <ButtonGroup>
      <Tooltip>
        <TooltipTrigger
          render={
            <Button
              variant="outline"
              size="icon-sm"
              aria-label={t.insertRuby}
              disabled={!isEditable}
              onClick={() => {
                toggleRubyEditor(editor)
              }}
            >
              <Languages />
            </Button>
          }
        />
        <TooltipContent>{t.insertRuby}</TooltipContent>
      </Tooltip>
    </ButtonGroup>
  )
}
