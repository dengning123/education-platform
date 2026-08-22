const ALLOWED_REQUEST_HEADERS = Object.freeze([
  "authorization",
  "apikey",
  "content-type",
  "x-client-info",
]);

const PUBLIC_ERROR_CATALOG = new Map([
  ["AUTHENTICATION_REQUIRED", 401],
  ["CORS_ORIGIN_DENIED", 403],
  ["DEPENDENCY_DEADLINE_EXCEEDED", 504],
  ["FIT_EVALUATION_FAILED_CLOSED", 500],
  ["FIT_EVALUATION_REJECTED", 422],
  ["FIT_NORMALIZATION_PREPARATION_FAILED_CLOSED", 500],
  ["FIT_NORMALIZATION_PREPARATION_REJECTED", 422],
  ["FIT_NORMALIZATION_REVIEW_FAILED_CLOSED", 500],
  ["FIT_NORMALIZATION_REVIEW_REJECTED", 422],
  ["FIT_NORMALIZATION_RESUME_FAILED_CLOSED", 500],
  ["FIT_NORMALIZATION_RESUME_REJECTED", 422],
  ["INVALID_JSON", 400],
  ["METHOD_NOT_ALLOWED", 405],
  ["PAYLOAD_TOO_LARGE", 413],
  ["PROFILE_NOT_FOUND", 404],
  ["REQUEST_ABORTED", 408],
  ["REQUEST_DEADLINE_EXCEEDED", 504],
  ["SERVICE_CONFIGURATION_MISSING", 500],
  ["UNSUPPORTED_MEDIA_TYPE", 415],
]);

const DEFAULT_MAX_BODY_BYTES = 64 * 1024;
const DEFAULT_REQUEST_DEADLINE_MS = 50_000;
const DEFAULT_DEPENDENCY_DEADLINE_MS = 10_000;
export const EDGE_HTTP_BOUNDARY_VERSION = "fit-edge-http-v1";
const CONFIG_VALUE_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class EdgeHttpError extends Error {
  constructor(code, status = undefined) {
    if (!PUBLIC_ERROR_CATALOG.has(code)) {
      throw new TypeError("Unknown public Edge error code");
    }
    super(code);
    this.name = "EdgeHttpError";
    this.code = code;
    this.status = normalizeErrorStatus(status ?? PUBLIC_ERROR_CATALOG.get(code));
  }
}

export function edgeHttpError(code, status = undefined) {
  return new EdgeHttpError(code, status);
}

export function normalizeErrorStatus(status) {
  if (Number.isInteger(status) && status >= 400 && status <= 599) return status;
  return 500;
}

export function jsonSuccess(body, status) {
  if (!Number.isInteger(status) || status < 200 || status > 299) {
    throw new TypeError("Edge success status must be in the 2xx range");
  }
  return Object.freeze({ body, status });
}

function parseBoundedInteger(raw, fallback, minimum, maximum) {
  if (raw === undefined || raw === "") return fallback;
  if (!/^[0-9]+$/.test(raw)) throw new TypeError("Invalid Edge numeric configuration");
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new TypeError("Edge numeric configuration is out of bounds");
  }
  return value;
}

function parseReleaseValue(raw) {
  if (raw === undefined || !CONFIG_VALUE_PATTERN.test(raw)) {
    throw new TypeError("Missing or invalid Edge release configuration");
  }
  return raw;
}

export function parseAllowedOrigins(raw) {
  if (raw === undefined) throw new TypeError("Missing Edge origin configuration");
  if (raw === "none") return new Set();
  if (raw.length === 0 || raw.includes("*")) {
    throw new TypeError("Invalid Edge origin configuration");
  }

  const origins = raw.split(",").map((value) => value.trim());
  if (origins.some((value) => value.length === 0)) {
    throw new TypeError("Invalid Edge origin configuration");
  }

  const result = new Set();
  for (const origin of origins) {
    let parsed;
    try {
      parsed = new URL(origin);
    } catch {
      throw new TypeError("Invalid Edge origin configuration");
    }
    if (
      (parsed.protocol !== "https:" && parsed.protocol !== "http:") ||
      parsed.username !== "" ||
      parsed.password !== "" ||
      parsed.pathname !== "/" ||
      parsed.search !== "" ||
      parsed.hash !== "" ||
      parsed.origin !== origin
    ) {
      throw new TypeError("Invalid Edge origin configuration");
    }
    result.add(origin);
  }
  return result;
}

export function readEdgeConfiguration(getEnv) {
  const configuration = {
    allowedOrigins: parseAllowedOrigins(getEnv("FIT_EDGE_ALLOWED_ORIGINS")),
    semanticRelease: parseReleaseValue(getEnv("FIT_EDGE_SEMANTIC_RELEASE")),
    deployedBuild: parseReleaseValue(getEnv("FIT_EDGE_DEPLOYED_BUILD")),
    boundaryVersion: EDGE_HTTP_BOUNDARY_VERSION,
    maxBodyBytes: parseBoundedInteger(
      getEnv("FIT_EDGE_MAX_BODY_BYTES"),
      DEFAULT_MAX_BODY_BYTES,
      1024,
      1024 * 1024,
    ),
    requestDeadlineMs: parseBoundedInteger(
      getEnv("FIT_EDGE_REQUEST_DEADLINE_MS"),
      DEFAULT_REQUEST_DEADLINE_MS,
      1,
      60_000,
    ),
    dependencyDeadlineMs: parseBoundedInteger(
      getEnv("FIT_EDGE_DEPENDENCY_DEADLINE_MS"),
      DEFAULT_DEPENDENCY_DEADLINE_MS,
      1,
      30_000,
    ),
  };
  return Object.freeze(configuration);
}

function baseHeaders(requestId, origin, originAllowed) {
  const headers = new Headers({ "x-request-id": requestId });
  if (origin !== null) headers.set("vary", "Origin");
  if (originAllowed) {
    headers.set("access-control-allow-origin", origin);
    headers.set("access-control-expose-headers", "x-request-id");
  }
  return headers;
}

function jsonResponse(body, status, requestId, origin, originAllowed, extraHeaders = undefined) {
  const headers = baseHeaders(requestId, origin, originAllowed);
  headers.set("content-type", "application/json; charset=utf-8");
  if (extraHeaders !== undefined) {
    for (const [name, value] of Object.entries(extraHeaders)) headers.set(name, value);
  }
  return new Response(JSON.stringify(body), { status, headers });
}

function publicErrorResponse(error, requestId, origin, originAllowed) {
  const extraHeaders = error.code === "METHOD_NOT_ALLOWED" ? { allow: "POST, OPTIONS" } : undefined;
  return jsonResponse(
    { error: error.code, requestId },
    error.status,
    requestId,
    origin,
    originAllowed,
    extraHeaders,
  );
}

function requestedHeadersAreAllowed(request) {
  const raw = request.headers.get("access-control-request-headers");
  if (raw === null || raw.trim() === "") return true;
  const requested = raw.split(",").map((value) => value.trim().toLowerCase());
  return requested.every((value) => ALLOWED_REQUEST_HEADERS.includes(value));
}

function preflightResponse(request, requestId, origin, originAllowed) {
  if (
    origin === null ||
    !originAllowed ||
    request.headers.get("access-control-request-method")?.toUpperCase() !== "POST" ||
    !requestedHeadersAreAllowed(request)
  ) {
    throw edgeHttpError("CORS_ORIGIN_DENIED");
  }
  const headers = baseHeaders(requestId, origin, true);
  headers.set("access-control-allow-headers", ALLOWED_REQUEST_HEADERS.join(", "));
  headers.set("access-control-allow-methods", "POST, OPTIONS");
  headers.set("access-control-max-age", "600");
  return new Response(null, { status: 204, headers });
}

function isJsonContentType(request) {
  const raw = request.headers.get("content-type");
  return raw !== null && raw.split(";", 1)[0].trim().toLowerCase() === "application/json";
}

function requestDeadlineError(deadline) {
  return edgeHttpError(deadline.abortCode() ?? "REQUEST_DEADLINE_EXCEEDED");
}

function createRequestDeadline(request, deadlineMs) {
  const controller = new AbortController();
  let abortCode = null;
  const abort = (code) => {
    if (controller.signal.aborted) return;
    abortCode = code;
    controller.abort();
  };
  const onRequestAbort = () => abort("REQUEST_ABORTED");
  if (request.signal.aborted) onRequestAbort();
  else request.signal.addEventListener("abort", onRequestAbort, { once: true });
  const timer = setTimeout(() => abort("REQUEST_DEADLINE_EXCEEDED"), deadlineMs);

  return Object.freeze({
    signal: controller.signal,
    abortCode: () => abortCode,
    dispose: () => {
      clearTimeout(timer);
      request.signal.removeEventListener("abort", onRequestAbort);
    },
  });
}

async function readBodyChunk(reader, deadline) {
  if (deadline.signal.aborted) throw requestDeadlineError(deadline);
  return await new Promise((resolve, reject) => {
    const onAbort = () => reject(requestDeadlineError(deadline));
    deadline.signal.addEventListener("abort", onAbort, { once: true });
    reader.read().then(resolve, reject).finally(() => {
      deadline.signal.removeEventListener("abort", onAbort);
    });
  });
}

async function readBoundedJson(request, maxBodyBytes, deadline) {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    if (!/^[0-9]+$/.test(contentLength)) throw edgeHttpError("PAYLOAD_TOO_LARGE");
    if (Number(contentLength) > maxBodyBytes) throw edgeHttpError("PAYLOAD_TOO_LARGE");
  }
  if (request.body === null) throw edgeHttpError("INVALID_JSON");

  const reader = request.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await readBodyChunk(reader, deadline);
      if (done) break;
      length += value.byteLength;
      if (length > maxBodyBytes) {
        await reader.cancel();
        throw edgeHttpError("PAYLOAD_TOO_LARGE");
      }
      chunks.push(value);
    }
  } catch (error) {
    if (deadline.signal.aborted) {
      try {
        await reader.cancel();
      } catch {
        // The public response is determined only by the closed deadline catalog.
      }
      throw requestDeadlineError(deadline);
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
    throw edgeHttpError("INVALID_JSON");
  }
}

function createDependencyFetch(fetchImpl, requestDeadline, deadlineMs) {
  return async function dependencyFetch(input, init = undefined) {
    const controller = new AbortController();
    let abortCode = null;
    const abort = (code) => {
      if (controller.signal.aborted) return;
      abortCode = code;
      controller.abort();
    };
    const onRequestDeadline = () => {
      abort(requestDeadline.abortCode() ?? "REQUEST_DEADLINE_EXCEEDED");
    };
    const callerSignal = init?.signal;
    const onCallerAbort = () => abort("REQUEST_ABORTED");

    if (requestDeadline.signal.aborted) onRequestDeadline();
    else requestDeadline.signal.addEventListener("abort", onRequestDeadline, { once: true });
    if (callerSignal?.aborted) onCallerAbort();
    else callerSignal?.addEventListener("abort", onCallerAbort, { once: true });

    const timer = setTimeout(() => abort("DEPENDENCY_DEADLINE_EXCEEDED"), deadlineMs);
    try {
      const response = await fetchImpl(input, { ...init, signal: controller.signal });
      if (abortCode !== null) throw edgeHttpError(abortCode);
      return response;
    } catch (error) {
      if (abortCode !== null) throw edgeHttpError(abortCode);
      throw error;
    } finally {
      clearTimeout(timer);
      requestDeadline.signal.removeEventListener("abort", onRequestDeadline);
      callerSignal?.removeEventListener("abort", onCallerAbort);
    }
  };
}

function validAuthorization(request) {
  const authorization = request.headers.get("authorization");
  if (authorization === null || !authorization.startsWith("Bearer ")) return null;
  const token = authorization.slice("Bearer ".length);
  return token.trim().length === 0 ? null : authorization;
}

function statusClass(status) {
  return `${Math.floor(status / 100)}xx`;
}

function emitEvent(log, event) {
  const status = Number.isInteger(event.status) && event.status >= 100 && event.status <= 599
    ? event.status
    : 500;
  const durationMs = Number.isFinite(event.durationMs)
    ? Math.min(600_000, Math.max(0, Math.round(event.durationMs)))
    : 0;
  const errorCode = event.errorCode !== null && PUBLIC_ERROR_CATALOG.has(event.errorCode)
    ? event.errorCode
    : null;
  const operationalEvent = {
    event: "FIT_EDGE_REQUEST_V2",
    requestId: event.requestId,
    endpoint: event.endpoint,
    semanticRelease: event.semanticRelease,
    deployedBuild: event.deployedBuild,
    boundaryVersion: event.boundaryVersion,
    stage: "RESPONSE",
    status,
    statusClass: statusClass(status),
    errorCode,
    durationMs,
    coldStart: event.coldStart === true,
  };
  try {
    log(JSON.stringify(operationalEvent));
  } catch {
    // Operational logging must never change the HTTP result.
  }
}

function serverRequestId(randomUUID) {
  let candidate;
  try {
    candidate = randomUUID();
  } catch {
    candidate = null;
  }
  if (typeof candidate === "string" && UUID_PATTERN.test(candidate)) return candidate;
  return crypto.randomUUID();
}

export function createEdgeHttpHandler({
  endpoint,
  internalErrorCode,
  handler,
  getEnv,
  log = console.log,
  now = () => performance.now(),
  randomUUID = () => crypto.randomUUID(),
  fetchImpl = fetch,
}) {
  if (typeof endpoint !== "string" || !CONFIG_VALUE_PATTERN.test(endpoint)) {
    throw new TypeError("Invalid Edge endpoint code");
  }
  if (typeof handler !== "function" || typeof getEnv !== "function" || typeof fetchImpl !== "function") {
    throw new TypeError("Invalid Edge handler configuration");
  }
  if (!PUBLIC_ERROR_CATALOG.has(internalErrorCode)) {
    throw new TypeError("Unknown internal Edge error code");
  }

  let coldStart = true;
  return async function edgeHttpHandler(request) {
    const startedAt = now();
    const requestId = serverRequestId(randomUUID);
    const origin = request.headers.get("origin");
    let configuration;
    let requestDeadline;
    let originAllowed = false;
    let response;
    let errorCode = null;

    try {
      configuration = readEdgeConfiguration(getEnv);
      originAllowed = origin !== null && configuration.allowedOrigins.has(origin);
      if (request.method === "OPTIONS") {
        response = preflightResponse(request, requestId, origin, originAllowed);
      } else {
        requestDeadline = createRequestDeadline(request, configuration.requestDeadlineMs);
        if (origin !== null && !originAllowed) throw edgeHttpError("CORS_ORIGIN_DENIED");
        if (request.method !== "POST") throw edgeHttpError("METHOD_NOT_ALLOWED");
        if (!isJsonContentType(request)) throw edgeHttpError("UNSUPPORTED_MEDIA_TYPE");
        const authorization = validAuthorization(request);
        if (authorization === null) throw edgeHttpError("AUTHENTICATION_REQUIRED");

        const body = await readBoundedJson(request, configuration.maxBodyBytes, requestDeadline);
        const dependencyFetch = createDependencyFetch(
          fetchImpl,
          requestDeadline,
          configuration.dependencyDeadlineMs,
        );
        const result = await handler({
          request,
          body,
          authorization,
          requestId,
          dependencyFetch,
        });
        if (
          result === null ||
          typeof result !== "object" ||
          !Number.isInteger(result.status) ||
          result.status < 200 ||
          result.status > 299 ||
          !("body" in result)
        ) {
          throw new TypeError("Invalid Edge success result");
        }
        response = jsonResponse(result.body, result.status, requestId, origin, originAllowed);
      }
    } catch (error) {
      const publicError = error instanceof EdgeHttpError
        ? error
        : edgeHttpError(internalErrorCode);
      errorCode = publicError.code;
      const errorOriginAllowed = publicError.code === "CORS_ORIGIN_DENIED"
        ? false
        : originAllowed;
      response = publicErrorResponse(publicError, requestId, origin, errorOriginAllowed);
    } finally {
      requestDeadline?.dispose();
    }

    const semanticRelease = configuration?.semanticRelease ?? "configuration-unavailable";
    const deployedBuild = configuration?.deployedBuild ?? "configuration-unavailable";
    const boundaryVersion = configuration?.boundaryVersion ?? EDGE_HTTP_BOUNDARY_VERSION;
    emitEvent(log, {
      requestId,
      endpoint,
      semanticRelease,
      deployedBuild,
      boundaryVersion,
      status: response.status,
      errorCode,
      durationMs: now() - startedAt,
      coldStart,
    });
    coldStart = false;
    return response;
  };
}
