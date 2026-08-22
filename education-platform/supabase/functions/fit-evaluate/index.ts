import {
  createEdgeHttpHandler,
  edgeHttpError,
  jsonSuccess,
  normalizeErrorStatus,
} from "../_shared/http-boundary.js";
import {
  executeFitEvaluation,
  FitExecutorPostgrestGateway,
  FitAdapterError,
  loadFitEvaluationSnapshot,
  parseFitEvaluationRequest,
  PostgrestGateway,
} from "../_shared/fit-runtime.js";

const handleRequest = createEdgeHttpHandler({
  endpoint: "FIT_EVALUATE",
  internalErrorCode: "FIT_EVALUATION_FAILED_CLOSED",
  getEnv: (name: string) => Deno.env.get(name),
  handler: async ({ body, authorization }: { body: unknown; authorization: string }) => {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (supabaseUrl === undefined || serviceRoleKey === undefined || anonKey === undefined) {
      throw edgeHttpError("SERVICE_CONFIGURATION_MISSING");
    }

    try {
      const fitRequest = parseFitEvaluationRequest(body);
      const userDatabase = new PostgrestGateway(
        supabaseUrl,
        anonKey,
        authorization.slice("Bearer ".length),
      );
      const ownsProfile = await userDatabase.rpc<boolean>("current_user_owns_profile", {
        p_profile_version_id: fitRequest.profileVersionId,
      });
      if (ownsProfile !== true) throw edgeHttpError("PROFILE_NOT_FOUND");
      const serviceDatabase = new FitExecutorPostgrestGateway(supabaseUrl, serviceRoleKey);
      const sourceDatabase = await loadFitEvaluationSnapshot(serviceDatabase, fitRequest);
      const executed = await executeFitEvaluation(serviceDatabase, fitRequest, sourceDatabase);
      return jsonSuccess({
        evaluationId: executed.evaluationId,
        candidateInputFingerprint: executed.candidateInputFingerprint,
        resultFingerprint: executed.resultFingerprint,
        schemaVersion: executed.output.schemaVersion,
        dimensions: executed.output.dimensions,
      }, 201);
    } catch (error) {
      if (error instanceof FitAdapterError) {
        throw edgeHttpError("FIT_EVALUATION_REJECTED", normalizeErrorStatus(error.status));
      }
      throw error;
    }
  },
});

Deno.serve(handleRequest);
