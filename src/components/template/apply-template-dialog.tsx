import { useState } from "react"

import { useMutation, useQueryClient } from "@tanstack/react-query"

import { TriangleAlertIcon } from "lucide-react"
import { toast } from "sonner"

import { Alert, AlertDescription, AlertTitle } from "#/components/ui/alert"
import { Button } from "#/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "#/components/ui/dialog"
import { Input } from "#/components/ui/input"
import { Label } from "#/components/ui/label"
import { applyTemplateMutationOptions } from "#/lib/supabase/data/template"

interface ApplyTemplateDialogProps {
  schema: string
  templateName: string
  defaultTargetTable?: string
  trigger: React.ReactNode
}

export function ApplyTemplateDialog({
  schema,
  templateName,
  defaultTargetTable,
  trigger,
}: ApplyTemplateDialogProps) {
  const [open, setOpen] = useState(false)
  const [targetTable, setTargetTable] = useState(defaultTargetTable ?? "")
  const queryClient = useQueryClient()

  const { mutateAsync: applyTemplate, isPending } = useMutation(
    applyTemplateMutationOptions
  )

  const handleApply = async () => {
    const table = targetTable.trim()
    if (!table) return
    try {
      const count = await applyTemplate({
        schema,
        templateName,
        targetTable: table,
      })
      await queryClient.invalidateQueries({
        queryKey: ["supasheet", "resource-data", schema, table],
      })
      toast.success(
        `Inserted ${count} row${count !== 1 ? "s" : ""} into "${table}"`
      )
      setOpen(false)
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to apply template"
      )
    }
  }

  return (
    <>
      <span onClick={() => setOpen(true)}>{trigger}</span>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Apply template</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <Alert variant="destructive">
              <TriangleAlertIcon />
              <AlertTitle>This will insert data</AlertTitle>
              <AlertDescription>
                Applying this template will INSERT rows into the target table.
                This action cannot be undone.
              </AlertDescription>
            </Alert>
            <div className="space-y-2">
              <Label htmlFor="target-table">Target table</Label>
              <Input
                id="target-table"
                value={targetTable}
                onChange={(e) => setTargetTable(e.target.value)}
                placeholder="table_name"
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleApply()
                }}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleApply}
              disabled={!targetTable.trim() || isPending}
            >
              {isPending ? "Applying…" : "Apply"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
