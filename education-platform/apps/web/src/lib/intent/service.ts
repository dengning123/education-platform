import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import {
  parseFitAccessContextOptions,
  parseFitIntentDiscovery,
  parseFitIntentDocument,
  parseFitIntentOperationResult,
  parseFitIntentTaxonomyOptions,
  type FitAccessContextOptions,
  type FitIntentDiscovery,
  type FitIntentDocument,
  type FitIntentMutation,
  type FitIntentOperationResult,
  type FitIntentTaxonomyOptions,
} from "./contracts";
import { IntentServiceError, mapIntentRpcError } from "./errors";
import { createClient } from "../supabase/server";

export interface IntentService {
  authenticate(): Promise<void>;
  discover(profileVersionId: string): Promise<FitIntentDiscovery>;
  create(profileVersionId: string, operationId: string): Promise<FitIntentOperationResult>;
  document(intentSetId: string): Promise<FitIntentDocument>;
  mutate(input: Readonly<{ intentSetId: string; operationId: string; expectedRevision: number } & FitIntentMutation>): Promise<FitIntentOperationResult>;
  freeze(intentSetId: string, operationId: string, expectedRevision: number): Promise<FitIntentOperationResult>;
  taxonomy(intentSetId: string, dimension: FitIntentTaxonomyOptions["dimension"]): Promise<FitIntentTaxonomyOptions>;
  accessOptions(intentSetId: string): Promise<FitAccessContextOptions>;
}

export type IntentServiceFactory = (signal: AbortSignal) => Promise<IntentService>;
type RpcResult = Readonly<{ data: unknown; error: unknown }>;
type RpcBuilder = PromiseLike<RpcResult> & { abortSignal(signal: AbortSignal): PromiseLike<RpcResult> };
type IntentSupabaseClient = Pick<SupabaseClient, "auth"> & { rpc(name: string, args?: Record<string, unknown>): RpcBuilder };

const DEPENDENCY_DEADLINE_MS = 10_000;

function createDependencyFetch(requestSignal: AbortSignal): typeof fetch {
  return async (input, init) => fetch(input, {
    ...init,
    signal: AbortSignal.any([
      requestSignal,
      init?.signal ?? new AbortController().signal,
      AbortSignal.timeout(DEPENDENCY_DEADLINE_MS),
    ]),
  });
}

class SupabaseIntentService implements IntentService {
  constructor(private readonly supabase: IntentSupabaseClient, private readonly signal: AbortSignal) {}

  async authenticate(): Promise<void> {
    const { data, error } = await this.supabase.auth.getUser();
    if (this.signal.aborted) throw new IntentServiceError("REQUEST_TIMEOUT");
    if (error || !data.user) throw new IntentServiceError("AUTH_REQUIRED");
  }

  private async rpc(name: string, args: Record<string, unknown> = {}): Promise<unknown> {
    let result: RpcResult;
    try { result = await this.supabase.rpc(name, args).abortSignal(this.signal); }
    catch { throw new IntentServiceError(this.signal.aborted ? "REQUEST_TIMEOUT" : "INTERNAL_ERROR"); }
    if (this.signal.aborted) throw new IntentServiceError("REQUEST_TIMEOUT");
    if (result.error) throw new IntentServiceError(mapIntentRpcError(result.error));
    return result.data;
  }

  async discover(profileVersionId: string) {
    return parseFitIntentDiscovery(await this.rpc("discover_fit_intent_v027", { p_profile_version_id: profileVersionId }));
  }

  async create(profileVersionId: string, operationId: string) {
    return parseFitIntentOperationResult(await this.rpc("create_or_resume_fit_intent_draft_v027", {
      p_profile_version_id: profileVersionId, p_operation_id: operationId,
    }));
  }

  async document(intentSetId: string) {
    return parseFitIntentDocument(await this.rpc("get_fit_intent_document_v027", { p_intent_set_id: intentSetId }));
  }

  async mutate(input: Readonly<{ intentSetId: string; operationId: string; expectedRevision: number } & FitIntentMutation>) {
    return parseFitIntentOperationResult(await this.rpc("mutate_fit_intent_draft_v027", {
      p_intent_set_id: input.intentSetId,
      p_operation_id: input.operationId,
      p_expected_revision: input.expectedRevision,
      p_command: input.command,
      p_payload: input.payload,
    }));
  }

  async freeze(intentSetId: string, operationId: string, expectedRevision: number) {
    return parseFitIntentOperationResult(await this.rpc("freeze_fit_intent_draft_v027", {
      p_intent_set_id: intentSetId, p_operation_id: operationId, p_expected_revision: expectedRevision,
    }));
  }

  async taxonomy(intentSetId: string, dimension: FitIntentTaxonomyOptions["dimension"]) {
    return parseFitIntentTaxonomyOptions(await this.rpc("get_fit_intent_taxonomy_options_v027", {
      p_intent_set_id: intentSetId, p_dimension: dimension,
    }));
  }

  async accessOptions(intentSetId: string) {
    return parseFitAccessContextOptions(await this.rpc("get_fit_access_context_options_v027", { p_intent_set_id: intentSetId }));
  }
}

export const createSupabaseIntentService: IntentServiceFactory = async (signal) => {
  const supabase = await createClient({ customFetch: createDependencyFetch(signal) });
  return new SupabaseIntentService(supabase as unknown as IntentSupabaseClient, signal);
};
