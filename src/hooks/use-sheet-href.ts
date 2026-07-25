import { useLocation } from "@tanstack/react-router"

const SUPPORTED_VIEW_RE =
  /\/(table|grid|kanban\/[^/]+|calendar\/[^/]+|gallery\/[^/]+|list\/[^/]+|tree\/[^/]+|[^/]+\/detail(?:\/(?!sheet$)[^/]+)?)$/

export type SheetLink = {
  to: string
  search: Record<string, unknown>
}

export function useSheetHref(
  search: Record<string, unknown>
): SheetLink | null {
  const { pathname } = useLocation()
  if (!SUPPORTED_VIEW_RE.test(pathname)) return null
  const cleaned: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(search)) {
    if (value === undefined) continue
    cleaned[key] = value
  }
  return { to: `${pathname}/sheet`, search: cleaned }
}
