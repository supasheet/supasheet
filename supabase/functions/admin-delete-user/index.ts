import {
  corsHeaders,
  createAdminClient,
  errorResponse,
  getCallerId,
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

  const callerId = await getCallerId(req.headers.get("Authorization"))
  if (callerId === userId)
    return errorResponse(
      "Cannot delete your own account via this endpoint",
      403
    )

  const adminClient = createAdminClient()

  // Delete the auth user — the supasheet.users row has no ON DELETE CASCADE
  // from auth.users, so we clean it up explicitly first.
  await adminClient.schema("supasheet").from("users").delete().eq("id", userId)

  const { error } = await adminClient.auth.admin.deleteUser(userId)
  if (error) {
    console.error("admin-delete-user", error)
    return errorResponse("Could not delete user", 400)
  }

  return jsonResponse({ success: true })
})
