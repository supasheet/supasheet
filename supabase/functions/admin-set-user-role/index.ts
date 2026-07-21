import {
  corsHeaders,
  createAdminClient,
  errorResponse,
  getCallerId,
  jsonResponse,
  requireRole,
} from "../_shared/admin.ts"

const KNOWN_ROLES = ["x-admin", "admin", "user"] as const

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders })
  }

  const body = await req.json().catch(() => null)
  if (!body?.userId) return errorResponse("Missing userId", 400)
  if (!KNOWN_ROLES.includes(body.role)) {
    return errorResponse(`Invalid role: ${body.role}`, 400)
  }

  const { userId, role } = body

  const callerId = await getCallerId(req.headers.get("Authorization"))
  if (callerId === userId)
    return errorResponse(
      "Cannot change your own role via this endpoint",
      403
    )

  const denied = await requireRole(req.headers.get("Authorization"), "x-admin")
  if (denied) return denied

  const adminClient = createAdminClient()
  const { data, error } = await adminClient.auth.admin.updateUserById(userId, {
    app_metadata: { role },
  })
  if (error) {
    console.error("admin-set-user-role", error)
    return errorResponse("Could not update user role", 400)
  }

  return jsonResponse(data)
})
