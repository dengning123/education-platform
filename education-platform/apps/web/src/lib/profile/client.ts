import { PROFILE_UUID_PATTERN } from "./contracts";
import { PROFILE_PUBLIC_ERROR_CATALOG, type PublicProfileErrorCode } from "./errors";

export type ProfileHttpSuccess<T> = Readonly<{ ok: true; data: T; requestId: string }>;
export type ProfileHttpFailure = Readonly<{ ok: false; error: PublicProfileErrorCode; requestId: string; message?: string }>;
export type ProfileHttpResult<T> = ProfileHttpSuccess<T> | ProfileHttpFailure;

type ProfileFetch = typeof fetch;

function isRequestId(value: unknown): value is string {
  return typeof value === "string" && PROFILE_UUID_PATTERN.test(value);
}

function closedFailure(value: unknown): ProfileHttpFailure | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const object = value as Record<string, unknown>;
  if (
    typeof object.error !== "string" ||
    !(object.error in PROFILE_PUBLIC_ERROR_CATALOG) ||
    !isRequestId(object.requestId)
  ) return null;
  return Object.freeze({
    ok: false,
    error: object.error as PublicProfileErrorCode,
    requestId: object.requestId,
    ...(typeof object.message === "string" ? { message: object.message } : {}),
  });
}

export async function postProfileRequest<T>(
  capability: string,
  body: unknown,
  options: Readonly<{ fetchImpl?: ProfileFetch; ambiguousRetries?: number }> = {},
): Promise<ProfileHttpResult<T>> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const serialized = JSON.stringify(body);
  const attempts = Math.max(1, 1 + (options.ambiguousRetries ?? 0));
  let lastRequestId = crypto.randomUUID();

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetchImpl(`/api/profile/${capability}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: serialized,
      });
      const value = await response.json() as unknown;
      if (value !== null && typeof value === "object" && !Array.isArray(value)) {
        const object = value as Record<string, unknown>;
        if (isRequestId(object.requestId)) lastRequestId = object.requestId;
        if (response.ok && "data" in object && isRequestId(object.requestId)) {
          return Object.freeze({ ok: true, data: object.data as T, requestId: object.requestId });
        }
      }
      const failure = closedFailure(value);
      if (failure && failure.error === "REQUEST_TIMEOUT" && attempt + 1 < attempts) continue;
      return failure ?? Object.freeze({ ok: false, error: "INTERNAL_ERROR", requestId: lastRequestId });
    } catch {
      if (attempt + 1 < attempts) continue;
      return Object.freeze({ ok: false, error: "INTERNAL_ERROR", requestId: lastRequestId });
    }
  }
  return Object.freeze({ ok: false, error: "INTERNAL_ERROR", requestId: lastRequestId });
}

export function newProfileOperationId(randomUUID: () => string = () => crypto.randomUUID()): string {
  const operationId = randomUUID();
  if (!PROFILE_UUID_PATTERN.test(operationId)) throw new TypeError("INVALID_OPERATION_ID_SOURCE");
  return operationId.toLowerCase();
}
