import { useState } from "react"

import { useMutation } from "@tanstack/react-query"
import { createFileRoute } from "@tanstack/react-router"

import { SparklesIcon, TableIcon } from "lucide-react"
import { toast } from "sonner"

import { MutationConfirmBar } from "#/components/ai/mutation-confirm-bar"
import type { PendingMutation } from "#/components/ai/mutation-confirm-bar"
import { NonTabularDialog } from "#/components/ai/non-tabular-dialog"
import { QueryBar } from "#/components/ai/query-bar"
import { ResultBar } from "#/components/ai/result-bar"
import { ResultDataTable } from "#/components/ai/result-data-table"
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "#/components/ui/empty"
import { Spinner } from "#/components/ui/spinner"
import { askAI, confirmMutation } from "#/lib/ai/retrieval"
import type { AIResponse, ChatMessage } from "#/lib/ai/types"

export const Route = createFileRoute("/ai/")({
  component: AIPage,
})

type DisplayResult =
  | { kind: "table"; rows: Record<string, unknown>[]; summary: string }
  | { kind: "note"; summary: string; value?: string }

function toDisplay(response: AIResponse): DisplayResult | null {
  if (response.type === "json") {
    return { kind: "table", rows: response.value, summary: response.summary }
  }
  if (response.type === "scalar") {
    return {
      kind: "note",
      summary: response.summary,
      value: response.value,
    }
  }
  if (response.type === "mutation_result") {
    return {
      kind: "table",
      rows: response.value,
      summary: response.summary,
    }
  }
  if (response.type === "text") {
    return { kind: "note", summary: response.summary }
  }
  return null
}

function AIPage() {
  const [history, setHistory] = useState<ChatMessage[]>([])
  const [result, setResult] = useState<DisplayResult | null>(null)
  const [resetSignal, setResetSignal] = useState(0)
  const [pendingNonTabular, setPendingNonTabular] = useState<{
    question: string
    response: AIResponse
  } | null>(null)
  const [pendingMutation, setPendingMutation] =
    useState<PendingMutation | null>(null)

  function commitToHistory(
    question: string,
    response: AIResponse,
    display: DisplayResult | null
  ) {
    setHistory((prev) => [
      ...prev,
      { role: "user", content: question },
      { role: "assistant", content: response.summary, result: response },
    ])
    if (display) setResult(display)
    setResetSignal((s) => s + 1)
  }

  const { mutate: ask, isPending: isAsking } = useMutation({
    mutationFn: (question: string) => askAI(question, history),
    onSuccess: (response, question) => {
      if (response.type === "json") {
        commitToHistory(question, response, toDisplay(response))
        return
      }
      if (response.type === "mutation_preview") {
        setPendingMutation({
          question,
          kind: response.kind,
          value: response.value,
          mutationSql: response.mutationSql,
          summary: response.summary,
        })
        setResult({
          kind: "table",
          rows: response.value,
          summary: response.summary,
        })
        setResetSignal((s) => s + 1)
        return
      }
      setPendingNonTabular({ question, response })
    },
    onError: (err: unknown) => {
      const message = err instanceof Error ? err.message : "Request failed"
      toast.error(message)
    },
  })

  const { mutate: confirmRun, isPending: isConfirming } = useMutation({
    mutationFn: (m: PendingMutation) =>
      confirmMutation({
        mutationSql: m.mutationSql,
        kind: m.kind,
        summary: m.summary,
      }),
    onSuccess: (response) => {
      if (!pendingMutation) return
      commitToHistory(pendingMutation.question, response, toDisplay(response))
      toast.success(
        response.type === "mutation_result"
          ? `${pendingMutation.kind} affected ${response.value.length} row${response.value.length === 1 ? "" : "s"}`
          : "Done"
      )
      setPendingMutation(null)
    },
    onError: (err: unknown) => {
      const message = err instanceof Error ? err.message : "Mutation failed"
      toast.error(message)
    },
  })

  function acceptNonTabular() {
    if (!pendingNonTabular) return
    const { question, response } = pendingNonTabular
    commitToHistory(question, response, toDisplay(response))
    setPendingNonTabular(null)
  }

  function dismissNonTabular() {
    setPendingNonTabular(null)
  }

  function cancelMutation() {
    if (isConfirming) return
    setPendingMutation(null)
    setResult(null)
  }

  function handleNewQuery() {
    setResult(null)
  }

  const showPendingState = isAsking && result === null

  return (
    <div className="flex flex-1 flex-col pb-32">
      <div className="flex flex-1 flex-col">
        {showPendingState ? (
          <PendingState />
        ) : result === null ? (
          <Empty className="flex-1">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <SparklesIcon />
              </EmptyMedia>
              <EmptyTitle>Ask your data anything</EmptyTitle>
              <EmptyDescription>
                Read or change your data — INSERT, UPDATE, and DELETE require
                confirmation before they run.
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : result.kind === "table" ? (
          <ResultDataTable rows={result.rows} />
        ) : (
          <NoteResult summary={result.summary} value={result.value} />
        )}
      </div>
      <div className="pointer-events-none fixed inset-x-0 bottom-0 z-20 flex justify-center bg-gradient-to-t from-background via-background/95 to-transparent px-4 pt-8 pb-6">
        <div className="pointer-events-auto w-full max-w-3xl">
          {pendingMutation ? (
            <MutationConfirmBar
              pendingMutation={pendingMutation}
              isConfirming={isConfirming}
              onConfirm={() => confirmRun(pendingMutation)}
              onCancel={cancelMutation}
            />
          ) : result?.kind === "table" ? (
            <ResultBar summary={result.summary} onNewQuery={handleNewQuery} />
          ) : (
            <QueryBar
              onSubmit={ask}
              disabled={isAsking || isConfirming}
              pending={isAsking}
              resetSignal={resetSignal}
            />
          )}
        </div>
      </div>
      <NonTabularDialog
        response={pendingNonTabular?.response ?? null}
        onShowAnyway={acceptNonTabular}
        onRefine={dismissNonTabular}
      />
    </div>
  )
}

function PendingState() {
  return (
    <Empty className="flex-1">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <Spinner />
        </EmptyMedia>
        <EmptyTitle>Thinking…</EmptyTitle>
        <EmptyDescription>
          Running your query against the data.
        </EmptyDescription>
      </EmptyHeader>
    </Empty>
  )
}

function NoteResult({ summary, value }: { summary: string; value?: string }) {
  return (
    <Empty className="flex-1">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <TableIcon />
        </EmptyMedia>
        <EmptyTitle>{value ?? "Non-tabular result"}</EmptyTitle>
        <EmptyDescription>{summary}</EmptyDescription>
      </EmptyHeader>
    </Empty>
  )
}
