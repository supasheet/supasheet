"use client"

import { useNavigate } from "@tanstack/react-router"

import { useQueryClient } from "@tanstack/react-query"

import {
  MoreHorizontalIcon,
  PlusIcon,
  RefreshCwIcon,
  TableIcon,
  UploadIcon,
  ZapIcon,
} from "lucide-react"
import { toast } from "sonner"

import { NewRecordTrigger } from "#/components/resource/sheet/new-record-trigger"
import { Button } from "#/components/ui/button"
import { ButtonGroup } from "#/components/ui/button-group"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "#/components/ui/dropdown-menu"
import { useSheetHref } from "#/hooks/use-sheet-href"
import type {
  ColumnSchema,
  ResourceSchema,
  TableMetadata,
} from "#/lib/database-meta.types"

interface RecordActionsProps {
  schema: string
  resource: string
  columnsSchema: ColumnSchema[]
  tableSchema?: ResourceSchema | null
}

function downloadTemplate(resource: string, columnsSchema: ColumnSchema[]) {
  const headers = columnsSchema
    .map((c) => c.name ?? "")
    .filter(Boolean)
    .join(",")
  const blob = new Blob([headers + "\n"], { type: "text/csv;charset=utf-8;" })
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = `${resource}_template.csv`
  link.style.visibility = "hidden"
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

export function ResourceActions({
  schema,
  resource,
  columnsSchema,
  tableSchema,
}: RecordActionsProps) {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const importLink = useSheetHref({ mode: "import" })
  const quickCreateLink = useSheetHref({ mode: "create", quick: true })

  const quickCreate = (
    JSON.parse(tableSchema?.comment ?? "{}") as TableMetadata
  ).fields?.quick_create

  function handleRefresh() {
    queryClient.invalidateQueries({
      queryKey: ["supasheet", "resource-data", schema, resource],
    })
    toast.success("Data refreshed")
  }

  function handleImport() {
    if (importLink)
      navigate({
        to: importLink.to as never,
        search: importLink.search as never,
      })
  }

  return (
    <ButtonGroup>
      <NewRecordTrigger size="sm">
        <PlusIcon className="mr-1.5 size-3.5" />
        New record
      </NewRecordTrigger>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button size="icon-sm" aria-label="More Options">
              <MoreHorizontalIcon />
            </Button>
          }
        />
        <DropdownMenuContent align="end" className="w-48">
          {quickCreate?.length && quickCreateLink ? (
            <DropdownMenuGroup>
              <DropdownMenuItem
                onClick={() =>
                  navigate({
                    to: quickCreateLink.to as never,
                    search: quickCreateLink.search as never,
                  })
                }
              >
                <ZapIcon />
                Quick create
              </DropdownMenuItem>
            </DropdownMenuGroup>
          ) : null}
          {quickCreate?.length ? <DropdownMenuSeparator /> : null}
          <DropdownMenuGroup>
            <DropdownMenuItem onClick={handleImport} disabled={!importLink}>
              <UploadIcon />
              Import data
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => downloadTemplate(resource, columnsSchema)}
            >
              <TableIcon />
              Download template
            </DropdownMenuItem>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <DropdownMenuItem onClick={handleRefresh}>
              <RefreshCwIcon />
              Refresh
            </DropdownMenuItem>
          </DropdownMenuGroup>
        </DropdownMenuContent>
      </DropdownMenu>
    </ButtonGroup>
  )
}
