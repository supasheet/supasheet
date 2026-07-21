import {
  corsHeaders,
  createAdminClient,
  errorResponse,
  jsonResponse,
  requireRole,
} from "../_shared/admin.ts"

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders })
  }

  const denied = await requireRole(req.headers.get("Authorization"), "x-admin")
  if (denied) return denied

  const { page = 1, perPage = 50 } = await req.json().catch(() => ({}))

  const adminClient = createAdminClient()
  const { data, error } = await adminClient.auth.admin.listUsers({
    page,
    perPage,
  })
  if (error) {
    console.error("admin-list-users", error)
    return errorResponse("Could not list users", 500)
  }

  return jsonResponse(data)
})
