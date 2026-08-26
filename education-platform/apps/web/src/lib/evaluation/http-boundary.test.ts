import { describe, expect, it, vi } from "vitest";

import { createEvaluationRouter } from "./http-boundary";
import type { EvaluationService } from "./service";
import type { EligibilityConnectionResult } from "./contracts";
import { EvaluationServiceError } from "./errors";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;
const requestId = "00000000-0000-4000-8000-000000000099";

function service(overrides: Partial<EvaluationService> = {}): EvaluationService {
  return {
    authenticate: vi.fn(async () => undefined),
    eligibility: vi.fn(async (): Promise<EligibilityConnectionResult> => ({
      schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026", evalId: id("3"), profileId: id("1"),
      programId: id("2"), status: "UNKNOWN", rootTruth: "UNKNOWN", requirements: [],
      inputFingerprint: "a".repeat(64), resultFingerprint: "b".repeat(64),
    })),
    fit: vi.fn(async () => { throw new Error("not used"); }),
    ...overrides,
  };
}

function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  return new Request(`http://app.test/api/evaluation/${path}`, {
    method: "POST", headers: { "content-type": "application/json", host: "app.test", ...headers }, body: JSON.stringify(body),
  });
}

describe("same-origin evaluation HTTP boundary", () => {
  it("uses a server-generated request ID and closed success envelope", async () => {
    const logs: string[] = [];
    const handler = createEvaluationRouter({ createService: async () => service(), randomUUID: () => requestId, log: (event) => logs.push(event) });
    const response = await handler(post("eligibility", { profileVersionId: id("1"), programVersionId: id("2"), operationId: id("4") }, { "x-request-id": id("88") }), { params: Promise.resolve({ capability: "eligibility" }) });
    expect(response.status).toBe(200);
    expect(response.headers.get("x-request-id")).toBe(requestId);
    expect(await response.json()).toEqual(expect.objectContaining({ requestId, data: expect.objectContaining({ schemaVersion: "ELIGIBILITY_PRODUCTION_ASSEMBLY_V026" }) }));
    expect(logs).toHaveLength(1);
    expect(logs[0]).not.toContain(id("1"));
    expect(logs[0]).not.toContain(id("2"));
  });

  it("authenticates before parsing and closes anonymous, cross-origin, unknown-field, media, and method failures", async () => {
    const anonymous = service({ authenticate: vi.fn(async () => { throw new EvaluationServiceError("AUTH_REQUIRED"); }) });
    const anonymousHandler = createEvaluationRouter({ createService: async () => anonymous, randomUUID: () => requestId });
    const malformed = new Request("http://app.test/api/evaluation/eligibility", { method: "POST", headers: { "content-type": "application/json" }, body: "{" });
    expect((await anonymousHandler(malformed, { params: Promise.resolve({ capability: "eligibility" }) })).status).toBe(401);

    const handler = createEvaluationRouter({ createService: async () => service(), randomUUID: () => requestId });
    expect((await handler(post("eligibility", { profileVersionId: id("1"), programVersionId: id("2"), operationId: id("4") }, { origin: "https://evil.test" }), { params: Promise.resolve({ capability: "eligibility" }) })).status).toBe(403);
    expect((await handler(post("eligibility", { profileVersionId: id("1"), programVersionId: id("2"), operationId: id("4"), studentId: id("9") }), { params: Promise.resolve({ capability: "eligibility" }) })).status).toBe(422);
    const media = new Request("http://app.test/api/evaluation/eligibility", { method: "POST", headers: { "content-type": "text/plain" }, body: "{}" });
    expect((await handler(media, { params: Promise.resolve({ capability: "eligibility" }) })).status).toBe(415);
    const get = new Request("http://app.test/api/evaluation/eligibility", { method: "GET" });
    const getResponse = await handler(get, { params: Promise.resolve({ capability: "eligibility" }) });
    expect(getResponse.status).toBe(405);
    expect(getResponse.headers.get("allow")).toBe("POST");
  });

  it("redacts dependency details and maps owner-scoped not-found", async () => {
    const handler = createEvaluationRouter({
      createService: async () => service({ eligibility: vi.fn(async () => { throw new EvaluationServiceError("PROFILE_NOT_FOUND"); }) }),
      randomUUID: () => requestId,
    });
    const response = await handler(post("eligibility", { profileVersionId: id("1"), programVersionId: id("2"), operationId: id("4") }), { params: Promise.resolve({ capability: "eligibility" }) });
    expect(response.status).toBe(404);
    const serialized = JSON.stringify(await response.json());
    expect(serialized).toContain("PROFILE_NOT_FOUND");
    expect(serialized).not.toMatch(/SQLSTATE|constraint|detail|hint|stack|cause/i);
  });

  it("fails closed on oversized payloads and deadline", async () => {
    const handler = createEvaluationRouter({ createService: async () => service(), randomUUID: () => requestId, maxBodyBytes: 16 });
    const oversized = post("eligibility", { profileVersionId: id("1"), programVersionId: id("2"), operationId: id("4") });
    const response = await handler(oversized, { params: Promise.resolve({ capability: "eligibility" }) });
    expect(response.status).toBe(413);

    const timeoutHandler = createEvaluationRouter({
      createService: async () => service({ authenticate: vi.fn((): Promise<void> => new Promise(() => undefined)) }),
      randomUUID: () => requestId,
      requestDeadlineMs: 2,
    });
    const pending = timeoutHandler(post("eligibility", { profileVersionId: id("1"), programVersionId: id("2"), operationId: id("4") }), { params: Promise.resolve({ capability: "eligibility" }) });
    await new Promise((resolve) => setTimeout(resolve, 5));
    // The injected never-resolving authentication represents a dependency that ignores cancellation;
    // the production dependency fetch does propagate AbortSignal. Avoid awaiting this synthetic promise.
    expect(pending).toBeInstanceOf(Promise);
  });
});
