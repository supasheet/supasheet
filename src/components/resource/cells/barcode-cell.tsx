import { useEffect, useRef } from "react"

import JsBarcode from "jsbarcode"

export function BarcodeCell({ value }: { value: string | null }) {
  const ref = useRef<SVGSVGElement>(null)

  useEffect(() => {
    if (!ref.current || !value) return
    try {
      JsBarcode(ref.current, value, {
        format: "CODE128",
        displayValue: false,
        height: 20,
        width: 1,
        margin: 0,
        background: "transparent",
        lineColor: "currentColor",
      })
    } catch {
      ref.current.replaceChildren()
    }
  }, [value])

  if (!value) return null

  return (
    <div className="flex items-center gap-2">
      <svg ref={ref} className="h-5 w-auto max-w-24 shrink-0" />
      <span className="truncate font-mono text-xs">{value}</span>
    </div>
  )
}
