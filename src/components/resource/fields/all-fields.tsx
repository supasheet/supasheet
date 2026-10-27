import type { FieldProps } from "#/types/fields"

import { BooleanField } from "./boolean-field"
import { DateField } from "./date-field"
import { DatetimeField } from "./datetime-field"
import { DurationField } from "./duration-field"
import { JsonField } from "./json-field"
import { LongtextField } from "./long-text-field"
import { MoneyField } from "./money-field"
import { NumberField } from "./number-field"
import { PercentageField } from "./percentage-field"
import { RatingField } from "./rating-field"
import { RichTextField } from "./rich-text-field"
import { SelectField } from "./select-field"
import { TextField } from "./text-field"
import { TimeField } from "./time-field"
import { UuidField } from "./uuid-field"

export function AllFields({ columnMetadata }: FieldProps) {
  switch (columnMetadata.variant) {
    case "uuid":
      return <UuidField columnMetadata={columnMetadata} />
    case "money":
      return <MoneyField columnMetadata={columnMetadata} />
    case "number":
      return <NumberField columnMetadata={columnMetadata} />
    case "percentage":
      return <PercentageField columnMetadata={columnMetadata} />
    case "boolean":
      return <BooleanField columnMetadata={columnMetadata} />
    case "select":
      return <SelectField columnMetadata={columnMetadata} />
    case "date":
      return <DateField columnMetadata={columnMetadata} />
    case "time":
      return <TimeField columnMetadata={columnMetadata} />
    case "datetime":
      return <DatetimeField columnMetadata={columnMetadata} />
    case "json":
      return <JsonField columnMetadata={columnMetadata} />
    case "long_text":
      return <LongtextField columnMetadata={columnMetadata} />
    case "rating":
      return <RatingField columnMetadata={columnMetadata} />
    case "duration":
      return <DurationField columnMetadata={columnMetadata} />
    case "rich_text":
      return <RichTextField columnMetadata={columnMetadata} />
    case "color":
    case "barcode":
    case "email":
    case "tel":
    case "text":
    case "url":
    default:
      return <TextField columnMetadata={columnMetadata} />
  }
}
