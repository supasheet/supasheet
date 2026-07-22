import type { ComponentProps } from "react"

import { cn } from "#/lib/utils"

const sizeClasses = {
  narrow: "max-w-2xl space-y-4",
  wide: "max-w-6xl space-y-8",
}

interface PageContainerProps extends ComponentProps<"div"> {
  size?: keyof typeof sizeClasses
}

export function PageContainer({
  size = "wide",
  className,
  ...props
}: PageContainerProps) {
  return (
    <div
      className={cn("mx-auto w-full p-6", sizeClasses[size], className)}
      {...props}
    />
  )
}
