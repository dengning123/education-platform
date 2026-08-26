import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("../supabase/server", () => ({ createClient: vi.fn() }));

import { FIT_INTENT_DIMENSIONS } from "./contracts";
import { IntentServiceError } from "./errors";
import { createSupabaseIntentService } from "./service";
import { createClient } from "../supabase/server";

const id = (suffix: string) => `00000000-0000-4000-8000-${suffix.padStart(12, "0")}`;
const document = {
  schemaVersion: "FIT_INTENT_DOCUMENT_V027", intentSetId: id("1"), profileVersionId: id("2"), versionNumber: 1,
  status: "DRAFT", revision: 0, snapshotHash: null, taxonomyRelease: { releaseCode: "v0.1", releaseOrdinal: 1 },
  dimensions: FIT_INTENT_DIMENSIONS.map((dimension) => ({ dimension, state: "UNANSWERED" })), declarations: [], accessContext: null,
};

function client(data: unknown = document, error: unknown = null) {
  const builder = { abortSignal: vi.fn(async () => ({ data, error })), then: undefined };
  return {
    auth: { getUser: vi.fn(async () => ({ data: { user: { id: id("99") } }, error: null })) },
    rpc: vi.fn(() => builder), builder,
  };
}

async function serviceFor(mock: ReturnType<typeof client>) {
  vi.mocked(createClient).mockResolvedValue(mock as never);
  const service = await createSupabaseIntentService(new AbortController().signal);
  await service.authenticate();
  return service;
}

describe("session-scoped M027 Intent RPC service", () => {
  it("derives ownership from the current session and forwards only closed arguments", async () => {
    const mock = client();
    const service = await serviceFor(mock);
    await service.document(id("1"));
    expect(mock.rpc).toHaveBeenCalledWith("get_fit_intent_document_v027", { p_intent_set_id: id("1") });
    expect(JSON.stringify(mock.rpc.mock.calls)).not.toContain(id("99"));
  });

  it("preserves operationId, revision, command, and exact payload for database idempotency", async () => {
    const result = { schemaVersion: "FIT_INTENT_OPERATION_RESULT_V027", operation: "MUTATE", command: "DIMENSION_MARK_NOT_SUPPLIED", intentSetId: id("1"), revision: 1, resourceId: null, document: { ...document, revision: 1, dimensions: document.dimensions.map((entry) => entry.dimension === "ACADEMIC" ? { ...entry, state: "EXPLICIT_NOT_SUPPLIED" } : entry) } };
    const mock = client(result);
    const service = await serviceFor(mock);
    await service.mutate({ intentSetId: id("1"), operationId: id("3"), expectedRevision: 0, command: "DIMENSION_MARK_NOT_SUPPLIED", payload: { dimension: "ACADEMIC" } });
    expect(mock.rpc).toHaveBeenCalledWith("mutate_fit_intent_draft_v027", {
      p_intent_set_id: id("1"), p_operation_id: id("3"), p_expected_revision: 0,
      p_command: "DIMENSION_MARK_NOT_SUPPLIED", p_payload: { dimension: "ACADEMIC" },
    });
  });

  it("maps only closed database error identities", async () => {
    await expect((await serviceFor(client(null, { message: "FIT_INTENT_REVISION_CONFLICT", detail: "private" }))).document(id("1")))
      .rejects.toEqual(new IntentServiceError("INTENT_REVISION_CONFLICT"));
    await expect((await serviceFor(client(null, { message: "raw SQLSTATE 42501", hint: "secret" }))).document(id("1")))
      .rejects.toEqual(new IntentServiceError("INTERNAL_ERROR"));
  });
});
