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

  const {
    email,
    data: userData,
    redirectTo,
  } = await req.json().catch(() => ({}))
  if (!email) return errorResponse("Missing email", 400)

  const adminClient = createAdminClient()
  const { data, error } = await adminClient.auth.admin.inviteUserByEmail(
    email,
    {
      data: userData,
      redirectTo,
    }
  )
  if (error) {
    console.error("admin-invite-user", error)
    return errorResponse("Could not invite user", 400)
  }

  return jsonResponse(data, 201)
})
