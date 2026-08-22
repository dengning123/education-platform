import {
  createEdgeHttpHandler,
  edgeHttpError,
  jsonSuccess,
  normalizeErrorStatus,
} from "../_shared/http-boundary.js";
import {
  FitAdapterError,
  parseFitFinancialNormalizationReviewRequest,
  PostgrestGateway,
} from "../_shared/fit-runtime.js";

const handleRequest = createEdgeHttpHandler({
  endpoint: "FIT_NORMALIZATION_REVIEW",
  internalErrorCode: "FIT_NORMALIZATION_REVIEW_FAILED_CLOSED",
  getEnv: (name: string) => Deno.env.get(name),
  handler: async ({ body, authorization }: { body: unknown; authorization: string }) => {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (supabaseUrl === undefined || anonKey === undefined) {
      throw edgeHttpError("SERVICE_CONFIGURATION_MISSING");
    }

    try {
      const parsed = parseFitFinancialNormalizationReviewRequest(body);
      const userDatabase = new PostgrestGateway(
        supabaseUrl,
        anonKey,
        authorization.slice("Bearer ".length),
      );
      const reviewed = await userDatabase.rpc("review_fit_financial_normalization_v017", {
        p_financial_normalization_id: parsed.normalizationId,
        p_verification_evidence_id: parsed.verificationEvidenceId,
      });
      return jsonSuccess(reviewed, 200);
    } catch (error) {
      if (error instanceof FitAdapterError) {
        throw edgeHttpError(
          "FIT_NORMALIZATION_REVIEW_REJECTED",
          normalizeErrorStatus(error.status),
        );
      }
      throw error;
    }
  },
});

Deno.serve(handleRequest);
