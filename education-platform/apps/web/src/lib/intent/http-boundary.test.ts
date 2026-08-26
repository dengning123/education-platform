import { describe, expect, it, vi } from "vitest";

import { createIntentRouter } from "./http-boundary";
import { IntentServiceError } from "./errors";
import type { IntentService } from "./service";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;
const requestId = "00000000-0000-4000-8000-000000000099";

function service(overrides: Partial<IntentService> = {}): IntentService {
  return {
    authenticate: vi.fn(async () => undefined), discover: vi.fn(), create: vi.fn(async () => ({
      schemaVersion: "FIT_INTENT_OPERATION_RESULT_V027" as const, operation: "CREATE_OR_RESUME" as const,
      intentSetId: id("1"), profileVersionId: id("2"), versionNumber: 1, status: "DRAFT" as const, revision: 0,
    })), document: vi.fn(), mutate: vi.fn(), freeze: vi.fn(), taxonomy: vi.fn(), accessOptions: vi.fn(), ...overrides,
  };
}

function post(capability: string, value: unknown, extra: Record<string, string> = {}) {
  return new Request(`http://app.test/api/intent/${capability}`, {
    method: "POST", headers: { host: "app.test", "content-type": "application/json", ...extra }, body: JSON.stringify(value),
  });
}

describe("same-origin M027 Intent HTTP boundary", () => {
  it("uses a server requestId and emits identifier-free operational metadata", async () => {
    const logs: string[] = [];
    const handler = createIntentRouter({ createService: async () => service(), randomUUID: () => requestId, log: (event) => logs.push(event) });
    const result = await handler(post("create", { profileVersionId: id("2"), operationId: id("3") }, { "x-request-id": id("88") }), { params: Promise.resolve({ capability: "create" }) });
    expect(result.status).toBe(200);
    expect(result.headers.get("x-request-id")).toBe(requestId);
    expect((await result.json()).requestId).toBe(requestId);
    expect(logs).toHaveLength(1);
    for (const secret of [id("2"), id("3"), "studentId", "authSubject", "cookie", "authorization"]) expect(logs[0]).not.toContain(secret);
  });

  it("authenticates first and fails closed for cross-origin, unknown fields, media, malformed JSON, and unknown routes", async () => {
    const anonymous = createIntentRouter({ createService: async () => service({ authenticate: vi.fn(async () => { throw new IntentServiceError("AUTH_REQUIRED"); }) }), randomUUID: () => requestId });
    const malformed = new Request("http://app.test/api/intent/create", { method: "POST", headers: { "content-type": "application/json" }, body: "{" });
    expect((await anonymous(malformed, { params: Promise.resolve({ capability: "create" }) })).status).toBe(401);
    const handler = createIntentRouter({ createService: async () => service(), randomUUID: () => requestId });
    expect((await handler(post("create", { profileVersionId: id("2"), operationId: id("3") }, { origin: "https://evil.test" }), { params: Promise.resolve({ capability: "create" }) })).status).toBe(403);
    expect((await handler(post("create", { profileVersionId: id("2"), operationId: id("3"), studentId: id("4") }), { params: Promise.resolve({ capability: "create" }) })).status).toBe(422);
    expect((await handler(post("unknown", {}), { params: Promise.resolve({ capability: "unknown" }) })).status).toBe(404);
    const media = new Request("http://app.test/api/intent/create", { method: "POST", headers: { "content-type": "text/plain" }, body: "{}" });
    expect((await handler(media, { params: Promise.resolve({ capability: "create" }) })).status).toBe(415);
  });

  it("does not leak PostgREST details through closed conflicts", async () => {
    const handler = createIntentRouter({ createService: async () => service({ mutate: vi.fn(async () => { throw new IntentServiceError("INTENT_REVISION_CONFLICT"); }) }), randomUUID: () => requestId });
    const result = await handler(post("mutate", { intentSetId: id("1"), operationId: id("2"), expectedRevision: 0, command: "DIMENSION_MARK_NOT_SUPPLIED", payload: { dimension: "ACADEMIC" } }), { params: Promise.resolve({ capability: "mutate" }) });
    expect(result.status).toBe(409);
    expect(JSON.stringify(await result.json())).not.toMatch(/SQLSTATE|detail|hint|constraint|stack|cause/i);
  });

  it("rejects declared and streamed oversized bodies", async () => {
    const handler = createIntentRouter({ createService: async () => service(), randomUUID: () => requestId, maxBodyBytes: 16 });
    expect((await handler(post("create", { profileVersionId: id("2"), operationId: id("3") }), { params: Promise.resolve({ capability: "create" }) })).status).toBe(413);
  });
});
