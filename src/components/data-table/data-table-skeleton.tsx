import { Skeleton } from "#/components/ui/skeleton"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import { cn } from "#/lib/utils"

interface DataTableSkeletonProps extends React.ComponentProps<"div"> {
  columnCount: number
  rowCount?: number
  cellWidths?: string[]
  withViewOptions?: boolean
  withPagination?: boolean
  shrinkZero?: boolean
}

export function DataTableSkeleton({
  columnCount,
  rowCount = 20,
  cellWidths = ["auto"],
  withViewOptions = true,
  withPagination = true,
  shrinkZero = false,
  className,
  ...props
}: DataTableSkeletonProps) {
  const cozyCellWidths = Array.from(
    { length: columnCount },
    (_, index) => cellWidths[index % cellWidths.length] ?? "auto"
  )

  return (
    <div className={cn("flex flex-col gap-2", className)} {...props}>
      {/* Toolbar */}
      <div className="flex items-center justify-between">
        <Skeleton className="h-7 w-16" />
        {withViewOptions ? <Skeleton className="h-7 w-24" /> : null}
      </div>

      {/* Table */}
      <div className="overflow-hidden rounded-md border">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              {Array.from({ length: columnCount }).map((_, j) => (
                <TableHead
                  key={j}
                  style={{
                    width: cozyCellWidths[j],
                    minWidth: shrinkZero ? cozyCellWidths[j] : "auto",
                  }}
                >
                  <Skeleton className="h-6 w-full" />
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {Array.from({ length: rowCount }).map((_, i) => (
              <TableRow key={i} className="hover:bg-transparent">
                {Array.from({ length: columnCount }).map((_col, j) => (
                  <TableCell
                    key={j}
                    style={{
                      width: cozyCellWidths[j],
                      minWidth: shrinkZero ? cozyCellWidths[j] : "auto",
                    }}
                  >
                    <Skeleton className="h-6 w-full" />
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      {/* Pagination */}
      {withPagination ? (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <Skeleton className="h-5 w-32" />
          <div className="flex flex-wrap items-center gap-2">
            <div className="flex items-center gap-2">
              <Skeleton className="hidden h-5 w-24 sm:block" />
              <Skeleton className="h-7 w-14" />
            </div>
            <div className="flex items-center gap-1.5">
              <Skeleton className="size-7" />
              <Skeleton className="h-7 w-12" />
              <Skeleton className="h-5 w-12" />
              <Skeleton className="size-7" />
            </div>
          </div>
        </div>
      ) : null}
    </div>
  )
}
