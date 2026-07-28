import { useMutation, useQueryClient } from "@tanstack/react-query"

import Handlebars from "handlebars"
import { PrinterIcon } from "lucide-react"
import { toast } from "sonner"

import { Button } from "#/components/ui/button"
import type { DatabaseSchemas, DatabaseViews } from "#/lib/database-meta.types"
import { reportTemplateQueryOptions } from "#/lib/supabase/data/report"

interface ReportPrintButtonProps<S extends DatabaseSchemas> {
  schema: S
  viewName: DatabaseViews<S>
  name: string
  rows: Record<string, unknown>[]
}

export function ReportPrintButton<S extends DatabaseSchemas>({
  schema,
  viewName,
  name,
  rows,
}: ReportPrintButtonProps<S>) {
  const queryClient = useQueryClient()

  const { mutate: print, isPending } = useMutation({
    mutationFn: async () => {
      const source = await queryClient.fetchQuery(
        reportTemplateQueryOptions(schema, viewName)
      )

      const html = Handlebars.compile(source)({ name, rows })

      const win = window.open("", "_blank")
      if (!win) throw new Error("Pop-up blocked. Allow pop-ups to print.")

      win.document.write(html)
      win.document.close()
      win.focus()
      win.print()
    },
    onError: (error) => {
      toast.error(error.message)
    },
  })

  return (
    <Button
      variant="outline"
      size="sm"
      disabled={isPending}
      onClick={() => print()}
    >
      <PrinterIcon />
      {isPending ? "Preparing…" : "Print Report"}
    </Button>
  )
}
