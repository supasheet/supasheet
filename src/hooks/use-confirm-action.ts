import { useState } from "react"

export function useConfirmAction<T>(
  onConfirm: (item: T) => void | Promise<void>
) {
  const [target, setTarget] = useState<T | null>(null)
  const [pending, setPending] = useState(false)

  return {
    open: target !== null,
    target,
    request: (item: T) => setTarget(item),
    cancel: () => setTarget(null),
    confirm: async () => {
      if (target === null) return
      setPending(true)
      try {
        await onConfirm(target)
      } finally {
        setPending(false)
        setTarget(null)
      }
    },
    pending,
  }
}
