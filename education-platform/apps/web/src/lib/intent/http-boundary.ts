import {
  FitIntentContractError,
  parseFitIntentCreateRequest,
  parseFitIntentIdRequest,
  parseFitIntentMutationRequest,
  parseFitIntentProfileRequest,
  parseFitIntentRevisionRequest,
  parseFitIntentTaxonomyRequest,
} from "./contracts";
import { IntentServiceError, publicIntentError, type PublicIntentErrorCode } from "./errors";
import type { IntentService, IntentServiceFactory } from "./service";

export const INTENT_HTTP_BOUNDARY_VERSION = "intent-http-v1";
export const INTENT_CONNECTION_BUILD = "phase4b-m027-intent-orchestration-local";
export const INTENT_CAPABILITIES = ["discover", "create", "document", "mutate", "freeze", "taxonomy", "access-options"] as const;
type IntentCapability = (typeof INTENT_CAPABILITIES)[number];
type RouteContext = Readonly<{ params: Promise<{ capability: string }> }>;

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

class BoundaryError extends Error {
  constructor(readonly code: PublicIntentErrorCode) { super(code); }
}

type Options = Readonly<{
  createService: IntentServiceFactory;
  log?: (event: string) => void;
  now?: () => number;
  randomUUID?: () => string;
  maxBodyBytes?: number;
  requestDeadlineMs?: number;
}>;

function requestId(source: () => string): string {
  try { const value = source(); if (UUID_V4.test(value)) return value; } catch { /* use CSPRNG */ }
  return crypto.randomUUID();
}

function response(body: unknown, status: number, id: string): Response {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff",
    "x-request-id": id,
  });
  if (status === 405) headers.set("allow", "POST");
  return new Response(JSON.stringify(body), { status, headers });
}

function failure(code: PublicIntentErrorCode, id: string): Response {
  const catalog = publicIntentError(code);
  return response({ error: code, requestId: id, message: catalog.message }, catalog.status, id);
}

function sameOrigin(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (origin === null) return true;
  try {
    const parsed = new URL(origin);
    const host = request.headers.get("host") ?? new URL(request.url).host;
    const forwarded = request.headers.get("x-forwarded-proto")?.split(",", 1)[0].trim();
    return parsed.host === host && parsed.protocol === (forwarded ? `${forwarded}:` : new URL(request.url).protocol);
  } catch { return false; }
}

async function body(request: Request, maximum: number, signal: AbortSignal): Promise<unknown> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null && (!/^\d+$/.test(contentLength) || Number(contentLength) > maximum)) throw new BoundaryError("PAYLOAD_TOO_LARGE");
  if (request.body === null) throw new BoundaryError("INVALID_JSON");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    if (signal.aborted) throw new BoundaryError("REQUEST_TIMEOUT");
    const next = await reader.read();
    if (next.done) break;
    length += next.value.byteLength;
    if (length > maximum) { await reader.cancel(); throw new BoundaryError("PAYLOAD_TOO_LARGE"); }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
  catch { throw new BoundaryError("INVALID_JSON"); }
}

async function execute(capability: IntentCapability, value: unknown, service: IntentService) {
  if (capability === "discover") {
    const input = parseFitIntentProfileRequest(value);
    return service.discover(input.profileVersionId);
  }
  if (capability === "create") {
    const input = parseFitIntentCreateRequest(value);
    return service.create(input.profileVersionId, input.operationId);
  }
  if (capability === "document") {
    const input = parseFitIntentIdRequest(value);
    return service.document(input.intentSetId);
  }
  if (capability === "mutate") return service.mutate(parseFitIntentMutationRequest(value));
  if (capability === "freeze") {
    const input = parseFitIntentRevisionRequest(value);
    return service.freeze(input.intentSetId, input.operationId, input.expectedRevision);
  }
  if (capability === "taxonomy") {
    const input = parseFitIntentTaxonomyRequest(value);
    return service.taxonomy(input.intentSetId, input.dimension);
  }
  const input = parseFitIntentIdRequest(value);
  return service.accessOptions(input.intentSetId);
}

export function createIntentRouter(options: Options) {
  const log = options.log ?? console.info;
  const now = options.now ?? (() => performance.now());
  const randomUUID = options.randomUUID ?? (() => crypto.randomUUID());
  const maxBodyBytes = options.maxBodyBytes ?? 24 * 1024;
  const deadline = options.requestDeadlineMs ?? 15_000;

  return async (request: Request, context: RouteContext): Promise<Response> => {
    const started = now();
    const id = requestId(randomUUID);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), deadline);
    let route = "INTENT_UNKNOWN";
    let error: PublicIntentErrorCode | null = null;
    let result: Response;
    try {
      const service = await options.createService(controller.signal);
      await service.authenticate();
      if (!sameOrigin(request)) throw new BoundaryError("ACCESS_DENIED");
      if (request.method !== "POST") throw new BoundaryError("METHOD_NOT_ALLOWED");
      if (request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() !== "application/json") throw new BoundaryError("UNSUPPORTED_MEDIA_TYPE");
      const raw = (await context.params).capability;
      if (!(INTENT_CAPABILITIES as readonly string[]).includes(raw)) throw new BoundaryError("RESOURCE_NOT_FOUND");
      const capability = raw as IntentCapability;
      route = `INTENT_${capability.replace("-", "_").toUpperCase()}`;
      const data = await execute(capability, await body(request, maxBodyBytes, controller.signal), service);
      if (controller.signal.aborted) throw new BoundaryError("REQUEST_TIMEOUT");
      result = response({ data, requestId: id }, 200, id);
    } catch (caught) {
      if (controller.signal.aborted) error = "REQUEST_TIMEOUT";
      else if (caught instanceof BoundaryError || caught instanceof IntentServiceError) error = caught.code;
      else if (caught instanceof FitIntentContractError) error = "INVALID_REQUEST";
      else error = "INTERNAL_ERROR";
      result = failure(error, id);
    } finally { clearTimeout(timer); }
    try {
      log(JSON.stringify({
        event: "INTENT_HTTP_REQUEST_V1", requestId: id, route, stage: "RESPONSE",
        status: result.status, statusClass: `${Math.floor(result.status / 100)}xx`, errorCode: error,
        durationMs: Math.max(0, Math.min(600_000, Math.round(now() - started))),
        build: INTENT_CONNECTION_BUILD, boundaryVersion: INTENT_HTTP_BOUNDARY_VERSION,
      }));
    } catch { /* observability cannot affect behavior */ }
    return result;
  };
}
