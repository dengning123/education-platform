import "server-only";

import {
  projectEligibilityAssemblyResult,
  projectFitEdgeResult,
  type EligibilityConnectionRequest,
  type EligibilityConnectionResult,
  type FitConnectionRequest,
  type FitConnectionResult,
} from "./contracts";
import { EvaluationContractError } from "./contracts";
import { EvaluationServiceError } from "./errors";
import { createClient } from "../supabase/server";

export interface EvaluationService {
  authenticate(): Promise<void>;
  eligibility(input: EligibilityConnectionRequest): Promise<EligibilityConnectionResult>;
  fit(input: FitConnectionRequest): Promise<FitConnectionResult>;
}

export type EvaluationServiceFactory = (signal: AbortSignal) => Promise<EvaluationService>;

export type EvaluationAuthClient = {
  auth: {
    getUser(): Promise<Readonly<{ data: Readonly<{ user: unknown | null }>; error: unknown }>>;
    getSession(): Promise<Readonly<{ data: Readonly<{ session: Readonly<{ access_token: string }> | null }>; error: unknown }>>;
  };
  rpc(functionName: string, args: Record<string, unknown>): PromiseLike<Readonly<{ data: unknown; error: unknown }>>;
};

const DEPENDENCY_DEADLINE_MS = 45_000;

function createDependencyFetch(requestSignal: AbortSignal): typeof fetch {
  return async (input, init) => fetch(input, {
    ...init,
    signal: AbortSignal.any([requestSignal, init?.signal ?? new AbortController().signal, AbortSignal.timeout(DEPENDENCY_DEADLINE_MS)]),
  });
}

function mapFitFailure(status: number): EvaluationServiceError {
  if (status === 401) return new EvaluationServiceError("AUTH_REQUIRED");
  if (status === 403) return new EvaluationServiceError("ACCESS_DENIED");
  if (status === 404) return new EvaluationServiceError("RESOURCE_NOT_FOUND");
  if (status === 408 || status === 504) return new EvaluationServiceError("REQUEST_TIMEOUT");
  if (status === 400 || status === 409 || status === 422) return new EvaluationServiceError("INVALID_REQUEST");
  return new EvaluationServiceError("INTERNAL_ERROR");
}

const ELIGIBILITY_DEPENDENCY_ERRORS = new Set([
  "AUTH_REQUIRED", "ACCESS_DENIED", "PROFILE_NOT_FOUND", "PROFILE_NOT_FROZEN",
  "PROGRAM_NOT_FOUND", "ELIGIBILITY_RULESET_NOT_FOUND", "ELIGIBILITY_RULESET_AMBIGUOUS",
  "ELIGIBILITY_INPUT_INVALID", "ELIGIBILITY_ASSEMBLY_CONFLICT", "REQUEST_TIMEOUT", "INTERNAL_ERROR",
]);

function mapEligibilityFailure(error: unknown): EvaluationServiceError {
  const message = error !== null && typeof error === "object" && "message" in error
    && typeof error.message === "string" ? error.message : "INTERNAL_ERROR";
  return new EvaluationServiceError(
    ELIGIBILITY_DEPENDENCY_ERRORS.has(message)
      ? message as ConstructorParameters<typeof EvaluationServiceError>[0]
      : "INTERNAL_ERROR",
  );
}

export class SupabaseEvaluationService implements EvaluationService {
  private accessToken: string | null = null;

  constructor(
    private readonly supabase: EvaluationAuthClient,
    private readonly signal: AbortSignal,
    private readonly dependencyFetch: typeof fetch,
  ) {}

  async authenticate(): Promise<void> {
    const userResult = await this.supabase.auth.getUser();
    if (this.signal.aborted) throw new EvaluationServiceError("REQUEST_TIMEOUT");
    if (userResult.error || !userResult.data.user) throw new EvaluationServiceError("AUTH_REQUIRED");
    const sessionResult = await this.supabase.auth.getSession();
    const token = sessionResult.data.session?.access_token;
    if (sessionResult.error || typeof token !== "string" || token.length === 0) throw new EvaluationServiceError("AUTH_REQUIRED");
    this.accessToken = token;
  }

  private token(): string {
    if (this.accessToken === null) throw new EvaluationServiceError("AUTH_REQUIRED");
    return this.accessToken;
  }

  async eligibility(input: EligibilityConnectionRequest): Promise<EligibilityConnectionResult> {
    let result: Readonly<{ data: unknown; error: unknown }>;
    try {
      result = await this.supabase.rpc("assemble_eligibility_evaluation_v030", {
        p_profile_version_id: input.profileVersionId,
        p_program_version_id: input.programVersionId,
        p_operation_id: input.operationId,
      });
    } catch {
      throw new EvaluationServiceError(this.signal.aborted ? "REQUEST_TIMEOUT" : "INTERNAL_ERROR");
    }
    if (result.error) throw mapEligibilityFailure(result.error);
    try {
      return projectEligibilityAssemblyResult(result.data);
    } catch (error) {
      if (error instanceof EvaluationContractError) throw new EvaluationServiceError("INTERNAL_ERROR");
      throw error;
    }
  }

  async fit(input: FitConnectionRequest): Promise<FitConnectionResult> {
    const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const publicKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!baseUrl || !publicKey) throw new EvaluationServiceError("INTERNAL_ERROR");
    const edgeRequest = {
      schemaVersion: "FIT_PRODUCT_EVALUATION_REQUEST_V027",
      profileVersionId: input.profileVersionId,
      intentSetId: input.intentSetId,
      programVersionId: input.programVersionId,
      eligibilityContextEvaluationId: input.completedEligibilityEvaluationId,
    };

    let response: Response;
    try {
      response = await this.dependencyFetch(new URL("/functions/v1/fit-evaluate", baseUrl), {
        method: "POST",
        headers: {
          apikey: publicKey,
          authorization: `Bearer ${this.token()}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(edgeRequest),
      });
    } catch {
      throw new EvaluationServiceError("REQUEST_TIMEOUT");
    }
    if (!response.ok) throw mapFitFailure(response.status);
    let body: unknown;
    try { body = await response.json(); } catch { throw new EvaluationServiceError("INTERNAL_ERROR"); }
    try {
      return projectFitEdgeResult(body);
    } catch (error) {
      if (error instanceof EvaluationContractError) throw new EvaluationServiceError("INTERNAL_ERROR");
      throw error;
    }
  }
}

export const createSupabaseEvaluationService: EvaluationServiceFactory = async (signal) => {
  const dependencyFetch = createDependencyFetch(signal);
  const supabase = await createClient({ customFetch: dependencyFetch });
  return new SupabaseEvaluationService(supabase as unknown as EvaluationAuthClient, signal, dependencyFetch);
};
