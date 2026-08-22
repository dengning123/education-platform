import assert from "node:assert/strict";
import test from "node:test";

import {
  createEdgeHttpHandler,
  EDGE_HTTP_BOUNDARY_VERSION,
  edgeHttpError,
  jsonSuccess,
  normalizeErrorStatus,
  parseAllowedOrigins,
} from "./http-boundary.js";

const allowedOrigin = "https://app.example.test";

function environment(overrides = {}) {
  const values = {
    FIT_EDGE_ALLOWED_ORIGINS: allowedOrigin,
    FIT_EDGE_SEMANTIC_RELEASE: "fit-v0.1",
    FIT_EDGE_DEPLOYED_BUILD: "build-0123456789abcdef",
    ...overrides,
  };
  return (name) => values[name];
}

function request({
  body = { ok: true },
  headers = {},
  method = "POST",
  origin,
  rawBody,
} = {}) {
  const allHeaders = {
    authorization: "Bearer valid-token",
    "content-type": "application/json",
    ...headers,
  };
  if (origin !== undefined) allHeaders.origin = origin;
  return new Request("https://project.example.test/functions/v1/test", {
    method,
    headers: allHeaders,
    body: method === "POST" ? (rawBody ?? JSON.stringify(body)) : undefined,
  });
}

function harness(options = {}) {
  const logs = [];
  let observedContext;
  const handler = createEdgeHttpHandler({
    endpoint: "FIT_TEST",
    internalErrorCode: "FIT_EVALUATION_FAILED_CLOSED",
    getEnv: options.getEnv ?? environment(),
    randomUUID: options.randomUUID ?? (() => "00000000-0000-4000-8000-000000000001"),
    now: options.now ?? (() => 10),
    fetchImpl: options.fetchImpl,
    log: (line) => logs.push(line),
    handler: options.handler ?? ((context) => {
      observedContext = context;
      return jsonSuccess({ accepted: context.body }, 201);
    }),
  });
  return { handler, logs, observedContext: () => observedContext };
}

function abortingFetch(_input, init) {
  return new Promise((_resolve, reject) => {
    const rejectForAbort = () => reject(new Error("raw dependency abort detail"));
    if (init.signal.aborted) rejectForAbort();
    else init.signal.addEventListener("abort", rejectForAbort, { once: true });
  });
}

async function json(response) {
  return JSON.parse(await response.text());
}

test("allowlisted browser origin receives exact CORS grant and compatible success JSON", async () => {
  const { handler, observedContext } = harness();
  const response = await handler(request({ origin: allowedOrigin, body: { value: 3 } }));
  assert.equal(response.status, 201);
  assert.equal(response.headers.get("access-control-allow-origin"), allowedOrigin);
  assert.equal(response.headers.get("access-control-expose-headers"), "x-request-id");
  assert.equal(response.headers.get("access-control-allow-credentials"), null);
  assert.equal(response.headers.get("vary"), "Origin");
  assert.equal(response.headers.get("x-request-id"), "00000000-0000-4000-8000-000000000001");
  assert.equal(await response.text(), '{"accepted":{"value":3}}');
  assert.deepEqual(observedContext().body, { value: 3 });
});

test("inbound request ID is never trusted", async () => {
  const { handler } = harness();
  const response = await handler(request({ headers: { "x-request-id": "attacker-value" } }));
  assert.equal(response.headers.get("x-request-id"), "00000000-0000-4000-8000-000000000001");
  assert.notEqual(response.headers.get("x-request-id"), "attacker-value");
});

test("non-browser request proceeds without any wildcard CORS grant", async () => {
  const { handler } = harness();
  const response = await handler(request());
  assert.equal(response.status, 201);
  assert.equal(response.headers.get("access-control-allow-origin"), null);
  assert.equal(response.headers.get("vary"), null);
});

test("valid preflight is exact and has no body", async () => {
  const { handler } = harness();
  const response = await handler(request({
    method: "OPTIONS",
    origin: allowedOrigin,
    headers: {
      "access-control-request-method": "POST",
      "access-control-request-headers": "authorization, content-type",
    },
  }));
  assert.equal(response.status, 204);
  assert.equal(await response.text(), "");
  assert.equal(response.headers.get("access-control-allow-origin"), allowedOrigin);
  assert.equal(response.headers.get("access-control-allow-methods"), "POST, OPTIONS");
  assert.equal(response.headers.get("access-control-allow-credentials"), null);
});

for (const options of [
  { name: "unknown origin", origin: "https://evil.example", headers: { "access-control-request-method": "POST" } },
  { name: "unknown header", origin: allowedOrigin, headers: { "access-control-request-method": "POST", "access-control-request-headers": "x-secret" } },
  { name: "unknown method", origin: allowedOrigin, headers: { "access-control-request-method": "DELETE" } },
]) {
  test(`preflight rejects ${options.name} without a CORS grant`, async () => {
    const { handler } = harness();
    const response = await handler(request({ method: "OPTIONS", ...options }));
    assert.equal(response.status, 403);
    assert.equal(response.headers.get("access-control-allow-origin"), null);
    assert.deepEqual(await json(response), {
      error: "CORS_ORIGIN_DENIED",
      requestId: "00000000-0000-4000-8000-000000000001",
    });
  });
}

test("actual request from unknown browser origin is rejected before work", async () => {
  let called = false;
  const { handler } = harness({ handler: () => { called = true; return jsonSuccess({}, 200); } });
  const response = await handler(request({ origin: "https://evil.example" }));
  assert.equal(response.status, 403);
  assert.equal(response.headers.get("access-control-allow-origin"), null);
  assert.equal(called, false);
});

test("method, media type, authentication, and malformed JSON failures use closed envelopes", async () => {
  const cases = [
    [request({ method: "GET" }), 405, "METHOD_NOT_ALLOWED"],
    [request({ headers: { "content-type": "text/plain" } }), 415, "UNSUPPORTED_MEDIA_TYPE"],
    [request({ headers: { authorization: "" } }), 401, "AUTHENTICATION_REQUIRED"],
    [request({ rawBody: "{" }), 400, "INVALID_JSON"],
  ];
  for (const [input, status, code] of cases) {
    const { handler } = harness();
    const response = await handler(input);
    assert.equal(response.status, status);
    assert.deepEqual(await json(response), {
      error: code,
      requestId: "00000000-0000-4000-8000-000000000001",
    });
  }
});

test("body limit is enforced from both declared and observed bytes", async () => {
  const getEnv = environment({ FIT_EDGE_MAX_BODY_BYTES: "1024" });
  const declared = harness({ getEnv });
  const declaredResponse = await declared.handler(request({ headers: { "content-length": "2048" } }));
  assert.equal(declaredResponse.status, 413);

  const observed = harness({ getEnv });
  const observedResponse = await observed.handler(request({ rawBody: JSON.stringify({ value: "x".repeat(2048) }) }));
  assert.equal(observedResponse.status, 413);
  assert.equal((await json(observedResponse)).error, "PAYLOAD_TOO_LARGE");
});

test("public handler failures preserve only catalog code, safe status, and server request ID", async () => {
  const { handler } = harness({
    handler: () => { throw edgeHttpError("FIT_EVALUATION_REJECTED", 409); },
  });
  const response = await handler(request({ rawBody: '{"secret":"must-not-leak"}' }));
  assert.equal(response.status, 409);
  const text = await response.text();
  assert.equal(text, '{"error":"FIT_EVALUATION_REJECTED","requestId":"00000000-0000-4000-8000-000000000001"}');
  assert.equal(text.includes("must-not-leak"), false);
});

test("unknown exceptions fail closed without raw messages or nested details", async () => {
  const { handler, logs } = harness({
    handler: () => { throw new Error("SQLSTATE 99999 student-id secret-token", { cause: { detail: "raw detail" } }); },
  });
  const response = await handler(request());
  assert.equal(response.status, 500);
  const text = await response.text();
  assert.equal(text, '{"error":"FIT_EVALUATION_FAILED_CLOSED","requestId":"00000000-0000-4000-8000-000000000001"}');
  assert.equal(text.includes("SQLSTATE"), false);
  assert.equal(text.includes("raw detail"), false);
  assert.equal(logs[0].includes("SQLSTATE"), false);
  assert.equal(logs[0].includes("secret-token"), false);
  assert.equal(logs[0].includes("raw detail"), false);
});

test("invalid generated IDs are replaced and never make client input authoritative", async () => {
  const { handler } = harness({ randomUUID: () => "invalid-server-id" });
  const response = await handler(request({ headers: { "x-request-id": "attacker-id" } }));
  const responseRequestId = response.headers.get("x-request-id");
  assert.match(responseRequestId, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  assert.notEqual(responseRequestId, "attacker-id");
  assert.notEqual(responseRequestId, "invalid-server-id");
});

test("dependency deadline aborts the actual injected dependency fetch and fails closed", async () => {
  let observedSignal;
  const { handler, logs } = harness({
    getEnv: environment({
      FIT_EDGE_DEPENDENCY_DEADLINE_MS: "5",
      FIT_EDGE_REQUEST_DEADLINE_MS: "100",
    }),
    fetchImpl: (input, init) => {
      observedSignal = init.signal;
      return abortingFetch(input, init);
    },
    handler: async ({ dependencyFetch }) => {
      await dependencyFetch("https://dependency.example.test/rpc");
      return jsonSuccess({ unreachable: true }, 200);
    },
  });
  const response = await handler(request());
  assert.equal(response.status, 504);
  assert.equal(observedSignal.aborted, true);
  assert.deepEqual(await json(response), {
    error: "DEPENDENCY_DEADLINE_EXCEEDED",
    requestId: "00000000-0000-4000-8000-000000000001",
  });
  assert.equal(logs[0].includes("raw dependency abort detail"), false);
});

test("request deadline propagates through and aborts an in-flight dependency", async () => {
  let observedSignal;
  const { handler } = harness({
    getEnv: environment({
      FIT_EDGE_DEPENDENCY_DEADLINE_MS: "100",
      FIT_EDGE_REQUEST_DEADLINE_MS: "5",
    }),
    fetchImpl: (input, init) => {
      observedSignal = init.signal;
      return abortingFetch(input, init);
    },
    handler: async ({ dependencyFetch }) => {
      await dependencyFetch("https://dependency.example.test/rpc");
      return jsonSuccess({ unreachable: true }, 200);
    },
  });
  const response = await handler(request());
  assert.equal(response.status, 504);
  assert.equal(observedSignal.aborted, true);
  assert.equal((await json(response)).error, "REQUEST_DEADLINE_EXCEEDED");
});

test("request deadline bounds a stalled request body before dependency work", async () => {
  let called = false;
  const body = new ReadableStream({ start() {} });
  const stalledRequest = new Request("https://project.example.test/functions/v1/test", {
    method: "POST",
    headers: {
      authorization: "Bearer valid-token",
      "content-type": "application/json",
    },
    body,
    duplex: "half",
  });
  const { handler } = harness({
    getEnv: environment({ FIT_EDGE_REQUEST_DEADLINE_MS: "5" }),
    handler: () => {
      called = true;
      return jsonSuccess({}, 200);
    },
  });
  const response = await handler(stalledRequest);
  assert.equal(response.status, 504);
  assert.equal((await json(response)).error, "REQUEST_DEADLINE_EXCEEDED");
  assert.equal(called, false);
});

test("caller abort maps to a stable closed request error", async () => {
  const controller = new AbortController();
  const input = request();
  const abortedRequest = new Request(input, { signal: controller.signal });
  const { handler } = harness({
    getEnv: environment({
      FIT_EDGE_DEPENDENCY_DEADLINE_MS: "100",
      FIT_EDGE_REQUEST_DEADLINE_MS: "100",
    }),
    fetchImpl: abortingFetch,
    handler: async ({ dependencyFetch }) => {
      setTimeout(() => controller.abort(), 5);
      await dependencyFetch("https://dependency.example.test/rpc");
      return jsonSuccess({ unreachable: true }, 200);
    },
  });
  const response = await handler(abortedRequest);
  assert.equal(response.status, 408);
  assert.equal((await json(response)).error, "REQUEST_ABORTED");
});

test("structured event is allowlisted and excludes headers, payload, and object identifiers", async () => {
  const { handler, logs } = harness();
  await handler(request({
    body: { profileVersionId: "11111111-1111-4111-8111-111111111111", amount: 999999 },
    headers: { authorization: "Bearer top-secret-token", cookie: "session=secret" },
  }));
  assert.equal(logs.length, 1);
  const event = JSON.parse(logs[0]);
  assert.deepEqual(Object.keys(event), [
    "event", "requestId", "endpoint", "semanticRelease", "deployedBuild",
    "boundaryVersion", "stage",
    "status", "statusClass", "errorCode", "durationMs", "coldStart",
  ]);
  assert.equal(event.event, "FIT_EDGE_REQUEST_V2");
  assert.equal(event.semanticRelease, "fit-v0.1");
  assert.equal(event.deployedBuild, "build-0123456789abcdef");
  assert.equal(event.boundaryVersion, EDGE_HTTP_BOUNDARY_VERSION);
  for (const forbidden of ["top-secret-token", "session=secret", "11111111-1111-4111-8111-111111111111", "999999"]) {
    assert.equal(logs[0].includes(forbidden), false);
  }
});

test("invalid or wildcard deployment configuration fails closed", async () => {
  for (const getEnv of [
    environment({ FIT_EDGE_ALLOWED_ORIGINS: "*" }),
    environment({ FIT_EDGE_ALLOWED_ORIGINS: "https://app.example.test/" }),
    environment({ FIT_EDGE_SEMANTIC_RELEASE: "" }),
    environment({ FIT_EDGE_REQUEST_DEADLINE_MS: "60001" }),
    environment({ FIT_EDGE_DEPENDENCY_DEADLINE_MS: "0" }),
  ]) {
    const { handler } = harness({ getEnv });
    const response = await handler(request({ origin: allowedOrigin }));
    assert.equal(response.status, 500);
    assert.equal(response.headers.get("access-control-allow-origin"), null);
    assert.equal((await json(response)).error, "FIT_EVALUATION_FAILED_CLOSED");
  }
});

test("deny-all origin configuration remains valid for non-browser smoke", async () => {
  assert.equal(parseAllowedOrigins("none").size, 0);
  const { handler } = harness({ getEnv: environment({ FIT_EDGE_ALLOWED_ORIGINS: "none" }) });
  assert.equal((await handler(request())).status, 201);
  assert.equal((await handler(request({ origin: allowedOrigin }))).status, 403);
});

test("adapter status normalization cannot escape HTTP error range", () => {
  assert.equal(normalizeErrorStatus(409), 409);
  assert.equal(normalizeErrorStatus(599), 599);
  assert.equal(normalizeErrorStatus(200), 500);
  assert.equal(normalizeErrorStatus("422"), 500);
});
