import {
  corsHeaders,
  createAdminClient,
  errorResponse,
  jsonResponse,
  requireRole,
} from "../_shared/admin.ts"

const CREATE_ALLOWED_FIELDS = [
  "email",
  "password",
  "email_confirm",
  "phone",
  "phone_confirm",
  "user_metadata",
] as const

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders })
  }

  const denied = await requireRole(
    req.headers.get("Authorization"),
    "x-admin"
  )
  if (denied) return denied

  const body = await req.json().catch(() => null)
  if (!body?.email) return errorResponse("Missing email", 400)

  const attrs: Record<string, unknown> = {}
  for (const key of CREATE_ALLOWED_FIELDS) {
    if (key in body) attrs[key] = body[key]
  }

  const adminClient = createAdminClient()
  const { data, error } = await adminClient.auth.admin.createUser(attrs)
  if (error) {
    console.error("admin-create-user", error)
    return errorResponse("Could not create user", 400)
  }

  return jsonResponse(data, 201)
})
