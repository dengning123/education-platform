import {
  FitAdapterError,
  FitExecutorPostgrestGateway,
  parseFitFinancialNormalizationDraftRequest,
  PostgrestGateway,
  prepareFitFinancialNormalization,
} from "../_shared/fit-runtime.js";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, apikey, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
};
const json = (body: unknown, status: number) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8" },
});

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const authorization = request.headers.get("authorization");
  if (authorization === null || !authorization.startsWith("Bearer ")) return json({ error: "AUTHENTICATION_REQUIRED" }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (supabaseUrl === undefined || serviceRoleKey === undefined || anonKey === undefined) return json({ error: "SERVICE_CONFIGURATION_MISSING" }, 500);
  try {
    const parsed = parseFitFinancialNormalizationDraftRequest(await request.json());
    const userDatabase = new PostgrestGateway(supabaseUrl, anonKey, authorization.slice("Bearer ".length));
    const ownsProfile = await userDatabase.rpc<boolean>("current_user_owns_profile", { p_profile_version_id: parsed.evaluation.profileVersionId });
    if (ownsProfile !== true) return json({ error: "PROFILE_NOT_FOUND" }, 404);
    const prepared = await prepareFitFinancialNormalization(new FitExecutorPostgrestGateway(supabaseUrl, serviceRoleKey), parsed);
    return json(prepared, 202);
  } catch (error) {
    if (error instanceof FitAdapterError) return json({ error: "FIT_NORMALIZATION_PREPARATION_REJECTED", message: error.message, detail: error.detail ?? null }, error.status);
    return json({ error: "FIT_NORMALIZATION_PREPARATION_FAILED_CLOSED" }, 500);
  }
});
