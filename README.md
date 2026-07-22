<div align="center">
  <h1 align="center">
  Supasheet
  </h1>
  <h3 align="center"><strong>Turn your Postgres schema into any business app.</strong></h3>
  <p>Supasheet turns any Supabase project into a complete application platform, not just an admin panel. Auto-generated CRUD, multiple data views (grid, data grid, kanban, calendar, gallery, list, tree), built-in auth with MFA, RBAC and RLS enforced natively by Supabase Postgres, configurable dashboards, charts, AI chat, SQL editor, file storage, comments, templates, and audit logs. All in one open-source React app. The <a href="./supabase/examples">supabase/examples/</a> directory ships ready-made schemas for CRM, HR, Finance, Inventory, Manufacturing, Procurement, Quality, LMS, Hostel, Helpdesk, Store, and Blog: proof it scales from a weekend internal tool to a full ERP or B2B product.</p>
  <p>Try out Supasheet demo at <a href="https://jdydxqrxntcdrxhqqmuv.supasheet.app" target="_blank">jdydxqrxntcdrxhqqmuv.supasheet.app</a></p>
</div>

<h1 align="center">
   <picture>
   <source media="(prefers-color-scheme: dark)" srcset="public/images/bg-dark.png">
   <img alt="supasheet" width="100%" src="public/images/bg-light.png">
   </picture>
</h1>

## Features

Use it as an internal admin panel, or as the backend and UI for a CRM, ERP module, or B2B customer portal. RBAC, RLS, and audit trails are enforced by Supabase Postgres itself, so it's safe to build real business systems on top.

- **Authentication** — Sign in, sign up, MFA, password reset, OAuth providers
- **User Management** — Create, invite, edit, and delete users via Supabase Admin API
- **Authorization (RBAC)** — Role-based access control with user roles and role permissions
- **Resource (CRUD)** — Auto-generated CRUD for any table, driven by Postgres schema metadata
- **Data Views** — Grid, Data Grid, Kanban, Calendar, Gallery, List, Tree, and Single-record views per resource
- **Form Sections** — Organize create/update forms into collapsible titled sections with per-mode field visibility
- **Conditional Fields** — Field visibility, required state, and read-only state driven by other field values
- **FK Behavior** — Auto-fill related fields and cascading dropdowns on foreign key selection
- **Filter Templates** — Saved, named filter presets per resource
- **Record Duplication** — Duplicate records with configurable field selection
- **Dashboard** — Configurable dashboard widgets
- **Analytics & Charts** — Area, bar, line, pie, radar chart types
- **Reports** — Tabular reports built from Supabase data
- **AI Chat** — Conversational interface for querying your data
- **SQL Editor** — Run and save SQL snippets directly from the app
- **Comments** — Per-record threaded comments and collaboration
- **Templates** — Reusable record templates per resource
- **Notifications** — In-app notification system
- **File Storage** — Browse, upload, rename, move, and preview files across Supabase Storage buckets
- **Audit Logs** — App-wide and per-record change history with filtering

## Tech Stack

- **App:** React 19 + Vite
- **Routing:** TanStack Router (file-based, type-safe)
- **Data Fetching:** TanStack Query
- **Forms:** TanStack Form
- **Tables:** TanStack Table
- **UI:** shadcn/ui (Base UI variant) + Tailwind CSS v4
- **Rich Text:** Lexical
- **Charts:** Recharts
- **Backend:** Supabase (Auth, Database, Storage, Edge Functions)

## Getting Started

1. Clone the repo and install dependencies:

```bash
npm install
```

2. Copy `.env.example` and fill in your Supabase credentials:

```bash
cp .env.example .env.local
```

```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

3. Run the development server:

```bash
npm run dev
```

## Scripts

```bash
npx supabase start # Start local Supabase instance
npm run dev        # Start dev server on port 3000
npm run build      # Production build
npm run typecheck  # TypeScript check
npm run lint       # ESLint
npm run check      # Format + lint fix
npm run test       # Run tests
```
