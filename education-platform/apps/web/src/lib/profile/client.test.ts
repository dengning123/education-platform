import { describe, expect, it } from "vitest";

import { newProfileOperationId, postProfileRequest } from "./client";

const operationId = "00000000-0000-4000-8000-000000000040";
const requestId = "00000000-0000-4000-8000-000000000041";

describe("Profile browser request client", () => {
  it("generates a validated operation ID", () => {
    expect(newProfileOperationId(() => operationId)).toBe(operationId);
    expect(() => newProfileOperationId(() => "attacker-value")).toThrow("INVALID_OPERATION_ID_SOURCE");
  });

  it("reuses the exact serialized body and operation ID after an ambiguous timeout", async () => {
    const bodies: string[] = [];
    const fetchImpl: typeof fetch = async (_input, init) => {
      bodies.push(String(init?.body));
      if (bodies.length === 1) return Response.json({ error: "REQUEST_TIMEOUT", requestId }, { status: 504 });
      return Response.json({ data: { revision: 2 }, requestId });
    };
    const body = { profileVersionId: operationId, operationId, expectedRevision: 1, command: "GOAL_DELETE", payload: { goalId: operationId } };
    const result = await postProfileRequest<{ revision: number }>("mutate", body, { fetchImpl, ambiguousRetries: 1 });
    expect(result).toMatchObject({ ok: true, data: { revision: 2 } });
    expect(bodies).toHaveLength(2);
    expect(bodies[1]).toBe(bodies[0]);
    expect(JSON.parse(bodies[1]).operationId).toBe(operationId);
  });

  it("never returns an unrecognized dependency failure as a public code", async () => {
    const fetchImpl: typeof fetch = async () => Response.json({ error: "raw SQLSTATE 42P01", requestId, message: "private relation missing" }, { status: 500 });
    const result = await postProfileRequest("document", {}, { fetchImpl });
    expect(result).toEqual({ ok: false, error: "INTERNAL_ERROR", requestId });
  });
});
