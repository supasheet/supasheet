import { useState } from "react"

export function useDeleteConfirm<T>(
  onDelete: (item: T) => void | Promise<void>
) {
  const [target, setTarget] = useState<T | null>(null)
  const [pending, setPending] = useState(false)

  return {
    open: target !== null,
    requestDelete: (item: T) => setTarget(item),
    cancel: () => setTarget(null),
    confirm: async () => {
      if (target === null) return
      setPending(true)
      try {
        await onDelete(target)
      } finally {
        setPending(false)
        setTarget(null)
      }
    },
    pending,
  }
}
