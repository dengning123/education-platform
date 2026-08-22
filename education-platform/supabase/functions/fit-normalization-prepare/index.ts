import {
  createEdgeHttpHandler,
  edgeHttpError,
  jsonSuccess,
  normalizeErrorStatus,
} from "../_shared/http-boundary.js";
import {
  FitAdapterError,
  FitExecutorPostgrestGateway,
  parseFitFinancialNormalizationDraftRequest,
  PostgrestGateway,
  prepareFitFinancialNormalization,
} from "../_shared/fit-runtime.js";

const handleRequest = createEdgeHttpHandler({
  endpoint: "FIT_NORMALIZATION_PREPARE",
  internalErrorCode: "FIT_NORMALIZATION_PREPARATION_FAILED_CLOSED",
  getEnv: (name: string) => Deno.env.get(name),
  handler: async ({ body, authorization, dependencyFetch }: {
    body: unknown;
    authorization: string;
    dependencyFetch: typeof fetch;
  }) => {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (supabaseUrl === undefined || serviceRoleKey === undefined || anonKey === undefined) {
      throw edgeHttpError("SERVICE_CONFIGURATION_MISSING");
    }

    try {
      const parsed = parseFitFinancialNormalizationDraftRequest(body);
      const userDatabase = new PostgrestGateway(
        supabaseUrl,
        anonKey,
        authorization.slice("Bearer ".length),
        dependencyFetch,
      );
      const ownsProfile = await userDatabase.rpc<boolean>("current_user_owns_profile", {
        p_profile_version_id: parsed.evaluation.profileVersionId,
      });
      if (ownsProfile !== true) throw edgeHttpError("PROFILE_NOT_FOUND");
      const prepared = await prepareFitFinancialNormalization(
        new FitExecutorPostgrestGateway(
          supabaseUrl,
          serviceRoleKey,
          serviceRoleKey,
          dependencyFetch,
        ),
        parsed,
      );
      return jsonSuccess(prepared, 202);
    } catch (error) {
      if (error instanceof FitAdapterError) {
        throw edgeHttpError(
          "FIT_NORMALIZATION_PREPARATION_REJECTED",
          normalizeErrorStatus(error.status),
        );
      }
      throw error;
    }
  },
});

Deno.serve(handleRequest);
