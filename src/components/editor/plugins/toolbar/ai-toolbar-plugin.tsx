import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext"
import { useLexicalEditable } from "@lexical/react/useLexicalEditable"
import { Sparkles } from "lucide-react"

import { OPEN_AI_EDITOR_COMMAND } from "#/components/editor/extensions/ai.ts"
import { useTranslation } from "#/components/editor/plugins/i18n-plugin.tsx"
import { ButtonGroup } from "#/components/ui/button-group.tsx"
import { Button } from "#/components/ui/button.tsx"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "#/components/ui/tooltip.tsx"

export function AiToolbarPlugin() {
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
              aria-label={t.askAi}
              disabled={!isEditable}
              onClick={() => {
                editor.dispatchCommand(OPEN_AI_EDITOR_COMMAND, undefined)
              }}
            >
              <Sparkles />
            </Button>
          }
        />
        <TooltipContent>{t.askAi}</TooltipContent>
      </Tooltip>
    </ButtonGroup>
  )
}
