import {
  FitAdapterError,
  parseFitFinancialNormalizationReviewRequest,
  PostgrestGateway,
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
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (supabaseUrl === undefined || anonKey === undefined) return json({ error: "SERVICE_CONFIGURATION_MISSING" }, 500);
  try {
    const parsed = parseFitFinancialNormalizationReviewRequest(await request.json());
    const userDatabase = new PostgrestGateway(supabaseUrl, anonKey, authorization.slice("Bearer ".length));
    const reviewed = await userDatabase.rpc("review_fit_financial_normalization_v017", {
      p_financial_normalization_id: parsed.normalizationId,
      p_verification_evidence_id: parsed.verificationEvidenceId,
    });
    return json(reviewed, 200);
  } catch (error) {
    if (error instanceof FitAdapterError) return json({ error: "FIT_NORMALIZATION_REVIEW_REJECTED", message: error.message, detail: error.detail ?? null }, error.status);
    return json({ error: "FIT_NORMALIZATION_REVIEW_FAILED_CLOSED" }, 500);
  }
});
