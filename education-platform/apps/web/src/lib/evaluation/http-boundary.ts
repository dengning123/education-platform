import {
  EvaluationContractError,
  parseEligibilityConnectionRequest,
  parseFitConnectionRequest,
} from "./contracts";
import {
  EvaluationServiceError,
  publicEvaluationError,
  type PublicEvaluationErrorCode,
} from "./errors";
import type { EvaluationService, EvaluationServiceFactory } from "./service";

export const EVALUATION_HTTP_BOUNDARY_VERSION = "evaluation-http-v1";
export const EVALUATION_CONNECTION_BUILD = "phase4b-profile-eligibility-fit-local";
export const EVALUATION_CAPABILITIES = ["eligibility", "fit"] as const;
export type EvaluationCapability = (typeof EVALUATION_CAPABILITIES)[number];

const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DEFAULT_MAX_BODY_BYTES = 64 * 1024;
const DEFAULT_REQUEST_DEADLINE_MS = 50_000;

class EvaluationBoundaryError extends Error {
  constructor(readonly code: PublicEvaluationErrorCode) {
    super(code);
    this.name = "EvaluationBoundaryError";
  }
}

type EvaluationOperationalEvent = Readonly<{
  event: "EVALUATION_HTTP_REQUEST_V1";
  requestId: string;
  route: string;
  stage: "RESPONSE";
  status: number;
  statusClass: string;
  errorCode: PublicEvaluationErrorCode | null;
  durationMs: number;
  build: typeof EVALUATION_CONNECTION_BUILD;
  boundaryVersion: typeof EVALUATION_HTTP_BOUNDARY_VERSION;
}>;

type EvaluationRouterOptions = Readonly<{
  createService: EvaluationServiceFactory;
  log?: (event: string) => void;
  now?: () => number;
  randomUUID?: () => string;
  maxBodyBytes?: number;
  requestDeadlineMs?: number;
}>;

type EvaluationRouteContext = Readonly<{ params: Promise<{ capability: string }> }>;

function serverRequestId(randomUUID: () => string): string {
  let candidate: string | null = null;
  try { candidate = randomUUID(); } catch { /* Fall back to the platform CSPRNG. */ }
  return candidate && UUID_V4_PATTERN.test(candidate) ? candidate : crypto.randomUUID();
}

function headers(requestId: string, status: number): Headers {
  const result = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-content-type-options": "nosniff",
    "x-request-id": requestId,
  });
  if (status === 405) result.set("allow", "POST");
  return result;
}

function json(body: unknown, status: number, requestId: string): Response {
  return new Response(JSON.stringify(body), { status, headers: headers(requestId, status) });
}

function failure(code: PublicEvaluationErrorCode, requestId: string): Response {
  const catalog = publicEvaluationError(code);
  return json({ error: code, requestId, message: catalog.message }, catalog.status, requestId);
}

function exactSameOrigin(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (origin === null) return true;
  let parsed: URL;
  try { parsed = new URL(origin); } catch { return false; }
  const host = request.headers.get("host") ?? new URL(request.url).host;
  const forwarded = request.headers.get("x-forwarded-proto")?.split(",", 1)[0].trim();
  const protocol = forwarded ? `${forwarded}:` : new URL(request.url).protocol;
  return parsed.host === host && parsed.protocol === protocol;
}

function isJson(request: Request): boolean {
  const contentType = request.headers.get("content-type");
  return contentType !== null && contentType.split(";", 1)[0].trim().toLowerCase() === "application/json";
}

async function readBoundedJson(request: Request, maxBodyBytes: number, signal: AbortSignal): Promise<unknown> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null && (!/^\d+$/.test(contentLength) || Number(contentLength) > maxBodyBytes)) {
    throw new EvaluationBoundaryError("PAYLOAD_TOO_LARGE");
  }
  if (request.body === null) throw new EvaluationBoundaryError("INVALID_JSON");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      if (signal.aborted) throw new EvaluationBoundaryError("REQUEST_TIMEOUT");
      const result = await reader.read();
      if (result.done) break;
      length += result.value.byteLength;
      if (length > maxBodyBytes) {
        await reader.cancel();
        throw new EvaluationBoundaryError("PAYLOAD_TOO_LARGE");
      }
      chunks.push(result.value);
    }
  } catch (error) {
    if (signal.aborted) throw new EvaluationBoundaryError("REQUEST_TIMEOUT");
    throw error;
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
  catch { throw new EvaluationBoundaryError("INVALID_JSON"); }
}

async function execute(capability: EvaluationCapability, body: unknown, service: EvaluationService) {
  return capability === "eligibility"
    ? service.eligibility(parseEligibilityConnectionRequest(body))
    : service.fit(parseFitConnectionRequest(body));
}

function emit(log: (event: string) => void, event: EvaluationOperationalEvent): void {
  try { log(JSON.stringify(event)); } catch { /* Logging cannot affect the response. */ }
}

export function createEvaluationRouter(options: EvaluationRouterOptions) {
  const log = options.log ?? console.info;
  const now = options.now ?? (() => performance.now());
  const randomUUID = options.randomUUID ?? (() => crypto.randomUUID());
  const maxBodyBytes = options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
  const deadline = options.requestDeadlineMs ?? DEFAULT_REQUEST_DEADLINE_MS;

  return async function evaluationRoute(request: Request, context: EvaluationRouteContext): Promise<Response> {
    const startedAt = now();
    const requestId = serverRequestId(randomUUID);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), deadline);
    let route = "EVALUATION_UNKNOWN";
    let errorCode: PublicEvaluationErrorCode | null = null;
    let response: Response;
    try {
      const service = await options.createService(controller.signal);
      await service.authenticate();
      if (controller.signal.aborted) throw new EvaluationBoundaryError("REQUEST_TIMEOUT");
      if (!exactSameOrigin(request)) throw new EvaluationBoundaryError("ACCESS_DENIED");
      if (request.method !== "POST") throw new EvaluationBoundaryError("METHOD_NOT_ALLOWED");
      if (!isJson(request)) throw new EvaluationBoundaryError("UNSUPPORTED_MEDIA_TYPE");
      const { capability: rawCapability } = await context.params;
      if (!(EVALUATION_CAPABILITIES as readonly string[]).includes(rawCapability)) throw new EvaluationBoundaryError("RESOURCE_NOT_FOUND");
      const capability = rawCapability as EvaluationCapability;
      route = `EVALUATION_${capability.toUpperCase()}`;
      const body = await readBoundedJson(request, maxBodyBytes, controller.signal);
      const data = await execute(capability, body, service);
      if (controller.signal.aborted) throw new EvaluationBoundaryError("REQUEST_TIMEOUT");
      response = json({ data, requestId }, 200, requestId);
    } catch (error) {
      if (controller.signal.aborted) errorCode = "REQUEST_TIMEOUT";
      else if (error instanceof EvaluationBoundaryError || error instanceof EvaluationServiceError) errorCode = error.code;
      else if (error instanceof EvaluationContractError) errorCode = "INVALID_REQUEST";
      else errorCode = "INTERNAL_ERROR";
      response = failure(errorCode, requestId);
    } finally {
      clearTimeout(timer);
    }
    emit(log, {
      event: "EVALUATION_HTTP_REQUEST_V1",
      requestId,
      route,
      stage: "RESPONSE",
      status: response.status,
      statusClass: `${Math.floor(response.status / 100)}xx`,
      errorCode,
      durationMs: Math.max(0, Math.min(600_000, Math.round(now() - startedAt))),
      build: EVALUATION_CONNECTION_BUILD,
      boundaryVersion: EVALUATION_HTTP_BOUNDARY_VERSION,
    });
    return response;
  };
}
