import { Button } from "#/components/ui/button"
import { Spinner } from "#/components/ui/spinner"
import type { MutationKind } from "#/lib/ai/types"

export type PendingMutation = {
  question: string
  kind: MutationKind
  value: Record<string, unknown>[]
  mutationSql: string
  summary: string
}

const ACTION_LABEL: Record<MutationKind, string> = {
  insert: "Insert",
  update: "Update",
  delete: "Delete",
}

const TITLE: Record<MutationKind, string> = {
  insert: "Confirm insert",
  update: "Confirm update",
  delete: "Confirm delete",
}

export function MutationConfirmBar({
  pendingMutation,
  isConfirming,
  onConfirm,
  onCancel,
}: {
  pendingMutation: PendingMutation
  isConfirming: boolean
  onConfirm: () => void
  onCancel: () => void
}) {
  const rowCount = pendingMutation.value.length
  return (
    <div className="border-warning/40 bg-warning/10 flex flex-wrap items-center justify-between gap-3 rounded-md border px-4 py-3">
      <div className="min-w-0">
        <p className="font-medium">{TITLE[pendingMutation.kind]}</p>
        <p className="text-sm text-muted-foreground">
          {pendingMutation.summary}{" "}
          {rowCount > 0 && (
            <span>
              ({rowCount} row{rowCount === 1 ? "" : "s"})
            </span>
          )}
        </p>
      </div>
      <div className="flex items-center gap-2">
        <Button variant="outline" onClick={onCancel} disabled={isConfirming}>
          Cancel
        </Button>
        <Button onClick={onConfirm} disabled={isConfirming || rowCount === 0}>
          {isConfirming ? (
            <span className="inline-flex items-center gap-2">
              <Spinner /> Running…
            </span>
          ) : (
            `${ACTION_LABEL[pendingMutation.kind]} ${rowCount} row${rowCount === 1 ? "" : "s"}`
          )}
        </Button>
      </div>
    </div>
  )
}
