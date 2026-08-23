import {
  parseCreateDraftRequest,
  parseEmptyRequest,
  parseForkRequest,
  parseMutationRequest,
  parseProfileIdRequest,
  parseRevisionRequest,
  ProfileContractError,
} from "./contracts";
import {
  ProfileServiceError,
  publicProfileError,
  type PublicProfileErrorCode,
} from "./errors";
import type { ProfileService, ProfileServiceFactory } from "./service";

export const PROFILE_HTTP_BOUNDARY_VERSION = "profile-http-v1";
export const PROFILE_CONNECTION_BUILD = "phase4b-1b2a-local";
export const PROFILE_CAPABILITIES = ["bootstrap", "draft", "document", "readiness", "mutate", "freeze", "fork"] as const;
export type ProfileCapability = (typeof PROFILE_CAPABILITIES)[number];

const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEFAULT_MAX_BODY_BYTES = 64 * 1024;
const DEFAULT_REQUEST_DEADLINE_MS = 15_000;

class ProfileBoundaryError extends Error {
  constructor(readonly code: PublicProfileErrorCode) {
    super(code);
    this.name = "ProfileBoundaryError";
  }
}

type ProfileOperationalEvent = Readonly<{
  event: "PROFILE_HTTP_REQUEST_V1";
  requestId: string;
  route: string;
  status: number;
  statusClass: string;
  errorCode: PublicProfileErrorCode | null;
  durationMs: number;
  stage: "RESPONSE";
  build: typeof PROFILE_CONNECTION_BUILD;
  boundaryVersion: typeof PROFILE_HTTP_BOUNDARY_VERSION;
}>;

type ProfileRouterOptions = Readonly<{
  createService: ProfileServiceFactory;
  log?: (event: string) => void;
  now?: () => number;
  randomUUID?: () => string;
  maxBodyBytes?: number;
  requestDeadlineMs?: number;
}>;

type ProfileRouteContext = Readonly<{ params: Promise<{ capability: string }> }>;

function serverRequestId(randomUUID: () => string): string {
  let candidate: string | null = null;
  try {
    candidate = randomUUID();
  } catch {
    // Fall through to the platform CSPRNG.
  }
  return candidate && UUID_V4_PATTERN.test(candidate) ? candidate : crypto.randomUUID();
}

function responseHeaders(requestId: string, status: number): Headers {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff",
    "x-request-id": requestId,
  });
  if (status === 405) headers.set("allow", "POST");
  return headers;
}

function jsonResponse(body: unknown, status: number, requestId: string): Response {
  return new Response(JSON.stringify(body), { status, headers: responseHeaders(requestId, status) });
}

function failureResponse(code: PublicProfileErrorCode, requestId: string): Response {
  const catalog = publicProfileError(code);
  return jsonResponse({ error: code, requestId, message: catalog.message }, catalog.status, requestId);
}

function exactSameOrigin(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (origin === null) return true;
  let parsedOrigin: URL;
  try {
    parsedOrigin = new URL(origin);
  } catch {
    return false;
  }
  const host = request.headers.get("host") ?? new URL(request.url).host;
  const forwardedProtocol = request.headers.get("x-forwarded-proto")?.split(",", 1)[0].trim();
  const protocol = forwardedProtocol ? `${forwardedProtocol}:` : new URL(request.url).protocol;
  return parsedOrigin.host === host && parsedOrigin.protocol === protocol;
}

function isJson(request: Request): boolean {
  const contentType = request.headers.get("content-type");
  return contentType !== null && contentType.split(";", 1)[0].trim().toLowerCase() === "application/json";
}

function readWithAbort(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  signal: AbortSignal,
): Promise<ReadableStreamReadResult<Uint8Array>> {
  if (signal.aborted) return Promise.reject(new ProfileBoundaryError("REQUEST_TIMEOUT"));
  return new Promise((resolve, reject) => {
    const onAbort = () => {
      signal.removeEventListener("abort", onAbort);
      reject(new ProfileBoundaryError("REQUEST_TIMEOUT"));
    };
    signal.addEventListener("abort", onAbort, { once: true });
    reader.read().then(
      (result) => {
        signal.removeEventListener("abort", onAbort);
        resolve(result);
      },
      (error: unknown) => {
        signal.removeEventListener("abort", onAbort);
        reject(error);
      },
    );
  });
}

async function readBoundedJson(request: Request, maxBodyBytes: number, signal: AbortSignal): Promise<unknown> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    if (!/^\d+$/.test(contentLength) || Number(contentLength) > maxBodyBytes) {
      throw new ProfileBoundaryError("PAYLOAD_TOO_LARGE");
    }
  }
  if (request.body === null) throw new ProfileBoundaryError("INVALID_JSON");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const result = await readWithAbort(reader, signal);
      if (result.done) break;
      length += result.value.byteLength;
      if (length > maxBodyBytes) {
        await reader.cancel();
        throw new ProfileBoundaryError("PAYLOAD_TOO_LARGE");
      }
      chunks.push(result.value);
    }
  } catch (error) {
    if (signal.aborted) {
      try { await reader.cancel(); } catch { /* A closed timeout still wins. */ }
      throw new ProfileBoundaryError("REQUEST_TIMEOUT");
    }
    throw error;
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new ProfileBoundaryError("INVALID_JSON");
  }
}

async function executeCapability(capability: ProfileCapability, body: unknown, service: ProfileService): Promise<unknown> {
  switch (capability) {
    case "bootstrap":
      parseEmptyRequest(body);
      return service.bootstrap();
    case "draft": {
      const input = parseCreateDraftRequest(body);
      return service.createOrResume(input.operationId);
    }
    case "document":
      parseEmptyRequest(body);
      return service.currentDocument();
    case "readiness": {
      const input = parseProfileIdRequest(body);
      return service.readiness(input.profileVersionId);
    }
    case "mutate":
      return service.mutate(parseMutationRequest(body));
    case "freeze":
      return service.freeze(parseRevisionRequest(body));
    case "fork":
      return service.fork(parseForkRequest(body));
  }
}

function emitOperationalEvent(log: (event: string) => void, event: ProfileOperationalEvent): void {
  try {
    log(JSON.stringify(event));
  } catch {
    // Logging must never affect the closed response.
  }
}

export function createProfileRouter(options: ProfileRouterOptions) {
  const log = options.log ?? console.info;
  const now = options.now ?? (() => performance.now());
  const randomUUID = options.randomUUID ?? (() => crypto.randomUUID());
  const maxBodyBytes = options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
  const requestDeadlineMs = options.requestDeadlineMs ?? DEFAULT_REQUEST_DEADLINE_MS;

  return async function profileRoute(request: Request, context: ProfileRouteContext): Promise<Response> {
    const startedAt = now();
    const requestId = serverRequestId(randomUUID);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), requestDeadlineMs);
    let route = "PROFILE_UNKNOWN";
    let errorCode: PublicProfileErrorCode | null = null;
    let response: Response;

    try {
      const service = await options.createService(controller.signal);
      await service.authenticate();
      if (controller.signal.aborted) throw new ProfileBoundaryError("REQUEST_TIMEOUT");
      if (!exactSameOrigin(request)) throw new ProfileBoundaryError("ACCESS_DENIED");
      if (request.method !== "POST") throw new ProfileBoundaryError("METHOD_NOT_ALLOWED");
      if (!isJson(request)) throw new ProfileBoundaryError("UNSUPPORTED_MEDIA_TYPE");

      const { capability: rawCapability } = await context.params;
      if (!(PROFILE_CAPABILITIES as readonly string[]).includes(rawCapability)) {
        throw new ProfileBoundaryError("RESOURCE_NOT_FOUND");
      }
      const capability = rawCapability as ProfileCapability;
      route = `PROFILE_${capability.toUpperCase()}`;
      const body = await readBoundedJson(request, maxBodyBytes, controller.signal);
      const data = await executeCapability(capability, body, service);
      if (controller.signal.aborted) throw new ProfileBoundaryError("REQUEST_TIMEOUT");
      response = jsonResponse({ data, requestId }, 200, requestId);
    } catch (error) {
      if (controller.signal.aborted) errorCode = "REQUEST_TIMEOUT";
      else if (error instanceof ProfileBoundaryError || error instanceof ProfileServiceError) errorCode = error.code;
      else if (error instanceof ProfileContractError) errorCode = "INVALID_REQUEST";
      else errorCode = "INTERNAL_ERROR";
      response = failureResponse(errorCode, requestId);
    } finally {
      clearTimeout(timer);
    }

    emitOperationalEvent(log, {
      event: "PROFILE_HTTP_REQUEST_V1",
      requestId,
      route,
      status: response.status,
      statusClass: `${Math.floor(response.status / 100)}xx`,
      errorCode,
      durationMs: Math.max(0, Math.min(600_000, Math.round(now() - startedAt))),
      stage: "RESPONSE",
      build: PROFILE_CONNECTION_BUILD,
      boundaryVersion: PROFILE_HTTP_BOUNDARY_VERSION,
    });
    return response;
  };
}
