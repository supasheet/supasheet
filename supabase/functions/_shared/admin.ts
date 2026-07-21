import { createClient } from "npm:@supabase/supabase-js@2"

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
}

/** Service-role client — can call auth.admin.* APIs */
export function createAdminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )
}

/** User-scoped client — used only to verify permissions via RLS / has_role() */
function createUserClient(authHeader: string) {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  )
}

/**
 * Resolve the authenticated caller's user ID from the Authorization header.
 * Returns the UUID string, or null if the token is missing/invalid.
 */
export async function getCallerId(
  authHeader: string | null
): Promise<string | null> {
  if (!authHeader) return null
  const userClient = createUserClient(authHeader)
  const { data } = await userClient.auth.getUser()
  return data.user?.id ?? null
}

/**
 * Verify the caller's active native Postgres role is a member of `role`
 * (pg_has_role, via supasheet.has_role). Returns a Response if access should
 * be denied, or null if allowed.
 */
export async function requireRole(
  authHeader: string | null,
  role: string
): Promise<Response | null> {
  if (!authHeader) {
    return errorResponse("Missing authorization header", 401)
  }

  const userClient = createUserClient(authHeader)
  const { data, error } = await userClient
    .schema("supasheet")
    .rpc("has_role", { requested_role: role })

  if (error) {
    console.error("requireRole rpc", error)
    return errorResponse("Permission check failed", 500)
  }
  if (!data) return errorResponse("Forbidden", 403)

  return null
}

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

export function errorResponse(message: string, status = 500): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
