import {
  createEdgeHttpHandler,
  edgeHttpError,
  jsonSuccess,
  normalizeErrorStatus,
} from "../_shared/http-boundary.js";
import {
  FitAdapterError,
  FitExecutorPostgrestGateway,
  parseFitEvaluationResumeRequest,
  PostgrestGateway,
  resumeFitEvaluation,
} from "../_shared/fit-runtime.js";

const handleRequest = createEdgeHttpHandler({
  endpoint: "FIT_NORMALIZATION_RESUME",
  internalErrorCode: "FIT_NORMALIZATION_RESUME_FAILED_CLOSED",
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
      const parsed = parseFitEvaluationResumeRequest(body);
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
      const executed = await resumeFitEvaluation(
        new FitExecutorPostgrestGateway(
          supabaseUrl,
          serviceRoleKey,
          serviceRoleKey,
          dependencyFetch,
        ),
        parsed,
      );
      return jsonSuccess({
        evaluationId: executed.evaluationId,
        candidateInputFingerprint: executed.candidateInputFingerprint,
        resultFingerprint: executed.resultFingerprint,
        schemaVersion: executed.output.schemaVersion,
        dimensions: executed.output.dimensions,
      }, 201);
    } catch (error) {
      if (error instanceof FitAdapterError) {
        throw edgeHttpError(
          "FIT_NORMALIZATION_RESUME_REJECTED",
          normalizeErrorStatus(error.status),
        );
      }
      throw error;
    }
  },
});

Deno.serve(handleRequest);
