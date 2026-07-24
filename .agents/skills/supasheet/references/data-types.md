# Column Data Types & Column Comment Options

Supasheet ships custom domain types (defined in `supabase/migrations/20250405004232_data_types.sql`). Using them changes how the column renders and edits in the UI — validation, pickers, previews — with zero app code.

## Domain types (exact definitions)

```sql
create type supasheet.FILE_OBJECT as (
  name VARCHAR(255), type VARCHAR(100), size BIGINT, url TEXT, last_modified TIMESTAMP
);
create domain supasheet.FILE as supasheet.FILE_OBJECT[];
create domain supasheet.EMAIL as text;
create domain supasheet.TEL as text;
create domain supasheet.RATING as real check (value >= 0 and value <= 5);
create domain supasheet.PERCENTAGE as real;
create domain supasheet.URL as text;
create domain supasheet.DURATION as bigint;
create domain supasheet.COLOR as varchar(16);
create domain supasheet.AVATAR as supasheet.FILE_OBJECT;
create domain supasheet.RICH_TEXT as text;
```

| Type                   | Underlying            | UI behavior                              |
| ---------------------- | --------------------- | ---------------------------------------- |
| `supasheet.EMAIL`      | text                  | validated, clickable `mailto:`           |
| `supasheet.TEL`        | text                  | clickable `tel:`, intl formatting        |
| `supasheet.URL`        | text                  | clickable link, opens new tab            |
| `supasheet.RICH_TEXT`  | text                  | WYSIWYG editor (Lexical)                 |
| `supasheet.RATING`     | real (0–5)            | interactive star input                   |
| `supasheet.PERCENTAGE` | real                  | progress bar, rendered "75%"             |
| `supasheet.DURATION`   | bigint (milliseconds) | human-readable "2h 30m", duration picker |
| `supasheet.COLOR`      | varchar(16)           | color picker, hex `#RRGGBB`              |
| `supasheet.FILE`       | `FILE_OBJECT[]`       | drag-drop multi-file upload              |
| `supasheet.AVATAR`     | single `FILE_OBJECT`  | single image, circular avatar preview    |

`FILE_OBJECT` stores `{ name, type, size, url, last_modified }`. `FILE` is an **array** of those; `AVATAR` is a **single** one. Files land in the `uploads` bucket (see `storage.md`).

Standard Postgres types (text, varchar, numeric, boolean, date, timestamptz, uuid, arrays like `varchar(500)[]`, and your own enums) all render sensibly too.

## Column comment options

Column comments are JSON. All columns accept the base keys; specific types add more.

### Base (any column)

```sql
comment on column app.tickets.title is '{"name": "Ticket Title", "description": "Shown in headers", "icon": "Type"}';
```

`name` overrides the header label in tables, reports, FK display columns, and CSV export. `icon` is a Lucide React icon name.

### File columns (`supasheet.FILE`)

`accept` (default `"*"`), `maxSize` in bytes (default 5242880), `maxFiles` (default 1):

```sql
comment on column app.tickets.attachments is '{"accept": "*", "maxFiles": 20}';

comment on column app.clients.logo is '{"accept": "image/*", "maxSize": 2097152}';

comment on column app.docs.contract is '{"accept": ".pdf", "maxSize": 10485760, "maxFiles": 1}';
```

### Avatar columns (`supasheet.AVATAR`)

`maxSize` only:

```sql
comment on column app.team_members.avatar is '{"accept":"image/*"}';

comment on column app.authors.avatar is '{"maxSize": 2097152}';
```

### Enum columns

`values` maps each enum value to a badge `variant` + optional `icon`; `progress: true` renders the enum as an ordered progress indicator (use for pipeline-like statuses):

```sql
comment on column app.tickets.status is '{
    "progress": true,
    "values": {
        "open":        {"variant": "info",      "icon": "CircleDot"},
        "in_progress": {"variant": "warning",   "icon": "Loader"},
        "resolved":    {"variant": "success",   "icon": "CheckCircle2"},
        "closed":      {"variant": "secondary", "icon": "XCircle"}
    }
}';
```

Variants: `default` | `secondary` | `success` | `warning` | `destructive` | `info`.

## Byte-size constants

| Size   | Bytes     |
| ------ | --------- |
| 1 MB   | 1048576   |
| 2 MB   | 2097152   |
| 5 MB   | 5242880   |
| 10 MB  | 10485760  |
| 25 MB  | 26214400  |
| 50 MB  | 52428800  |
| 100 MB | 104857600 |

## Authoritative sources

- `supabase/migrations/20250405004232_data_types.sql` — domain definitions
- `src/lib/database-meta.types.ts` — `ColumnMetadata`, `EnumColumnMetadata`, `FileColumnMetadata`, `AvatarColumnMetadata`
- `supabase/demo.sql` — every type used in context (clients, team_members, tasks, time_entries)
