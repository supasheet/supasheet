import { supabase } from "#/lib/supabase/client"

import type { AIResponse, ChatMessage, MutationKind } from "./types"

const PLATFORM_URL = import.meta.env.VITE_SUPASHEET_PLATFORM as
  string | undefined

async function platformHeaders(): Promise<Record<string, string>> {
  if (!PLATFORM_URL) {
    throw new Error("VITE_SUPASHEET_PLATFORM is not configured")
  }

  const {
    data: { session },
  } = await supabase.auth.getSession()
  if (!session) throw new Error("Not authenticated")

  const supabaseUrl =
    localStorage.getItem("supabase-url") ??
    (import.meta.env.VITE_SUPABASE_URL as string)
  const anonKey =
    localStorage.getItem("supabase-pubkey") ??
    (import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string)

  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${session.access_token}`,
    apikey: anonKey,
    "x-supabase-url": supabaseUrl,
  }
}

export async function askAI(
  question: string,
  history: ChatMessage[]
): Promise<AIResponse> {
  const headers = await platformHeaders()

  const messages = [
    ...history.map((m) => ({ role: m.role, content: m.content })),
    { role: "user", content: question },
  ]

  const res = await fetch(`${PLATFORM_URL}/api/ai/retrieval`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      today: new Date().toLocaleDateString("en-CA"),
      messages,
    }),
  })

  if (!res.ok) throw new Error((await res.text()) || `HTTP ${res.status}`)
  return (await res.json()) as AIResponse
}

export async function confirmMutation(args: {
  mutationSql: string
  kind: MutationKind
  summary: string
}): Promise<AIResponse> {
  const headers = await platformHeaders()

  const res = await fetch(`${PLATFORM_URL}/api/ai/confirm`, {
    method: "POST",
    headers,
    body: JSON.stringify(args),
  })

  if (!res.ok) throw new Error((await res.text()) || `HTTP ${res.status}`)
  return (await res.json()) as AIResponse
}
