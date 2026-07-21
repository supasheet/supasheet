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

  const { userId } = await req.json().catch(() => ({}))
  if (!userId) return errorResponse("Missing userId", 400)

  const adminClient = createAdminClient()
  const { data, error } = await adminClient.auth.admin.getUserById(userId)
  if (error) {
    console.error("admin-get-user", error)
    return errorResponse("Could not load user", 404)
  }

  return jsonResponse(data)
})
