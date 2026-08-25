import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import {
  parseProfileAccount,
  parseProfileDocument,
  parseProfileFrozenDiscovery,
  parseProfileOperationResult,
  parseProfileReadiness,
  parseProfileTaxonomyOptions,
  parseProfileTaxonomyProjection,
  type ProfileAccount,
  type ProfileDocument,
  type ProfileFrozenDiscovery,
  type ProfileMutationCommand,
  type ProfileOperationResult,
  type ProfileReadiness,
  type ProfileTaxonomyOptionKind,
  type ProfileTaxonomyOptions,
  type ProfileTaxonomyProjection,
} from "@/lib/profile/contracts";
import { mapProfileRpcError, ProfileServiceError } from "@/lib/profile/errors";
import { createClient } from "@/lib/supabase/server";

export interface ProfileService {
  authenticate(): Promise<void>;
  bootstrap(): Promise<ProfileAccount>;
  createOrResume(operationId: string): Promise<ProfileOperationResult>;
  currentDocument(): Promise<ProfileDocument>;
  knownDocument(profileVersionId: string): Promise<ProfileDocument>;
  latestFrozen(): Promise<ProfileFrozenDiscovery>;
  readiness(profileVersionId: string): Promise<ProfileReadiness>;
  taxonomy(profileVersionId: string | null): Promise<ProfileTaxonomyProjection>;
  taxonomyOptions(conceptKind: ProfileTaxonomyOptionKind): Promise<ProfileTaxonomyOptions>;
  mutate(input: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number } & ProfileMutationCommand>): Promise<ProfileOperationResult>;
  freeze(input: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }>): Promise<ProfileOperationResult>;
  fork(input: Readonly<{ sourceProfileVersionId: string; operationId: string }>): Promise<ProfileOperationResult>;
}

export type ProfileServiceFactory = (signal: AbortSignal) => Promise<ProfileService>;

type RpcResult = Readonly<{ data: unknown; error: unknown }>;
type RpcBuilder = PromiseLike<RpcResult> & { abortSignal(signal: AbortSignal): PromiseLike<RpcResult> };
type ProfileSupabaseClient = Pick<SupabaseClient, "auth"> & {
  rpc(functionName: string, args?: Record<string, unknown>): RpcBuilder;
};

const PROFILE_DEPENDENCY_DEADLINE_MS = 10_000;

function combinedSignal(signal: AbortSignal | null | undefined, timeoutSignal: AbortSignal): AbortSignal {
  return signal ? AbortSignal.any([signal, timeoutSignal]) : timeoutSignal;
}

function createDependencyFetch(requestSignal: AbortSignal): typeof fetch {
  return async (input, init) => {
    const timeoutSignal = AbortSignal.timeout(PROFILE_DEPENDENCY_DEADLINE_MS);
    return fetch(input, {
      ...init,
      signal: AbortSignal.any([requestSignal, combinedSignal(init?.signal, timeoutSignal)]),
    });
  };
}

class SupabaseProfileService implements ProfileService {
  constructor(
    private readonly supabase: ProfileSupabaseClient,
    private readonly signal: AbortSignal,
  ) {}

  async authenticate(): Promise<void> {
    const { data, error } = await this.supabase.auth.getUser();
    if (this.signal.aborted) throw new ProfileServiceError("REQUEST_TIMEOUT");
    if (error || !data.user) throw new ProfileServiceError("AUTH_REQUIRED");
  }

  private async rpc(functionName: string, args: Record<string, unknown> = {}): Promise<unknown> {
    let result: RpcResult;
    try {
      result = await this.supabase.rpc(functionName, args).abortSignal(this.signal);
    } catch {
      throw new ProfileServiceError(this.signal.aborted ? "REQUEST_TIMEOUT" : "INTERNAL_ERROR");
    }
    if (this.signal.aborted) throw new ProfileServiceError("REQUEST_TIMEOUT");
    if (result.error) throw new ProfileServiceError(mapProfileRpcError(result.error));
    return result.data;
  }

  async bootstrap(): Promise<ProfileAccount> {
    return parseProfileAccount(await this.rpc("bootstrap_profile_identity_v019"));
  }

  async createOrResume(operationId: string): Promise<ProfileOperationResult> {
    return parseProfileOperationResult(await this.rpc("create_or_resume_profile_draft_v019", { p_operation_id: operationId }));
  }

  async currentDocument(): Promise<ProfileDocument> {
    return parseProfileDocument(await this.rpc("get_profile_document_v019", { p_profile_version_id: null }));
  }

  async knownDocument(profileVersionId: string): Promise<ProfileDocument> {
    return parseProfileDocument(await this.rpc("get_profile_document_v019", { p_profile_version_id: profileVersionId }));
  }

  async latestFrozen(): Promise<ProfileFrozenDiscovery> {
    return parseProfileFrozenDiscovery(await this.rpc("get_latest_frozen_profile_v025"));
  }

  async readiness(profileVersionId: string): Promise<ProfileReadiness> {
    return parseProfileReadiness(await this.rpc("get_profile_readiness_v019", { p_profile_version_id: profileVersionId }));
  }

  async taxonomy(profileVersionId: string | null): Promise<ProfileTaxonomyProjection> {
    return parseProfileTaxonomyProjection(await this.rpc("get_profile_taxonomy_projection_v022", { p_profile_version_id: profileVersionId }));
  }

  async taxonomyOptions(conceptKind: ProfileTaxonomyOptionKind): Promise<ProfileTaxonomyOptions> {
    return parseProfileTaxonomyOptions(await this.rpc("get_profile_taxonomy_options_v023", { p_concept_kind: conceptKind }));
  }

  async mutate(input: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number } & ProfileMutationCommand>): Promise<ProfileOperationResult> {
    return parseProfileOperationResult(await this.rpc("mutate_profile_draft_v019", {
      p_profile_version_id: input.profileVersionId,
      p_operation_id: input.operationId,
      p_expected_revision: input.expectedRevision,
      p_command: input.command,
      p_payload: input.payload,
    }));
  }

  async freeze(input: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }>): Promise<ProfileOperationResult> {
    return parseProfileOperationResult(await this.rpc("freeze_profile_draft_v019", {
      p_profile_version_id: input.profileVersionId,
      p_operation_id: input.operationId,
      p_expected_revision: input.expectedRevision,
    }));
  }

  async fork(input: Readonly<{ sourceProfileVersionId: string; operationId: string }>): Promise<ProfileOperationResult> {
    return parseProfileOperationResult(await this.rpc("fork_frozen_profile_to_draft_v020", {
      p_source_profile_version_id: input.sourceProfileVersionId,
      p_operation_id: input.operationId,
    }));
  }
}

export const createSupabaseProfileService: ProfileServiceFactory = async (signal) => {
  const supabase = await createClient({ customFetch: createDependencyFetch(signal) });
  return new SupabaseProfileService(supabase as unknown as ProfileSupabaseClient, signal);
};
