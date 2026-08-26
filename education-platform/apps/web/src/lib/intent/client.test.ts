import { describe, expect, it, vi } from "vitest";

import { newIntentOperationId, postIntentRequest } from "./client";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;

describe("M027 Intent browser client", () => {
  it("reuses the exact serialized mutation for an ambiguous timeout retry", async () => {
    const bodies: string[] = [];
    const fetchImpl = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(String(init?.body));
      return bodies.length === 1
        ? new Response(JSON.stringify({ error: "REQUEST_TIMEOUT", requestId: id("9") }), { status: 504 })
        : new Response(JSON.stringify({ data: { revision: 2 }, requestId: id("8") }), { status: 200 });
    });
    const request = { intentSetId: id("1"), operationId: id("2"), expectedRevision: 1, command: "DIMENSION_MARK_NOT_SUPPLIED", payload: { dimension: "ACADEMIC" } };
    expect((await postIntentRequest("mutate", request, { fetchImpl, ambiguousRetries: 1 })).ok).toBe(true);
    expect(bodies).toEqual([JSON.stringify(request), JSON.stringify(request)]);
  });

  it("fails closed on malformed responses and operation ID sources", async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ error: "raw SQL", detail: "secret" }), { status: 500 }));
    expect(await postIntentRequest("create", {}, { fetchImpl })).toEqual(expect.objectContaining({ ok: false, error: "INTERNAL_ERROR" }));
    expect(() => newIntentOperationId(() => "not-a-uuid")).toThrow(/INVALID_OPERATION_ID_SOURCE/);
  });
});
