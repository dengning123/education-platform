import { describe, expect, it } from "vitest";

import type {
  ProfileAccount,
  ProfileDocument,
  ProfileFrozenDiscovery,
  ProfileMutationCommand,
  ProfileOperationResult,
  ProfileReadiness,
  ProfileTaxonomyOptions,
  ProfileTaxonomyProjection,
} from "./contracts";
import { ProfileServiceError } from "./errors";
import { createProfileRouter } from "./http-boundary";
import type { ProfileService, ProfileServiceFactory } from "./service";

const requestId = "00000000-0000-4000-8000-000000000101";
const profileId = "00000000-0000-4000-8000-000000000102";
const operationId = "00000000-0000-4000-8000-000000000103";

const readiness: ProfileReadiness = {
  schemaVersion: "PROFILE_READINESS_V019",
  freezeReady: false,
  requiredScopeCount: 8,
  declaredRequiredScopeCount: 0,
  missingDeclarations: [],
  declarations: [],
  mappingReadiness: [],
};

const document: ProfileDocument = {
  schemaVersion: "PROFILE_DOCUMENT_V019",
  profileVersionId: profileId,
  versionNumber: 1,
  status: "DRAFT",
  revision: 0,
  snapshotHash: null,
  frozenAt: null,
  readiness,
  evidenceItems: [], degrees: [], courses: [], testScores: [], experiences: [], skills: [], experienceSkills: [], goals: [], preferences: [], mappings: [],
};

const taxonomy: ProfileTaxonomyProjection = {
  schemaVersion: "PROFILE_TAXONOMY_PROJECTION_V022",
  releaseCode: "v0.1",
  releaseOrdinal: 1,
  concepts: [],
};
const taxonomyOptions: ProfileTaxonomyOptions = {
  schemaVersion: "PROFILE_TAXONOMY_OPTIONS_V023",
  releaseCode: "v0.1",
  releaseOrdinal: 1,
  conceptKind: "ASSESSMENT",
  options: [{
    conceptId: "10000000-0000-0000-0000-000000000071",
    canonicalKey: "ASSESSMENT.GRE",
    displayName: "GRE",
  }],
};

class MockProfileService implements ProfileService {
  authenticated = true;
  calls: Array<Readonly<{ method: string; input?: unknown }>> = [];
  error: ProfileServiceError | null = null;
  revision = 0;
  operations = new Map<string, { fingerprint: string; result: ProfileOperationResult }>();

  async authenticate() {
    if (!this.authenticated) throw new ProfileServiceError("AUTH_REQUIRED");
  }

  private fail() {
    if (this.error) throw this.error;
  }

  async bootstrap(): Promise<ProfileAccount> {
    this.fail();
    this.calls.push({ method: "bootstrap" });
    return { schemaVersion: "PROFILE_ACCOUNT_V019", accountState: "ACTIVE", hasCurrentDraft: false };
  }

  async createOrResume(input: string): Promise<ProfileOperationResult> {
    this.fail();
    this.calls.push({ method: "createOrResume", input });
    return { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "CREATE_OR_RESUME", profileVersionId: profileId, versionNumber: 1, status: "DRAFT", revision: this.revision };
  }

  async currentDocument(): Promise<ProfileDocument> {
    this.fail();
    this.calls.push({ method: "currentDocument" });
    return { ...document, revision: this.revision };
  }

  async knownDocument(input: string): Promise<ProfileDocument> {
    this.fail();
    this.calls.push({ method: "knownDocument", input });
    return { ...document, profileVersionId: input, status: "FROZEN", snapshotHash: "a".repeat(64), frozenAt: "2026-08-25T12:00:00Z" };
  }

  async latestFrozen(): Promise<ProfileFrozenDiscovery> {
    this.fail();
    this.calls.push({ method: "latestFrozen" });
    return {
      schemaVersion: "PROFILE_FROZEN_DISCOVERY_V025",
      profileVersionId: profileId,
      versionNumber: 1,
      status: "FROZEN",
      frozenAt: "2026-08-25T12:00:00Z",
    };
  }

  async readiness(input: string): Promise<ProfileReadiness> {
    this.fail();
    this.calls.push({ method: "readiness", input });
    return readiness;
  }

  async taxonomy(input: string | null): Promise<ProfileTaxonomyProjection> {
    this.fail();
    this.calls.push({ method: "taxonomy", input });
    return taxonomy;
  }

  async taxonomyOptions(input: "ASSESSMENT" | "SKILL"): Promise<ProfileTaxonomyOptions> {
    this.fail();
    this.calls.push({ method: "taxonomyOptions", input });
    return { ...taxonomyOptions, conceptKind: input };
  }

  async mutate(input: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number } & ProfileMutationCommand>): Promise<ProfileOperationResult> {
    this.fail();
    this.calls.push({ method: "mutate", input });
    const fingerprint = JSON.stringify(input);
    const stored = this.operations.get(input.operationId);
    if (stored) {
      if (stored.fingerprint !== fingerprint) throw new ProfileServiceError("PROFILE_OPERATION_CONFLICT");
      return stored.result;
    }
    if (input.expectedRevision !== this.revision) throw new ProfileServiceError("PROFILE_REVISION_CONFLICT");
    this.revision += 1;
    const result: ProfileOperationResult = {
      schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "MUTATE", command: input.command,
      profileVersionId: input.profileVersionId, revision: this.revision, resourceId: null, resourceKey: null,
    };
    this.operations.set(input.operationId, { fingerprint, result });
    return result;
  }

  async freeze(input: Readonly<{ profileVersionId: string; operationId: string; expectedRevision: number }>): Promise<ProfileOperationResult> {
    this.fail();
    this.calls.push({ method: "freeze", input });
    return { schemaVersion: "PROFILE_OPERATION_RESULT_V019", operation: "FREEZE", profileVersionId: input.profileVersionId, status: "FROZEN", revision: input.expectedRevision + 1, document };
  }

  async fork(input: Readonly<{ sourceProfileVersionId: string; operationId: string }>): Promise<ProfileOperationResult> {
    this.fail();
    this.calls.push({ method: "fork", input });
    return { schemaVersion: "PROFILE_OPERATION_RESULT_V020", operation: "FORK_FROZEN", sourceProfileVersionId: input.sourceProfileVersionId, profileVersionId: profileId, versionNumber: 2, status: "DRAFT", revision: 0 };
  }
}

function request(body: BodyInit = "{}", options: Readonly<{ method?: string; contentType?: string; origin?: string; headers?: Record<string, string> }> = {}) {
  return new Request("http://app.test/api/profile/mutate", {
    method: options.method ?? "POST",
    headers: {
      "content-type": options.contentType ?? "application/json",
      ...(options.origin ? { origin: options.origin } : {}),
      ...options.headers,
    },
    body: options.method === "GET" || options.method === "HEAD" ? undefined : body,
  });
}

function context(capability: string) {
  return { params: Promise.resolve({ capability }) };
}

function router(service: MockProfileService, options: Readonly<{ logs?: string[]; deadline?: number }> = {}) {
  const createService: ProfileServiceFactory = async () => service;
  return createProfileRouter({
    createService,
    randomUUID: () => requestId,
    log: (event) => options.logs?.push(event),
    requestDeadlineMs: options.deadline,
  });
}

async function json(response: Response): Promise<Record<string, unknown>> {
  return response.json() as Promise<Record<string, unknown>>;
}

describe("Profile HTTP boundary", () => {
  it("returns one server request ID in the header, body, and privacy-safe event", async () => {
    const service = new MockProfileService();
    const logs: string[] = [];
    const response = await router(service, { logs })(request("{}", { headers: { "x-request-id": "attacker-id" } }), context("bootstrap"));
    expect(response.status).toBe(200);
    expect(response.headers.get("x-request-id")).toBe(requestId);
    expect(await json(response)).toMatchObject({ requestId, data: { schemaVersion: "PROFILE_ACCOUNT_V019" } });
    expect(logs).toHaveLength(1);
    expect(JSON.parse(logs[0])).toEqual(expect.objectContaining({ requestId, route: "PROFILE_BOOTSTRAP", status: 200, errorCode: null }));
    expect(logs[0]).not.toContain("attacker-id");
  });

  it("normalizes anonymous and expired sessions before capability execution", async () => {
    const service = new MockProfileService();
    service.authenticated = false;
    const response = await router(service)(request("not-json", { contentType: "text/plain" }), context("bootstrap"));
    expect(response.status).toBe(401);
    expect(await json(response)).toEqual({ error: "AUTH_REQUIRED", requestId, message: "Sign in to continue." });
    expect(service.calls).toHaveLength(0);
  });

  it.each([
    ["unsupported content type", request("{}", { contentType: "text/plain" }), "bootstrap", 415, "UNSUPPORTED_MEDIA_TYPE"],
    ["malformed JSON", request("{"), "bootstrap", 400, "INVALID_JSON"],
    ["unknown capability", request("{}"), "history", 404, "RESOURCE_NOT_FOUND"],
    ["unsupported method", request(undefined, { method: "GET" }), "bootstrap", 405, "METHOD_NOT_ALLOWED"],
    ["cross-origin request", request("{}", { origin: "https://attacker.test" }), "bootstrap", 403, "ACCESS_DENIED"],
  ])("closes %s", async (_name, input, capability, status, code) => {
    const response = await router(new MockProfileService())(input as Request, context(capability as string));
    expect(response.status).toBe(status);
    expect(await json(response)).toMatchObject({ error: code, requestId });
  });

  it("rejects oversized bodies before JSON parsing", async () => {
    const response = await router(new MockProfileService())(request(JSON.stringify({ value: "x".repeat(70_000) })), context("bootstrap"));
    expect(response.status).toBe(413);
    expect(await json(response)).toMatchObject({ error: "PAYLOAD_TOO_LARGE" });
  });

  it("does not return raw PostgREST message, detail, hint, SQLSTATE, stack, or cause", async () => {
    const service = new MockProfileService();
    service.error = new ProfileServiceError("INTERNAL_ERROR");
    const logs: string[] = [];
    const response = await router(service, { logs })(request("{}"), context("document"));
    const serialized = JSON.stringify(await json(response));
    expect(response.status).toBe(500);
    for (const leaked of ["relation private.student", "detail", "hint", "42P01", "stack", "cause"]) {
      expect(serialized).not.toContain(leaked);
      expect(logs.join("\n")).not.toContain(leaked);
    }
  });

  it("advances revision once, exactly replays, and refuses changed payload or stale revision", async () => {
    const service = new MockProfileService();
    const handler = router(service);
    const base = { profileVersionId: profileId, operationId, expectedRevision: 0, command: "GOAL_CREATE", payload: { goalType: "OTHER", goalText: "Graduate study", priority: 1 } };
    const first = await handler(request(JSON.stringify(base)), context("mutate"));
    const replay = await handler(request(JSON.stringify(base)), context("mutate"));
    const changed = await handler(request(JSON.stringify({ ...base, payload: { ...base.payload, goalText: "Changed" } })), context("mutate"));
    const stale = await handler(request(JSON.stringify({ ...base, operationId: "00000000-0000-4000-8000-000000000104" })), context("mutate"));
    expect(await json(first)).toMatchObject({ data: { revision: 1 } });
    expect(await json(replay)).toMatchObject({ data: { revision: 1 } });
    expect(changed.status).toBe(409);
    expect(await json(changed)).toMatchObject({ error: "PROFILE_OPERATION_CONFLICT" });
    expect(stale.status).toBe(409);
    expect(await json(stale)).toMatchObject({ error: "PROFILE_REVISION_CONFLICT" });
    expect(service.revision).toBe(1);
  });

  it("passes only the closed freeze and known-source fork shapes", async () => {
    const service = new MockProfileService();
    const handler = router(service);
    await handler(request(JSON.stringify({ profileVersionId: profileId, operationId, expectedRevision: 2 })), context("freeze"));
    await handler(request(JSON.stringify({ sourceProfileVersionId: profileId, operationId })), context("fork"));
    expect(service.calls).toContainEqual({ method: "freeze", input: { profileVersionId: profileId, operationId, expectedRevision: 2 } });
    expect(service.calls).toContainEqual({ method: "fork", input: { sourceProfileVersionId: profileId, operationId } });
    const studentIdAttempt = await handler(request(JSON.stringify({ sourceProfileVersionId: profileId, operationId, studentId: profileId })), context("fork"));
    expect(studentIdAttempt.status).toBe(422);
  });

  it("passes only closed latest-frozen and known-document requests", async () => {
    const service = new MockProfileService();
    const handler = router(service);
    const latest = await handler(request("{}"), context("latest-frozen"));
    const known = await handler(request(JSON.stringify({ profileVersionId: profileId })), context("known-document"));
    const latestOwnership = await handler(request(JSON.stringify({ studentId: profileId })), context("latest-frozen"));
    const knownOwnership = await handler(request(JSON.stringify({ profileVersionId: profileId, studentId: profileId })), context("known-document"));
    const knownEnumeration = await handler(request(JSON.stringify({ profileVersionIds: [profileId] })), context("known-document"));
    expect(latest.status).toBe(200);
    expect(known.status).toBe(200);
    expect(service.calls).toContainEqual({ method: "latestFrozen" });
    expect(service.calls).toContainEqual({ method: "knownDocument", input: profileId });
    expect(latestOwnership.status).toBe(422);
    expect(knownOwnership.status).toBe(422);
    expect(knownEnumeration.status).toBe(422);
  });

  it("accepts only the closed projection and bounded-option taxonomy operations", async () => {
    const service = new MockProfileService();
    const handler = router(service);
    const current = await handler(request("{}"), context("taxonomy"));
    const explicit = await handler(request(JSON.stringify({ profileVersionId: profileId })), context("taxonomy"));
    const namedProjection = await handler(request(JSON.stringify({ operation: "projection", profileVersionId: profileId })), context("taxonomy"));
    const assessmentOptions = await handler(request(JSON.stringify({ operation: "options", conceptKind: "ASSESSMENT" })), context("taxonomy"));
    const skillOptions = await handler(request(JSON.stringify({ operation: "options", conceptKind: "SKILL" })), context("taxonomy"));
    const enumeration = await handler(request(JSON.stringify({ profileVersionId: profileId, conceptIds: [operationId] })), context("taxonomy"));
    const ownership = await handler(request(JSON.stringify({ studentId: profileId })), context("taxonomy"));
    const arbitraryKind = await handler(request(JSON.stringify({ operation: "options", conceptKind: "FIELD" })), context("taxonomy"));
    const optionsOwnership = await handler(request(JSON.stringify({ operation: "options", conceptKind: "SKILL", studentId: profileId })), context("taxonomy"));
    expect(current.status).toBe(200);
    expect(explicit.status).toBe(200);
    expect(namedProjection.status).toBe(200);
    expect(assessmentOptions.status).toBe(200);
    expect(skillOptions.status).toBe(200);
    expect(service.calls).toContainEqual({ method: "taxonomy", input: null });
    expect(service.calls).toContainEqual({ method: "taxonomy", input: profileId });
    expect(service.calls).toContainEqual({ method: "taxonomyOptions", input: "ASSESSMENT" });
    expect(service.calls).toContainEqual({ method: "taxonomyOptions", input: "SKILL" });
    expect(enumeration.status).toBe(422);
    expect(ownership.status).toBe(422);
    expect(arbitraryKind.status).toBe(422);
    expect(optionsOwnership.status).toBe(422);
  });

  it("maps active-draft and cross-owner/not-found service outcomes without leakage", async () => {
    const service = new MockProfileService();
    const handler = router(service);
    service.error = new ProfileServiceError("PROFILE_ACTIVE_DRAFT_EXISTS");
    const active = await handler(request(JSON.stringify({ sourceProfileVersionId: profileId, operationId })), context("fork"));
    expect(active.status).toBe(409);
    service.error = new ProfileServiceError("RESOURCE_NOT_FOUND");
    const unrelated = await handler(request(JSON.stringify({ profileVersionId: profileId })), context("readiness"));
    expect(unrelated.status).toBe(404);
    expect(await json(unrelated)).toMatchObject({ error: "RESOURCE_NOT_FOUND" });
  });

  it("bounds the whole request deadline", async () => {
    const createService: ProfileServiceFactory = async (signal) => {
      const service = new MockProfileService();
      service.authenticate = async () => {
        await new Promise<void>((resolve) => signal.addEventListener("abort", () => resolve(), { once: true }));
        throw new ProfileServiceError("REQUEST_TIMEOUT");
      };
      return service;
    };
    const handler = createProfileRouter({ createService, randomUUID: () => requestId, requestDeadlineMs: 5, log: () => undefined });
    const response = await handler(request("{}"), context("bootstrap"));
    expect(response.status).toBe(504);
    expect(await json(response)).toMatchObject({ error: "REQUEST_TIMEOUT", requestId });
  });

  it("logs no UUIDs except requestId and no request/profile/free-text values", async () => {
    const logs: string[] = [];
    const body = { profileVersionId: profileId, operationId, expectedRevision: 0, command: "GOAL_CREATE", payload: { goalType: "OTHER", goalText: "student@example.test private goal", priority: 1 } };
    await router(new MockProfileService(), { logs })(request(JSON.stringify(body)), context("mutate"));
    expect(logs.join("\n")).not.toContain(profileId);
    expect(logs.join("\n")).not.toContain(operationId);
    expect(logs.join("\n")).not.toContain("student@example.test");
    expect(logs.join("\n")).not.toContain("private goal");
    expect(logs.join("\n")).toContain(requestId);
  });
});
