create type supasheet.FILE_OBJECT as (
  name VARCHAR(255),
  type VARCHAR(100),
  size BIGINT,
  url TEXT,
  last_modified TIMESTAMP
);

create domain supasheet.FILE as supasheet.FILE_OBJECT[];

create domain supasheet.EMAIL as text;

create domain supasheet.TEL as text;

create domain supasheet.RATING as real check (
  value >= 0
  and value <= 5
);

create domain supasheet.PERCENTAGE as real;

create domain supasheet.URL as text;

create domain supasheet.DURATION as bigint;

create domain supasheet.COLOR as varchar(16);

create domain supasheet.AVATAR as supasheet.FILE_OBJECT;

create domain supasheet.RICH_TEXT as text;

create domain supasheet.BARCODE as text;
