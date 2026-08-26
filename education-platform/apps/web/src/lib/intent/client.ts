import { INTENT_PUBLIC_ERROR_CATALOG, type PublicIntentErrorCode } from "./errors";

export type IntentHttpResult<T> =
  | Readonly<{ ok: true; data: T; requestId: string }>
  | Readonly<{ ok: false; error: PublicIntentErrorCode; requestId: string; message?: string }>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function postIntentRequest<T>(
  capability: string,
  request: unknown,
  options: Readonly<{ fetchImpl?: typeof fetch; ambiguousRetries?: number }> = {},
): Promise<IntentHttpResult<T>> {
  const serialized = JSON.stringify(request);
  const attempts = Math.max(1, 1 + (options.ambiguousRetries ?? 0));
  let lastRequestId = crypto.randomUUID();
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await (options.fetchImpl ?? fetch)(`/api/intent/${capability}`, {
        method: "POST", headers: { "content-type": "application/json" }, body: serialized,
      });
      const value = await response.json() as Record<string, unknown>;
      if (UUID.test(String(value.requestId))) lastRequestId = String(value.requestId);
      if (response.ok && "data" in value && UUID.test(lastRequestId)) return Object.freeze({ ok: true, data: value.data as T, requestId: lastRequestId });
      if (typeof value.error === "string" && value.error in INTENT_PUBLIC_ERROR_CATALOG && UUID.test(lastRequestId)) {
        const failure = Object.freeze({ ok: false as const, error: value.error as PublicIntentErrorCode, requestId: lastRequestId, ...(typeof value.message === "string" ? { message: value.message } : {}) });
        if (failure.error === "REQUEST_TIMEOUT" && attempt + 1 < attempts) continue;
        return failure;
      }
    } catch { if (attempt + 1 < attempts) continue; }
    return Object.freeze({ ok: false, error: "INTERNAL_ERROR", requestId: lastRequestId });
  }
  return Object.freeze({ ok: false, error: "INTERNAL_ERROR", requestId: lastRequestId });
}

export function newIntentOperationId(randomUUID: () => string = () => crypto.randomUUID()): string {
  const value = randomUUID();
  if (!UUID.test(value)) throw new TypeError("INVALID_OPERATION_ID_SOURCE");
  return value.toLowerCase();
}
