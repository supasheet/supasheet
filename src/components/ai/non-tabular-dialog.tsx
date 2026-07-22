import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "#/components/ui/alert-dialog"
import { Button } from "#/components/ui/button"
import type { AIResponse } from "#/lib/ai/types"

export function NonTabularDialog({
  response,
  onShowAnyway,
  onRefine,
}: {
  response: AIResponse | null
  onShowAnyway: () => void
  onRefine: () => void
}) {
  const open = response !== null
  const isScalar = response?.type === "scalar"
  const preview =
    response?.type === "scalar"
      ? response.value
      : response?.type === "text"
        ? response.summary
        : ""

  return (
    <AlertDialog open={open} onOpenChange={(o) => !o && onRefine()}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>This answer isn't a table</AlertDialogTitle>
          <AlertDialogDescription>
            The AI returned a {isScalar ? "single value" : "text response"}{" "}
            rather than rows. What would you like to do?
          </AlertDialogDescription>
        </AlertDialogHeader>
        {preview && (
          <div className="max-h-48 overflow-y-auto rounded-md border bg-muted/40 p-3 text-sm whitespace-pre-wrap">
            {preview}
          </div>
        )}
        <AlertDialogFooter>
          <Button variant="outline" onClick={onRefine}>
            Refine query
          </Button>
          <AlertDialogAction onClick={onShowAnyway}>
            Show anyway
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
