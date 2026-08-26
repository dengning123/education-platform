import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("../supabase/server", () => ({ createClient: vi.fn() }));

import { FIT_DIMENSIONS, type FitConnectionRequest } from "./contracts";
import { EvaluationServiceError } from "./errors";
import { SupabaseEvaluationService, type EvaluationAuthClient } from "./service";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

const fitRequest: FitConnectionRequest = {
  profileVersionId: id("1"), intentSetId: id("2"), programVersionId: id("3"),
  completedEligibilityEvaluationId: id("4"), operationId: id("30"),
};

function fitBody() {
  return {
    evaluationId: id("5"), candidateInputFingerprint: "a".repeat(64), resultFingerprint: "b".repeat(64), schemaVersion: "fit-v0.1",
    dimensions: Object.fromEntries(FIT_DIMENSIONS.map((dimension) => [dimension, {
      dimension, methodRegistryId: id("10"), methodCode: `${dimension}_V01`, methodVersion: 1,
      assessment: "UNKNOWN", confidence: "LOW", evidenceCoverage: "INSUFFICIENT", inferenceCategory: "DETERMINISTIC",
      signals: [], reasons: [], limitingInputs: [], exactManifestRefs: [],
    }])),
  };
}

function eligibilityBody() {
  return {
    schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026",
    evalId: id("20"), profileId: id("1"), programId: id("3"),
    status: "UNKNOWN", rootTruth: "UNKNOWN", requirements: [],
    inputFingerprint: "c".repeat(64), resultFingerprint: "d".repeat(64),
  };
}

function userClient(token = "alice-session-jwt", authenticated = true): EvaluationAuthClient {
  return {
    auth: {
      getUser: vi.fn(async () => authenticated
        ? ({ data: { user: { id: id("90") } }, error: null })
        : ({ data: { user: null }, error: { message: "expired internal detail" } })),
      getSession: vi.fn(async () => ({ data: { session: { access_token: token } }, error: null })),
    },
    rpc: vi.fn(async () => ({ data: eligibilityBody(), error: null })),
  };
}

describe("Fit same-origin secure proxy service", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://127.0.0.1:54321");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "public-test-key");
  });

  afterEach(() => vi.unstubAllEnvs());

  it("assembles Eligibility through one session-scoped database RPC without a privileged key", async () => {
    const client = userClient();
    const service = new SupabaseEvaluationService(client, new AbortController().signal, vi.fn() as unknown as typeof fetch);
    await service.authenticate();
    const result = await service.eligibility({
      profileVersionId: id("1"), programVersionId: id("3"), operationId: id("30"),
    });
    expect(result.evalId).toBe(id("20"));
    expect(client.rpc).toHaveBeenCalledWith("assemble_eligibility_evaluation_v026", {
      p_profile_version_id: id("1"), p_program_version_id: id("3"), p_operation_id: id("30"),
    });
    expect(JSON.stringify(result)).not.toContain("alice-session-jwt");
  });

  it("maps only the closed Eligibility database error identity", async () => {
    const client = userClient();
    client.rpc = vi.fn(async () => ({
      data: null,
      error: { message: "ELIGIBILITY_RULESET_NOT_FOUND", detail: "private table", hint: "do not leak" },
    }));
    const service = new SupabaseEvaluationService(client, new AbortController().signal, vi.fn() as unknown as typeof fetch);
    await service.authenticate();
    await expect(service.eligibility({
      profileVersionId: id("1"), programVersionId: id("3"), operationId: id("30"),
    })).rejects.toEqual(new EvaluationServiceError("ELIGIBILITY_RULESET_NOT_FOUND"));

    client.rpc = vi.fn(async () => ({ data: null, error: { message: "raw SQLSTATE and constraint detail" } }));
    await expect(service.eligibility({
      profileVersionId: id("1"), programVersionId: id("3"), operationId: id("30"),
    })).rejects.toEqual(new EvaluationServiceError("INTERNAL_ERROR"));
  });

  it("sends only high-level Fit identities and the current session JWT to the product-aware Edge", async () => {
    const dependencyFetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      void input;
      void init;
      return new Response(JSON.stringify(fitBody()), { status: 201, headers: { "content-type": "application/json" } });
    });
    const service = new SupabaseEvaluationService(userClient(), new AbortController().signal, dependencyFetch);
    await service.authenticate();
    const result = await service.fit(fitRequest);
    expect(result.fitEvaluationId).toBe(id("5"));
    expect(Object.keys(result.dimensions)).toEqual(FIT_DIMENSIONS);
    expect(dependencyFetch).toHaveBeenCalledOnce();
    const [url, init] = dependencyFetch.mock.calls[0];
    expect(String(url)).toContain("/functions/v1/fit-evaluate");
    expect(new Headers(init?.headers).get("authorization")).toBe("Bearer alice-session-jwt");
    expect(JSON.parse(String(init?.body))).toEqual({
      schemaVersion: "FIT_PRODUCT_EVALUATION_REQUEST_V027",
      profileVersionId: id("1"), intentSetId: id("2"), programVersionId: id("3"),
      eligibilityContextEvaluationId: id("4"),
    });
    expect(String(init?.body)).not.toContain(id("30"));
    expect(JSON.stringify(result)).not.toContain("alice-session-jwt");
  });

  it("does not expose a raw Fit dependency error", async () => {
    const dependencyFetch = vi.fn(async () => new Response(JSON.stringify({
      error: "FIT_EVALUATION_REJECTED", detail: "internal PostgREST detail", hint: "private SQL hint",
    }), { status: 400, headers: { "content-type": "application/json" } }));
    const service = new SupabaseEvaluationService(userClient(), new AbortController().signal, dependencyFetch);
    await service.authenticate();
    await expect(service.fit(fitRequest)).rejects.toEqual(new EvaluationServiceError("INVALID_REQUEST"));
  });

  it("requires a validated session before any Fit dependency call", async () => {
    const client = userClient("expired-session", false);
    const dependencyFetch = vi.fn();
    const service = new SupabaseEvaluationService(client, new AbortController().signal, dependencyFetch as unknown as typeof fetch);
    await expect(service.authenticate()).rejects.toEqual(new EvaluationServiceError("AUTH_REQUIRED"));
    expect(dependencyFetch).not.toHaveBeenCalled();
  });
});
