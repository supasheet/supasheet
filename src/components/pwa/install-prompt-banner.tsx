import { Download, X } from "lucide-react"
import { useState } from "react"

import { Button } from "#/components/ui/button"
import { Card, CardContent } from "#/components/ui/card"
import { useInstallPrompt } from "#/hooks/use-install-prompt"

const DISMISS_KEY = "supasheet-install-prompt-dismissed"

export function InstallPromptBanner() {
  const { canInstall, isIos, promptInstall } = useInstallPrompt()
  const [dismissed, setDismissed] = useState(
    () => localStorage.getItem(DISMISS_KEY) === "1"
  )

  if (dismissed || (!canInstall && !isIos)) {
    return null
  }

  function dismiss() {
    localStorage.setItem(DISMISS_KEY, "1")
    setDismissed(true)
  }

  return (
    <Card className="fixed right-4 bottom-4 z-50 w-[min(22rem,calc(100vw-2rem))] shadow-lg">
      <CardContent className="flex items-start gap-3">
        <Download className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
        <div className="flex-1 space-y-2">
          <p className="text-sm font-medium">Install Supasheet</p>
          <p className="text-sm text-muted-foreground">
            {canInstall
              ? "Install the app for quicker access and a full-screen experience."
              : 'Tap the Share icon, then "Add to Home Screen" to install this app.'}
          </p>
          {canInstall && (
            <Button
              size="sm"
              onClick={() => {
                void promptInstall().then(dismiss)
              }}
            >
              Install
            </Button>
          )}
        </div>
        <Button
          variant="ghost"
          size="icon-sm"
          className="shrink-0"
          onClick={dismiss}
        >
          <X />
        </Button>
      </CardContent>
    </Card>
  )
}
