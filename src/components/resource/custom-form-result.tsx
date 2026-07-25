import type { FormResult } from "#/hooks/use-custom-form"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "#/components/ui/card"
import { Label } from "#/components/ui/label"
import {
  Table,
  TableBody,
  TableCell,
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
} from "#/components/ui/table"
import { computeAggregate, formatAggregateValue } from "#/lib/aggregate"
import { formatTitle } from "#/lib/format"

function formatCellValue(value: unknown) {
  if (value === null || value === undefined)
    return <span className="text-muted">N/A</span>
  if (typeof value === "boolean") return value ? "true" : "false"
  if (typeof value === "object")
    return (
      <code className="text-xs text-muted-foreground">
        {JSON.stringify(value)}
      </code>
    )
  return String(value)
}

function isNumericColumn(values: unknown[]) {
  const nonNull = values.filter((v) => v !== null && v !== undefined && v !== "")
  return (
    nonNull.length > 0 &&
    nonNull.every((v) => typeof v === "number" || !isNaN(Number(v)))
  )
}

function CustomFormResultCard({ record }: { record: Record<string, unknown> }) {
  const entries = Object.entries(record)

  return (
    <Card>
      <CardHeader>
        <div className="space-y-1.5">
          <CardTitle>Result</CardTitle>
          <CardDescription>View resource details and properties</CardDescription>
        </div>
      </CardHeader>
      <CardContent className="grid grid-cols-1 gap-4 py-4 md:grid-cols-2">
        {entries.map(([key, value]) => (
          <div key={key} className="flex min-w-0 flex-col gap-1.5">
            <Label className="inline-flex items-center gap-1.5 text-sm font-medium">
              {formatTitle(key)}
            </Label>
            <div className="text-sm text-muted-foreground">
              {formatCellValue(value)}
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}

function CustomFormResultTable({ rows }: { rows: Record<string, unknown>[] }) {
  const columns = Object.keys(rows[0])

  return (
    <div className="overflow-auto rounded-md border bg-card">
      <Table>
        <TableHeader>
          <TableRow>
            {columns.map((col) => (
              <TableHead key={col}>{formatTitle(col)}</TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row, i) => (
            <TableRow key={i}>
              {columns.map((col) => (
                <TableCell key={col}>{formatCellValue(row[col])}</TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
        <TableFooter>
          <TableRow>
            {columns.map((col) => {
              const values = rows.map((row) => row[col])
              const numeric = isNumericColumn(values)
              const fn = numeric ? "sum" : "count"
              const result = computeAggregate(
                values,
                fn,
                numeric ? "number" : "text"
              )
              return (
                <TableCell key={col} className="text-xs text-muted-foreground">
                  {numeric ? "Sum: " : "Count: "}
                  {formatAggregateValue(result)}
                </TableCell>
              )
            })}
          </TableRow>
        </TableFooter>
      </Table>
    </div>
  )
}

export function CustomFormResult({ result }: { result: FormResult }) {
  if (result.kind === "object") {
    return <CustomFormResultCard record={result.data} />
  }

  if (result.data.length === 0) {
    return (
      <div className="rounded-md border bg-card p-6 text-center text-sm text-muted-foreground">
        No rows returned.
      </div>
    )
  }

  return <CustomFormResultTable rows={result.data} />
}
