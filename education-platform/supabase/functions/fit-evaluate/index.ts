import {
  createEdgeHttpHandler,
  edgeHttpError,
  jsonSuccess,
  normalizeErrorStatus,
} from "../_shared/http-boundary.js";
import {
  executeFitEvaluation,
  executeProductFitEvaluation,
  fitEvaluationRequestFromProductAssembly,
  FitExecutorPostgrestGateway,
  FitAdapterError,
  isProductFitEvaluationRequest,
  loadFitEvaluationSnapshot,
  loadProductFitEvaluationSnapshot,
  parseProductFitEvaluationRequest,
  parseProductFitIntentAssembly,
  parseFitEvaluationRequest,
  PostgrestGateway,
} from "../_shared/fit-runtime.js";

const handleRequest = createEdgeHttpHandler({
  endpoint: "FIT_EVALUATE",
  internalErrorCode: "FIT_EVALUATION_FAILED_CLOSED",
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
      const productRequest = isProductFitEvaluationRequest(body)
        ? parseProductFitEvaluationRequest(body)
        : null;
      let fitRequest = productRequest === null ? parseFitEvaluationRequest(body) : null;
      const userDatabase = new PostgrestGateway(
        supabaseUrl,
        anonKey,
        authorization.slice("Bearer ".length),
        dependencyFetch,
      );
      const ownsProfile = await userDatabase.rpc<boolean>("current_user_owns_profile", {
        p_profile_version_id: productRequest?.profileVersionId ?? fitRequest!.profileVersionId,
      });
      if (ownsProfile !== true) throw edgeHttpError("PROFILE_NOT_FOUND");
      const productAssembly = productRequest === null ? null : parseProductFitIntentAssembly(
        await userDatabase.rpc<unknown>("get_fit_evaluation_assembly_v027", {
          p_profile_version_id: productRequest.profileVersionId,
          p_intent_set_id: productRequest.intentSetId,
          p_program_version_id: productRequest.programVersionId,
        }),
      );
      if (productRequest !== null && productAssembly !== null) {
        fitRequest = fitEvaluationRequestFromProductAssembly(productRequest, productAssembly);
      }
      const serviceDatabase = new FitExecutorPostgrestGateway(
        supabaseUrl,
        serviceRoleKey,
        serviceRoleKey,
        dependencyFetch,
      );
      const sourceDatabase = productAssembly === null
        ? await loadFitEvaluationSnapshot(serviceDatabase, fitRequest!)
        : await loadProductFitEvaluationSnapshot(serviceDatabase, fitRequest!);
      const executed = productAssembly === null
        ? await executeFitEvaluation(serviceDatabase, fitRequest!, sourceDatabase)
        : await executeProductFitEvaluation(serviceDatabase, fitRequest!, productAssembly, sourceDatabase);
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
